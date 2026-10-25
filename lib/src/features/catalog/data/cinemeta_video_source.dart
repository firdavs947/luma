import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/media_item.dart';
import '../domain/video_source.dart';

/// Каталог фильмов и сериалов на базе Cinemeta (метаданные Stremio).
///
/// Почему этот источник:
///  * не нужен API-ключ и регистрация;
///  * есть годовые ленты, поэтому новые релизы приходят сразу, как только
///    появляются в базе IMDb;
///  * каждая запись содержит описание, жанры, актёров, режиссёров, рейтинг
///    IMDb, дату выхода и официальный трейлер на YouTube;
///  * постеры, фоны и логотипы берутся с Metahub в высоком разрешении
///    (`poster/large` — 780×1170, `background/large` — 1920×1080), поэтому
///    обложки не растягиваются из миниатюр и не выглядят пиксельными.
///
/// Полные новые фильмы защищены авторским правом, поэтому в приложении для
/// них открывается официальный трейлер. Полные версии бесплатно доступны
/// для общественного достояния — этим занимается `ArchiveVideoSource`.
class CinemetaVideoSource extends VideoSource {
  CinemetaVideoSource({
    http.Client? client,
    this.cacheTtl = const Duration(minutes: 10),
  }) : _client = client ?? http.Client();

  final http.Client _client;

  /// Время жизни кэша: каталог не дёргает сеть на каждую перерисовку,
  /// но новые релизы подхватываются в пределах десяти минут.
  final Duration cacheTtl;

  static const _catalogBase = 'https://cinemeta-catalogs.strem.io/top/catalog';
  static const _searchBase = 'https://v3-cinemeta.strem.io/catalog';
  static const _metaBase = 'https://v3-cinemeta.strem.io/meta';
  static const _posterBase = 'https://images.metahub.space/poster/large';
  static const _backdropBase =
      'https://images.metahub.space/background/large';
  static const _logoBase = 'https://images.metahub.space/logo/medium';

  static const _animationGenre = 'Animation';
  static const _timeout = Duration(seconds: 15);

  final Map<String, _CinemetaCacheEntry> _cache = {};

  @override
  Future<List<MediaItem>> featured() async {
    // Новинки по всем направлениям грузятся параллельно: главный экран
    // получает свежие фильмы, сериалы и мультфильмы за один заход.
    final pages = await Future.wait([
      byCategory(MediaCategory.movies, sort: VideoSort.newest, limit: 16),
      byCategory(MediaCategory.series, sort: VideoSort.newest, limit: 16),
      byCategory(MediaCategory.cartoons, sort: VideoSort.newest, limit: 12),
    ]);
    return _interleave(pages);
  }

  @override
  Future<List<MediaItem>> byCategory(
    MediaCategory category, {
    VideoSort sort = VideoSort.popular,
    int limit = 24,
    int page = 1,
  }) async {
    return switch (category) {
      MediaCategory.movies => _categoryFeed(
        type: 'movie',
        category: category,
        sort: sort,
        limit: limit,
        page: page,
      ),
      MediaCategory.series => _categoryFeed(
        type: 'series',
        category: category,
        sort: sort,
        limit: limit,
        page: page,
      ),
      MediaCategory.cartoons => _cartoonFeed(
        sort: sort,
        limit: limit,
        page: page,
      ),
      MediaCategory.anime || MediaCategory.music => const [],
    };
  }

  /// Лента одного типа без мультфильмов: анимация вынесена в отдельный
  /// раздел, чтобы одна и та же запись не попадала в два ряда сразу.
  Future<List<MediaItem>> _categoryFeed({
    required String type,
    required MediaCategory category,
    required VideoSort sort,
    required int limit,
    required int page,
  }) async {
    if (page > 1 && (sort == VideoSort.oldest || sort == VideoSort.title)) {
      return const [];
    }

    final catalog = sort == VideoSort.newest ? 'year' : 'top';
    final skip = (page - 1) * limit;
    final metas = await _catalog(type: type, catalog: catalog, skip: skip);

    final items = <MediaItem>[];
    for (final meta in metas) {
      final genres = _stringList(meta['genres'] ?? meta['genre']);
      if (genres.contains(_animationGenre)) continue;

      final item = _toItem(meta, category: category);
      if (item != null) items.add(item);
    }

    _sort(items, sort);
    return items.take(limit).toList();
  }

  /// Мультфильмы: анимационные фильмы и анимационные сериалы из Cinemeta.
  ///
  /// Годовой ленты с жанром у сервиса нет, поэтому «сначала новые» строится
  /// сортировкой популярной ленты по дате выхода — свежие релизы всё равно
  /// оказываются в начале.
  Future<List<MediaItem>> _cartoonFeed({
    required VideoSort sort,
    required int limit,
    required int page,
  }) async {
    if (page > 1 && (sort == VideoSort.oldest || sort == VideoSort.title)) {
      return const [];
    }

    final skip = (page - 1) * limit;
    final pages = await Future.wait([
      _catalog(
        type: 'movie',
        catalog: 'top',
        genre: _animationGenre,
        skip: skip,
      ),
      _catalog(
        type: 'series',
        catalog: 'top',
        genre: _animationGenre,
        skip: skip,
      ),
    ]);

    final seen = <String>{};
    final items = <MediaItem>[];
    for (final metas in pages) {
      for (final meta in metas) {
        final type = '${meta['type'] ?? 'movie'}';
        final item = _toItem(
          meta,
          category: MediaCategory.cartoons,
          type: type,
        );
        if (item == null) continue;
        if (seen.add(item.id)) items.add(item);
      }
    }

    if (sort == VideoSort.popular) {
      // Чередуем фильмы и сериалы, чтобы лента не выглядела блоками.
      final movies = items.where((item) => item.id.startsWith('cm-movie-'));
      final series = items.where((item) => item.id.startsWith('cm-series-'));
      items
        ..clear()
        ..addAll(_interleave([movies.toList(), series.toList()]));
    } else {
      _sort(items, sort);
    }

    return items.take(limit).toList();
  }

  @override
  Future<List<MediaItem>> search(
    String query, {
    int limit = 24,
    int page = 1,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || page > 1) return const [];

    final pages = await Future.wait([
      _searchType('movie', trimmed),
      _searchType('series', trimmed),
    ]);

    final seen = <String>{};
    final items = <MediaItem>[];
    for (final metas in pages) {
      for (final meta in metas) {
        final type = '${meta['type'] ?? 'movie'}';
        final genres = _stringList(meta['genres'] ?? meta['genre']);
        final isAnimation = genres.contains(_animationGenre);
        final category = isAnimation
            ? MediaCategory.cartoons
            : type == 'series'
            ? MediaCategory.series
            : MediaCategory.movies;

        final item = _toItem(meta, category: category, type: type);
        if (item == null) continue;
        if (seen.add(item.id)) items.add(item);
      }
    }

    items.sort((a, b) {
      final score = b.displayScore.compareTo(a.displayScore);
      return score != 0 ? score : b.popularity.compareTo(a.popularity);
    });
    return items.take(limit).toList();
  }

  @override
  Future<VideoStream?> resolveStream(MediaItem item) async {
    final trailerId = item.trailerId;
    if (trailerId == null || trailerId.isEmpty) return null;

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

  @override
  Future<MediaItem> enrich(MediaItem item) async {
    final imdb = item.externalId;
    if (imdb == null || imdb.isEmpty) return item;

    final type = item.id.startsWith('cm-series-') ? 'series' : 'movie';
    final json = await _getJson('$_metaBase/$type/$imdb.json');
    final meta = json?['meta'];
    if (meta is! Map) return item;

    final enriched = _toItem(
      meta.cast<String, dynamic>(),
      category: item.category,
      type: type,
    );
    if (enriched == null) return item;

    return enriched.copyWith(
      isFavorite: item.isFavorite,
      progress: item.progress,
    );
  }

  // ───────────────────────── Сетевой слой ─────────────────────────

  Future<List<Map<String, dynamic>>> _catalog({
    required String type,
    required String catalog,
    int skip = 0,
    String? genre,
  }) async {
    final extras = <String>[
      if (genre != null) 'genre=$genre',
      if (skip > 0) 'skip=$skip',
    ];
    final suffix = extras.isEmpty ? '' : '/${extras.join('&')}';
    final json = await _getJson('$_catalogBase/$type/$catalog$suffix.json');
    return _metas(json);
  }

  Future<List<Map<String, dynamic>>> _searchType(
    String type,
    String query,
  ) async {
    final encoded = Uri.encodeComponent(query);
    final json = await _getJson(
      '$_searchBase/$type/top/search=$encoded.json',
    );
    return _metas(json);
  }

  List<Map<String, dynamic>> _metas(Map<String, dynamic>? json) {
    final metas = json?['metas'];
    if (metas is! List) return const [];
    return [
      for (final meta in metas)
        if (meta is Map) meta.cast<String, dynamic>(),
    ];
  }

  Future<Map<String, dynamic>?> _getJson(String url) async {
    final cached = _cache[url];
    if (cached != null && !cached.isExpired(cacheTtl)) return cached.json;

    try {
      final response = await _client.get(Uri.parse(url)).timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return cached?.json;
      }

      final decoded = json.decode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (decoded is! Map) return cached?.json;

      final map = decoded.cast<String, dynamic>();
      _cache[url] = _CinemetaCacheEntry(map, DateTime.now());
      return map;
    } on Exception {
      // Сеть недоступна — отдаём последний удачный ответ, если он есть.
      return cached?.json;
    }
  }

  // ───────────────────────── Маппинг ─────────────────────────

  MediaItem? _toItem(
    Map<String, dynamic> meta, {
    required MediaCategory category,
    String? type,
  }) {
    final imdb = '${meta['imdb_id'] ?? meta['id'] ?? ''}'.trim();
    if (!imdb.startsWith('tt')) return null;

    final trailerId = _trailerId(meta);
    if (trailerId == null) return null;

    final title = _clean('${meta['name'] ?? ''}');
    if (title.isEmpty) return null;

    final kind = type ?? '${meta['type'] ?? 'movie'}';
    final isSeries = kind == 'series';
    final genres = _stringList(meta['genres'] ?? meta['genre']);
    final cast = _stringList(meta['cast']).take(5).toList();
    final directors = _stringList(meta['director']).take(3).toList();
    final country = _clean('${meta['country'] ?? ''}');
    final year = _firstYear(meta);
    final score = double.tryParse('${meta['imdbRating'] ?? ''}') ?? 0;
    final released = _isoDate('${meta['released'] ?? ''}');
    final runtime = _runtimeLabel('${meta['runtime'] ?? ''}', isSeries);
    final popularity = ((double.tryParse('${meta['popularity'] ?? ''}') ?? 0) *
            1000)
        .round();

    return MediaItem(
      id: 'cm-$kind-$imdb',
      externalId: imdb,
      imdbId: imdb,
      title: title,
      subtitle: directors.isNotEmpty
          ? directors.first
          : genres.isNotEmpty
          ? genres.first
          : isSeries
          ? 'Сериал'
          : 'Фильм',
      category: category,
      year: year,
      durationLabel: runtime,
      rating: score / 2,
      score: score,
      description: _clean('${meta['description'] ?? ''}'),
      imageUrl: '$_posterBase/$imdb/img',
      backdropUrl: '$_backdropBase/$imdb/img',
      logoUrl: '$_logoBase/$imdb/img',
      trailerId: trailerId,
      origin: MediaOrigin.cinemeta,
      genres: genres,
      cast: cast,
      directors: directors,
      country: country.isEmpty ? null : country,
      releaseDate: released,
      popularity: popularity,
    );
  }

  /// Официальный трейлер: сначала обычный список, затем `trailerStreams`.
  static String? _trailerId(Map<String, dynamic> meta) {
    final trailers = meta['trailers'];
    if (trailers is List) {
      for (final trailer in trailers) {
        if (trailer is Map) {
          final source = '${trailer['source'] ?? ''}'.trim();
          if (source.isNotEmpty) return source;
        }
      }
    }

    final streams = meta['trailerStreams'];
    if (streams is List) {
      for (final stream in streams) {
        if (stream is Map) {
          final id = '${stream['ytId'] ?? ''}'.trim();
          if (id.isNotEmpty) return id;
        }
      }
    }
    return null;
  }

  static void _sort(List<MediaItem> items, VideoSort sort) {
    switch (sort) {
      case VideoSort.popular:
        break;
      case VideoSort.newest:
        items.sort((a, b) => _releaseKey(b).compareTo(_releaseKey(a)));
      case VideoSort.oldest:
        items.sort((a, b) => _releaseKey(a).compareTo(_releaseKey(b)));
      case VideoSort.title:
        items.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
    }
  }

  static int _releaseKey(MediaItem item) {
    final released = DateTime.tryParse(item.releaseDate ?? '');
    if (released != null) return released.millisecondsSinceEpoch;
    return item.releaseYear * 10000 + 101;
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

  static int _firstYear(Map<String, dynamic> meta) {
    final raw = '${meta['releaseInfo'] ?? meta['year'] ?? meta['released'] ?? ''}';
    final match = RegExp(r'(\d{4})').firstMatch(raw);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  static String? _isoDate(String raw) {
    final date = DateTime.tryParse(raw);
    if (date == null) return null;
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static String _runtimeLabel(String raw, bool isSeries) {
    final match = RegExp(r'(\d+)').firstMatch(raw);
    if (match == null) return '';
    final minutes = int.parse(match.group(1)!);
    if (minutes <= 0) return '';

    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    final base = hours > 0
        ? rest > 0
              ? '$hoursч $restм'
              : '$hoursч'
        : '$restм';
    return isSeries ? '$base/эп' : base;
  }

  static List<String> _stringList(Object? raw) {
    if (raw is List) {
      return [
        for (final value in raw)
          if ('$value'.trim().isNotEmpty) _clean('$value'),
      ];
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return [_clean(raw)];
    }
    return const [];
  }

  static String _clean(String value) {
    return value
        .replaceAll(RegExp('<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class _CinemetaCacheEntry {
  _CinemetaCacheEntry(this.json, this.storedAt);

  final Map<String, dynamic> json;
  final DateTime storedAt;

  bool isExpired(Duration ttl) => DateTime.now().difference(storedAt) > ttl;
}
