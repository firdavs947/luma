import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/audio_import_exception.dart';
import '../domain/imported_audio.dart';
import '../domain/imported_audio_repository.dart';
import 'library_state.dart';

/// Cubit библиотеки загруженной музыки.
///
/// Экраны не работают с файловой системой и диалогами выбора напрямую:
/// они просят Cubit выбрать файл, добавить трек или удалить его, а сами
/// только показывают состояние. Благодаря этому логика импорта тестируется
/// без интерфейса, а замена хранилища не затрагивает UI.
class LibraryCubit extends Cubit<LibraryState> {
  LibraryCubit(this._repository) : super(const LibraryState());

  final ImportedAudioRepository _repository;

  /// Поддерживает ли платформа импорт файлов.
  bool get isSupported => _repository.isSupported;

  /// Загружает список ранее импортированных треков.
  Future<void> load() async {
    emit(
      state.copyWith(
        status: LibraryStatus.loading,
        isSupported: _repository.isSupported,
      ),
    );

    final tracks = await _repository.load();
    if (isClosed) return;

    emit(state.copyWith(status: LibraryStatus.ready, tracks: tracks));
  }

  /// Открывает системный выбор аудиофайла.
  Future<AudioFileCandidate?> pickAudio() => _repository.pickAudio();

  /// Открывает системный выбор обложки.
  Future<AudioFileCandidate?> pickCover() => _repository.pickCover();

  /// Сохраняет трек и добавляет его в начало списка.
  ///
  /// Бросает [AudioImportException] с текстом для пользователя, если файл
  /// не проходит проверку.
  Future<ImportedAudio> addTrack({
    required AudioFileCandidate audio,
    required String title,
    required String artist,
    AudioFileCandidate? cover,
  }) async {
    if (state.isImporting) {
      throw const AudioImportException('Предыдущий файл ещё обрабатывается.');
    }

    emit(state.copyWith(isImporting: true));
    try {
      final track = await _repository.importTrack(
        audio: audio,
        title: title,
        artist: artist,
        cover: cover,
      );
      if (!isClosed) {
        emit(state.copyWith(tracks: [track, ...state.tracks]));
      }
      return track;
    } finally {
      if (!isClosed) emit(state.copyWith(isImporting: false));
    }
  }

  /// Удаляет трек вместе с его файлами.
  Future<void> remove(String id) async {
    await _repository.remove(id);
    if (isClosed) return;

    final tracks = [...state.tracks]..removeWhere((track) => track.id == id);
    emit(state.copyWith(tracks: tracks));
  }
}
