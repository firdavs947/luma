import 'package:equatable/equatable.dart';

import '../domain/imported_audio.dart';

/// Этап загрузки библиотеки импортированной музыки.
enum LibraryStatus { idle, loading, ready }

/// Состояние раздела «Загрузки»: импортированные треки и ход импорта.
class LibraryState extends Equatable {
  const LibraryState({
    this.status = LibraryStatus.idle,
    this.tracks = const [],
    this.isSupported = true,
    this.isImporting = false,
  });

  final LibraryStatus status;

  /// Треки, добавленные пользователем, в порядке убывания даты.
  final List<ImportedAudio> tracks;

  /// Доступна ли загрузка файлов на текущей платформе.
  final bool isSupported;

  /// Идёт ли обработка файла прямо сейчас.
  final bool isImporting;

  /// Первая загрузка ещё не завершена.
  bool get isLoading => status != LibraryStatus.ready;

  /// Библиотека пуста: загрузка завершена, но треков нет.
  bool get isEmpty => status == LibraryStatus.ready && tracks.isEmpty;

  LibraryState copyWith({
    LibraryStatus? status,
    List<ImportedAudio>? tracks,
    bool? isSupported,
    bool? isImporting,
  }) {
    return LibraryState(
      status: status ?? this.status,
      tracks: tracks ?? this.tracks,
      isSupported: isSupported ?? this.isSupported,
      isImporting: isImporting ?? this.isImporting,
    );
  }

  @override
  List<Object?> get props => [status, tracks, isSupported, isImporting];
}
