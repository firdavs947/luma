import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../genius/domain/genius_exception.dart';
import '../../../genius/domain/genius_models.dart';
import '../../../genius/domain/genius_repository.dart';
import 'album_state.dart';

/// Cubit экрана треклиста: загружает альбом по идентификатору.
///
/// Источник приводит альбом к [`MusicCollection`], поэтому экран не знает,
/// что именно вернул Genius, и остаётся неизменным при смене бэкенда.
class AlbumCubit extends Cubit<AlbumState> {
  AlbumCubit({
    required this._repository,
    this.albumId,
  }) : super(const AlbumState());

  final GeniusRepository _repository;

  /// Идентификатор альбома в источнике музыки.
  final String? albumId;

  Future<void> load() async {
    emit(const AlbumState(status: AlbumStatus.loading));

    try {
      final collection = await _loadCollection();
      if (isClosed) return;
      emit(AlbumState(status: AlbumStatus.ready, collection: collection));
    } on GeniusException catch (error) {
      if (isClosed) return;
      emit(AlbumState(status: AlbumStatus.error, error: error.message));
    }
  }

  Future<MusicCollection> _loadCollection() async {
    final album = albumId;
    if (album == null) {
      throw const GeniusException(0, 'Не указана подборка для загрузки');
    }
    return MusicCollection.fromAlbum(await _repository.getAlbum(album));
  }
}
