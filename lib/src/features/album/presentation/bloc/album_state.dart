import 'package:equatable/equatable.dart';

import '../../../genius/domain/genius_models.dart';

/// Этап загрузки экрана треклиста.
enum AlbumStatus { loading, ready, error }

/// Состояние экрана треклиста: данные подборки либо причина сбоя.
class AlbumState extends Equatable {
  const AlbumState({
    this.status = AlbumStatus.loading,
    this.collection,
    this.error,
  });

  final AlbumStatus status;

  /// Загруженная подборка вместе с треками.
  final MusicCollection? collection;

  /// Сообщение об ошибке для пользователя.
  final String? error;

  @override
  List<Object?> get props => [status, collection, error];
}
