import 'package:flutter/foundation.dart';

import 'audio_import_rules.dart';
import 'audio_metadata.dart';
import 'imported_audio.dart';

/// Файл, выбранный пользователем в системном диалоге.
@immutable
class AudioFileCandidate {
  const AudioFileCandidate({
    required this.name,
    required this.sizeBytes,
    required this.bytes,
    this.metadata,
  });

  /// Исходное имя файла вместе с расширением.
  final String name;
  final int sizeBytes;

  /// Содержимое файла.
  final Uint8List bytes;

  /// Метаданные, полученные при выборе аудиофайла (для обложки — `null`).
  ///
  /// Благодаря им разбор заголовка выполняется один раз: результат сразу
  /// показывается пользователю и позже сохраняется в библиотеке.
  final AudioMetadata? metadata;

  /// Расширение файла в нижнем регистре.
  String get extension => AudioImportRules.extensionOf(name);

  /// Размер файла в удобном для чтения виде.
  String get sizeLabel => AudioImportRules.formatBytes(sizeBytes);
}

/// Контракт библиотеки импортированной музыки.
///
/// В проекте нет серверной части, поэтому шаги серверной обработки —
/// приём файла, проверка целостности, извлечение метаданных и хранение —
/// выполняются на устройстве: файл копируется в приватный каталог
/// приложения, а метаданные попадают в манифест библиотеки.
abstract interface class ImportedAudioRepository {
  /// Поддерживает ли платформа работу с локальными файлами.
  bool get isSupported;

  /// Ранее импортированные треки в порядке добавления.
  Future<List<ImportedAudio>> load();

  /// Открывает системный выбор аудиофайла.
  ///
  /// Возвращает `null`, если пользователь отменил выбор, и бросает
  /// `AudioImportException`, если файл не проходит требования.
  Future<AudioFileCandidate?> pickAudio();

  /// Открывает системный выбор обложки. `null` — пользователь отменил выбор.
  Future<AudioFileCandidate?> pickCover();

  /// Проверяет файл, сохраняет его и записывает метаданные в библиотеку.
  Future<ImportedAudio> importTrack({
    required AudioFileCandidate audio,
    required String title,
    required String artist,
    AudioFileCandidate? cover,
  });

  /// Удаляет трек вместе с его файлами.
  Future<void> remove(String id);
}
