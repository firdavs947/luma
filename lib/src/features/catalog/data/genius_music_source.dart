import '../../genius/domain/genius_exception.dart';
import '../../genius/domain/genius_models.dart';
import '../../genius/domain/genius_repository.dart';
import '../domain/media_item.dart';
import '../domain/music_source.dart';
import 'genius_mapper.dart';

/// Источник музыки из Genius с автоматическим фолбэком на локальный каталог.
///
/// Если токен не задан, Genius недоступен или ответ пуст, приложение
/// продолжает работать: сервис не должен падать из-за внешней зависимости —
/// это обязательное требование магазинов приложений.
class GeniusMusicSource implements MusicSource {
  GeniusMusicSource({
    required this._repository,
    required this._fallback,
  });

  /// Исполнители, из которых собирается лента.
  ///
  /// Genius не умеет отдавать «подборки» или «жанры»: его выдача строится
  /// вокруг песен и исполнителей. Поэтому лента собирается из популярных
  /// песен известных артистов — по одной странице на каждого.
  static const _seeds = [
    '8351', // Coldplay
    '2358', // The Weeknd
    '604', // Radiohead
    '2300', // Adele
    '29472', // Imagine Dragons
    '1581', // Linkin Park
    '615550', // Billie Eilish
    '45', // Eminem
  ];

  /// Сколько песен запрашивать у каждого исполнителя.
  static const _songsPerSeed = 12;

  /// Сколько исполнителей дают альбом для ленты.
  ///
  /// Альбом стоит трёх запросов (`/songs/{id}`, `/albums/{id}`,
  /// `/albums/{id}/tracks`), поэтому их количество ограничено — при этом
  /// карточки-альбомы остаются в ленте, и экран треклиста доступен.
  static const _albumSeeds = 4;

  /// Предел числа треков в ленте: главный экран должен оставаться отзывчивым.
  static const _maxTracks = 48;

  /// Общий предел размера ленты.
  static const _maxItems = 60;

  final GeniusRepository _repository;
  final MusicSource _fallback;

  @override
  Future<List<MediaItem>> featured() async {
    if (!_repository.isConfigured) return _fallback.featured();

    try {
      // Песни всех исполнителей запрашиваются параллельно: лента собирается
      // одним проходом, а не восемью последовательными ожиданиями сети.
      final batches = await Future.wait(_seeds.map(_songsOf));

      final songs = _dedupeSongs(batches.expand((batch) => batch).toList());
      final tracks = songs
          .take(_maxTracks)
          .map((song) => mediaItemFromTrack(song))
          .toList();

      final albums = await _resolveAlbums(batches);

      // Альбомы и треки перемежаются, чтобы в ленте были и подборки с
      // треклистом, и треки для мгновенного воспроизведения.
      final items = _dedupe([
        ..._interleave([
          albums.map((album) => mediaItemFromAlbum(album)).toList(),
          tracks,
        ], _maxItems),
      ]);

      if (items.isNotEmpty) return items;
      return await _fallback.featured();
    } on GeniusException {
      return _fallback.featured();
    }
  }

  @override
  Future<MusicSearchPage> search(String query, {int offset = 0}) async {
    if (!_repository.isConfigured) {
      return _fallback.search(query, offset: offset);
    }

    // Genius не умеет постраничный поиск: `/search` отдаёт не более десяти
    // песен и не принимает смещение, поэтому «Показать ещё» не предлагается.
    if (offset > 0) return MusicSearchPage.empty;

    try {
      final songs = await _repository.searchSongs(query);
      final items = songs.map((song) => mediaItemFromTrack(song)).toList();
      return MusicSearchPage(items: items, hasMore: false);
    } on GeniusException {
      return _fallback.search(query, offset: offset);
    }
  }

  /// Популярные песни исполнителя; при сбое — пустой список.
  ///
  /// Один недоступный исполнитель не должен срывать всю ленту.
  Future<List<GeniusSong>> _songsOf(String artistId) async {
    try {
      return await _repository.songsByArtist(artistId, perPage: _songsPerSeed);
    } on GeniusException {
      return const [];
    }
  }

  /// Достаёт альбомы для первых [_albumSeeds] исполнителей.
  Future<List<GeniusAlbum>> _resolveAlbums(
    List<List<GeniusSong>> batches,
  ) async {
    final resolved = await Future.wait(
      batches.take(_albumSeeds).map(_albumOf),
    );

    final seen = <String>{};
    final albums = <GeniusAlbum>[];

    for (final album in resolved) {
      if (album == null || album.tracks.isEmpty) continue;
      if (seen.add(album.id)) albums.add(album);
    }
    return albums;
  }

  /// Альбом, к которому относится первая песня страницы.
  Future<GeniusAlbum?> _albumOf(List<GeniusSong> batch) async {
    if (batch.isEmpty) return null;

    try {
      // В выдаче `/artists/{id}/songs` альбома нет — узнаём его
      // идентификатор отдельным запросом к песне.
      final detail = await _repository.getSong(batch.first.id);
      final albumId = detail.albumId;
      if (albumId == null || albumId.isEmpty) return null;
      return await _repository.getAlbum(albumId);
    } on GeniusException {
      return null;
    }
  }

  /// Берёт элементы из списков по кругу, пока не наберёт [limit].
  List<T> _interleave<T>(List<List<T>> batches, int limit) {
    final result = <T>[];
    var index = 0;

    while (result.length < limit) {
      var added = false;

      for (final batch in batches) {
        if (index >= batch.length) continue;
        result.add(batch[index]);
        added = true;
        if (result.length >= limit) break;
      }

      if (!added) break;
      index++;
    }

    return result;
  }

  /// Убирает дубли песен: один и тот же трек может встретиться у разных
  /// исполнителей (совместные записи, каверы).
  List<GeniusSong> _dedupeSongs(List<GeniusSong> songs) {
    final seen = <String>{};
    return [
      for (final song in songs)
        if (seen.add(song.id)) song,
    ];
  }

  /// Убирает дубли элементов каталога по идентификатору.
  List<MediaItem> _dedupe(List<MediaItem> items) {
    final seen = <String>{};
    return [
      for (final item in items)
        if (seen.add(item.id)) item,
    ];
  }
}
