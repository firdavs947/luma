import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/files/file_storage.dart';
import '../domain/audio_import_exception.dart';
import '../domain/audio_import_rules.dart';
import '../domain/audio_metadata.dart';
import '../domain/imported_audio.dart';
import '../domain/imported_audio_repository.dart';
import 'audio_file_inspector.dart';
import 'preview_generator.dart';

/// Библиотека импортированной музыки на устройстве.
///
/// Серверной части у LUMA нет, поэтому весь конвейер обработки выполняется
/// локально и повторяет шаги серверного приёма файла:
///
///  1. системный выбор файла;
///  2. проверка формата и размера по [AudioImportRules];
///  3. проверка целостности контейнера и извлечение метаданных
///     ([AudioFileInspector] заодно отсекает файлы, замаскированные под
///     музыку);
///  4. сборка короткого превью ([PreviewGenerator]);
///  5. запись файлов в приватный каталог приложения и метаданных — в
///     манифест библиотеки.
///
/// Файлы лежат в приватном каталоге ([FileStorage]), недоступном другим
/// приложениям и файловым менеджерам, а в манифесте хранятся только ссылки
/// и метаданные — скачать трек извне нельзя.
class LocalImportedAudioRepository implements ImportedAudioRepository {
  LocalImportedAudioRepository(this._storage);

  /// Ключ манифеста библиотеки в локальных настройках.
  static const String manifestKey = 'luma_library_manifest_v1';

  final FileStorage _storage;
  static const AudioFileInspector _inspector = AudioFileInspector();
  final Random _random = Random();

  /// Очередь импорта.
  ///
  /// Файлы обрабатываются строго по одному: крупный трек не может
  /// конкурировать за память со следующим, поэтому несколько одновременных
  /// добавлений не приводят к пиковому потреблению памяти и гонке за
  /// манифестом.
  Future<void> _queue = Future<void>.value();

  @override
  bool get isSupported => _storage.isSupported;

  @override
  Future<List<ImportedAudio>> load() async {
    final tracks = await _read();

    // После переустановки приложения файлы пропадают, а манифест остаётся —
    // такие записи убираем, чтобы в интерфейсе не появлялись «битые» треки.
    if (!isSupported) return tracks;

    final alive = <ImportedAudio>[];
    for (final track in tracks) {
      if (await _storage.exists(track.audioLocation)) alive.add(track);
    }
    if (alive.length != tracks.length) await _write(alive);

    return alive;
  }

  @override
  Future<AudioFileCandidate?> pickAudio() async {
    _requireSupport();

    final file = await FilePicker.pickFile(
      dialogTitle: 'Выберите аудиофайл',
      type: FileType.custom,
      allowedExtensions: AudioImportRules.audioExtensions,
    );
    if (file == null) return null; // Пользователь закрыл диалог.

    // Размер известен до чтения — крупный файл отсекается сразу, без
    // загрузки в память.
    final declaredSize = file.lengthSync();
    if (declaredSize != null && declaredSize > 0) {
      final error = AudioImportRules.validateAudio(
        fileName: file.name,
        sizeBytes: declaredSize,
      );
      if (error != null) throw AudioImportException(error);
    }

    return _audioCandidate(name: file.name, bytes: await file.readAsBytes());
  }

  @override
  Future<AudioFileCandidate?> pickCover() async {
    _requireSupport();

    final file = await FilePicker.pickFile(
      dialogTitle: 'Выберите обложку',
      type: FileType.custom,
      allowedExtensions: AudioImportRules.coverExtensions,
    );
    if (file == null) return null;

    final bytes = await file.readAsBytes();
    final error = AudioImportRules.validateCover(
      fileName: file.name,
      sizeBytes: bytes.length,
    );
    if (error != null) throw AudioImportException(error);

    return AudioFileCandidate(
      name: file.name,
      sizeBytes: bytes.length,
      bytes: bytes,
    );
  }

  @override
  Future<ImportedAudio> importTrack({
    required AudioFileCandidate audio,
    required String title,
    required String artist,
    AudioFileCandidate? cover,
  }) {
    return _serialize(() async {
      // Повторная проверка: файл мог измениться между выбором и сохранением.
      final error = AudioImportRules.validateAudio(
        fileName: audio.name,
        sizeBytes: audio.sizeBytes,
      );
      if (error != null) throw AudioImportException(error);

      final metadata =
          audio.metadata ?? _inspector.inspect(bytes: audio.bytes, fileName: audio.name);

      final id = _newId();
      final extension = audio.extension;
      final saved = <String>[];

      try {
        final audioLocation = await _storage.save(
          fileName: '$id.$extension',
          bytes: audio.bytes,
        );
        saved.add(audioLocation);

        String? previewLocation;
        final preview = PreviewGenerator.build(
          bytes: audio.bytes,
          fileName: audio.name,
        );
        if (preview != null) {
          previewLocation = await _storage.save(
            fileName: '$id.preview.$extension',
            bytes: preview,
          );
          saved.add(previewLocation);
        }

        String? coverLocation;
        if (cover != null) {
          coverLocation = await _storage.save(
            fileName: '$id.cover.${cover.extension}',
            bytes: cover.bytes,
          );
          saved.add(coverLocation);
        }

        final track = ImportedAudio(
          id: id,
          title: _titleOf(title, audio.name),
          artist: artist.trim(),
          audioLocation: audioLocation,
          previewLocation: previewLocation,
          coverLocation: coverLocation,
          metadata: metadata,
          sizeBytes: audio.sizeBytes,
          addedAt: DateTime.now(),
        );

        await _write([track, ...await _read()]);
        return track;
      } on Exception {
        // Запись не состоялась — не оставляем «мусор» в каталоге.
        for (final location in saved) {
          await _storage.delete(location);
        }
        rethrow;
      }
    });
  }

  @override
  Future<void> remove(String id) async {
    final tracks = await _read();
    final index = tracks.indexWhere((track) => track.id == id);
    if (index == -1) return;

    final track = tracks[index];
    tracks.removeAt(index);
    await _write(tracks);

    await _storage.delete(track.audioLocation);
    if (track.previewLocation != null) {
      await _storage.delete(track.previewLocation!);
    }
    if (track.coverLocation != null) {
      await _storage.delete(track.coverLocation!);
    }
  }

  // ───────────────────────── Вспомогательные методы ─────────────────────────

  /// Собирает кандидата, проверяя формат, размер и содержимое файла.
  AudioFileCandidate _audioCandidate({
    required String name,
    required Uint8List bytes,
  }) {
    final error = AudioImportRules.validateAudio(
      fileName: name,
      sizeBytes: bytes.length,
    );
    if (error != null) throw AudioImportException(error);

    final AudioMetadata metadata;
    try {
      metadata = _inspector.inspect(bytes: bytes, fileName: name);
    } on AudioImportException {
      rethrow;
    } on Exception {
      throw const AudioImportException(
        'Не удалось прочитать аудиофайл: возможно, он повреждён.',
      );
    }

    return AudioFileCandidate(
      name: name,
      sizeBytes: bytes.length,
      bytes: bytes,
      metadata: metadata,
    );
  }

  /// Название трека: введённое пользователем или имя файла без расширения.
  String _titleOf(String title, String fileName) {
    final trimmed = title.trim();
    if (trimmed.isNotEmpty) return trimmed;

    final dot = fileName.lastIndexOf('.');
    final base = dot <= 0 ? fileName : fileName.substring(0, dot);
    return base.trim().isEmpty ? 'Без названия' : base.trim();
  }

  /// Уникальный идентификатор записи: отделяет её от контента источника.
  String _newId() {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final salt = _random.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return 'local-$stamp-$salt';
  }

  void _requireSupport() {
    if (isSupported) return;
    throw const AudioImportException(
      'Загрузка аудиофайлов доступна в мобильном приложении LUMA.',
    );
  }

  /// Ставит операцию в очередь импорта, чтобы файлы не обрабатывались
  /// параллельно.
  Future<T> _serialize<T>(Future<T> Function() action) {
    final completer = Completer<T>();

    _queue = _queue.then((_) async {
      try {
        completer.complete(await action());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });

    return completer.future;
  }

  /// Читает манифест библиотеки; повреждённые записи пропускаются.
  Future<List<ImportedAudio>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(manifestKey);
    if (raw == null || raw.isEmpty) return [];

    final Object? decoded;
    try {
      decoded = json.decode(raw);
    } on FormatException {
      return [];
    }
    if (decoded is! List) return [];

    final tracks = <ImportedAudio>[];
    for (final entry in decoded) {
      if (entry is! Map) continue;
      try {
        tracks.add(ImportedAudio.fromJson(Map<String, dynamic>.from(entry)));
      } on Object {
        // Запись повреждена — пропускаем её, остальные остаются доступны.
      }
    }
    return tracks;
  }

  /// Сохраняет манифест библиотеки.
  Future<void> _write(List<ImportedAudio> tracks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      manifestKey,
      json.encode([for (final track in tracks) track.toJson()]),
    );
  }
}
