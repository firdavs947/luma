import '../domain/media_item.dart';
import '../domain/video_source.dart';
import 'anilist_video_source.dart';
import 'archive_video_source.dart';
import 'cinemeta_video_source.dart';

/// Единый источник видео, собранный из трёх бесплатных сервисов.
///
/// Распределение ролей:
///  * Cinemeta — свежие фильмы, сериалы и мультфильмы с официальными
///    трейлерами и полными метаданными IMDb;
///  * AniList — актуальный сезон аниме, рейтинги и трейлеры;
///  * Internet Archive — полные фильмы общественного достояния, которые
///    можно смотреть целиком.
///
/// Каталог не знает о разделении: он работает с одним [VideoSource].
/// Ошибка одного сервиса не ломает остальные: каждый вызов изолирован,
/// поэтому при сбое Cinemeta продолжает работать аниме и архив.
class AggregatedVideoSource extends VideoSource {
  AggregatedVideoSource({
    CinemetaVideoSource? cinemeta,
    AniListVideoSource? anilist,
    ArchiveVideoSource? archive,
  }) : _cinemeta = cinemeta ?? CinemetaVideoSource(),
       _anilist = anilist ?? AniListVideoSource(),
       _archive = archive ?? ArchiveVideoSource();

  final CinemetaVideoSource _cinemeta;
  final AniListVideoSource _anilist;
  final ArchiveVideoSource _archive;

  @override
  Future<List<MediaItem>> featured() async {
    final pages = await Future.wait([
      _safe(_cinemeta.featured()),
      _safe(_anilist.featured()),
      _safe(_archive.freeFull(limit: 10)),
    ]);

    final releaseFeed = _interleave([pages[0], pages[1]]);
    final freeFilms = pages[2];

    // Бесплатные полные фильмы идут вперемешку с новинками: в hero-карусели
    // и общих рядах рядом оказываются и свежий трейлер, и фильм, который
    // можно посмотреть целиком.
    final mixed = <MediaItem>[];
    var freeIndex = 0;
    for (var i = 0; i < releaseFeed.length; i++) {
      mixed.add(releaseFeed[i]);
      if ((i + 1) % 5 == 0 && freeIndex < freeFilms.length) {
        mixed.add(freeFilms[freeIndex++]);
      }
    }
    while (freeIndex < freeFilms.length) {
      mixed.add(freeFilms[freeIndex++]);
    }

    return _dedupe(mixed).take(40).toList();
  }

  @override
  Future<List<MediaItem>> byCategory(
    MediaCategory category, {
    VideoSort sort = VideoSort.popular,
    int limit = 24,
    int page = 1,
  }) async {
    final source = switch (category) {
      MediaCategory.movies ||
      MediaCategory.series ||
      MediaCategory.cartoons => _cinemeta,
      MediaCategory.anime => _anilist,
      MediaCategory.music => null,
    };
    if (source == null) return const [];

    return _safe(
      source.byCategory(category, sort: sort, limit: limit, page: page),
    );
  }

  @override
  Future<List<MediaItem>> search(
    String query, {
    int limit = 24,
    int page = 1,
  }) async {
    final results = await Future.wait([
      _safe(_cinemeta.search(query, limit: limit, page: page)),
      _safe(_anilist.search(query, limit: limit, page: page)),
      _safe(_archive.search(query, limit: limit, page: page)),
    ]);

    // Порядок источников задаёт приоритет при совпадении: карточка Cinemeta
    // богаче метаданными, архивная запись добавляет полную версию.
    final merged = <MediaItem>[];
    final seenImdb = <String>{};
    final seenIds = <String>{};

    for (final items in results) {
      for (final item in items) {
        final imdb = item.imdbId;
        if (imdb != null && imdb.isNotEmpty && !seenImdb.add(imdb)) continue;
        if (!seenIds.add(item.id)) continue;
        merged.add(item);
      }
    }

    merged.sort((a, b) {
      final score = b.displayScore.compareTo(a.displayScore);
      return score != 0 ? score : b.popularity.compareTo(a.popularity);
    });
    return merged.take(limit).toList();
  }

  @override
  Future<VideoStream?> resolveStream(MediaItem item) async {
    final stream = switch (item.origin) {
      MediaOrigin.archive => await _safeStream(_archive.resolveStream(item)),
      MediaOrigin.cinemeta => await _safeStream(_cinemeta.resolveStream(item)),
      MediaOrigin.anilist => await _safeStream(_anilist.resolveStream(item)),
      MediaOrigin.unknown => await _resolveUnknown(item),
    };
    return stream;
  }

  @override
  Future<MediaItem> enrich(MediaItem item) async {
    try {
      final future = switch (item.origin) {
        MediaOrigin.archive => _archive.enrich(item),
        MediaOrigin.cinemeta => _cinemeta.enrich(item),
        MediaOrigin.anilist => _anilist.enrich(item),
        MediaOrigin.unknown => _cinemeta.enrich(item),
      };
      return await future;
    } on Exception {
      return item;
    }
  }

  @override
  Future<MediaItem?> fullVersionOf(MediaItem item) async {
    if (item.origin == MediaOrigin.archive) return item;
    try {
      return await _archive.fullVersionOf(item);
    } on Exception {
      return null;
    }
  }

  @override
  Future<List<MediaItem>> freeFull({int limit = 24}) async {
    return _safe(_archive.freeFull(limit: limit));
  }

  /// Запись без известного источника: если есть трейлер, открываем его,
  /// иначе пробуем найти полную версию в архиве.
  Future<VideoStream?> _resolveUnknown(MediaItem item) async {
    final trailerId = item.trailerId;
    if (trailerId != null && trailerId.isNotEmpty) {
      final watchUrl = 'https://www.youtube.com/watch?v=$trailerId';
      return VideoStream(
        url: watchUrl,
        kind: PlaybackKind.trailer,
        youtubeId: trailerId,
        providerLabel: 'Официальный трейлер',
        pageUrl: watchUrl,
        mimeType: 'video/youtube',
      );
    }

    final full = await fullVersionOf(item);
    if (full == null) return null;
    return _safeStream(_archive.resolveStream(full));
  }

  static Future<List<MediaItem>> _safe(Future<List<MediaItem>> future) async {
    try {
      return await future;
    } catch (_) {
      return const [];
    }
  }

  static Future<VideoStream?> _safeStream(Future<VideoStream?> future) async {
    try {
      return await future;
    } catch (_) {
      return null;
    }
  }

  static List<MediaItem> _dedupe(List<MediaItem> items) {
    final seenIds = <String>{};
    final seenImdb = <String>{};
    return [
      for (final item in items)
        if (seenIds.add(item.id) &&
            (item.imdbId == null ||
                item.imdbId!.isEmpty ||
                seenImdb.add(item.imdbId!)))
          item,
    ];
  }

  static List<MediaItem> _interleave(List<List<MediaItem>> pages) {
    final result = <MediaItem>[];
    final longest = pages.fold<int>(
      0,
      (max, page) => page.length > max ? page.length : max,
    );
    for (var i = 0; i < longest; i++) {
      for (final page in pages) {
        if (i < page.length) result.add(page[i]);
      }
    }
    return result;
  }
}
