import '../../genius/domain/genius_models.dart';
import '../domain/media_item.dart';

/// Слой-адаптер: переводит модели Genius в единую модель каталога
/// [`MediaItem`].
///
/// Благодаря этому Genius ничего не знает о каталоге, а каталог — о Genius,
/// и обе части можно менять независимо. Интерфейс при этом не меняется:
/// экраны работают с `MediaItem` ровно так же, как и с прежним источником.
MediaItem mediaItemFromAlbum(GeniusAlbum album) {
  final tracks = album.totalTracks;
  final summary =
      tracks == 0 ? album.typeLabel : '$tracks ${_trackWord(tracks)}';

  return MediaItem(
    id: 'gn_album_${album.id}',
    title: album.name,
    subtitle: album.artistNames,
    category: MediaCategory.music,
    year: int.tryParse(album.releaseYear ?? '') ?? DateTime.now().year,
    durationLabel: summary,
    // У альбомов Genius нет пользовательского рейтинга — оценку не показываем.
    rating: 0,
    description: '${album.typeLabel} · $summary',
    imageUrl: album.coverArtUrl,
    albumId: album.id,
  );
}

/// Преобразует песню Genius в элемент каталога.
///
/// [collectionTitle] и [collectionImage] передаются, когда песня пришла из
/// треклиста: так подставляются название и обложка альбома.
///
/// У Genius нет ни длительности, ни аудио, поэтому:
///  * `durationLabel` показывает прочерк (см. `GeniusSong.durationLabel`);
///  * `previewUrl` остаётся пустым — плеер сам подберёт запись у
///    стримингового провайдера, поэтому звук и анимации продолжают работать.
MediaItem mediaItemFromTrack(
  GeniusSong track, {
  String? collectionTitle,
  String? collectionImage,
  int? year,
}) {
  return MediaItem(
    id: 'gn_song_${track.id}',
    title: track.title,
    subtitle: track.artistNames,
    category: MediaCategory.music,
    year: year ?? track.releaseYear ?? DateTime.now().year,
    durationLabel: track.durationLabel,
    rating: 0,
    description: collectionTitle ?? '',
    imageUrl: track.imageUrl ?? collectionImage,
    isTrack: true,
  );
}

/// Согласование слова «трек» с числом.
String _trackWord(int count) {
  final mod10 = count % 10;
  final mod100 = count % 100;

  if (mod10 == 1 && mod100 != 11) return 'трек';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return 'трека';
  return 'треков';
}
