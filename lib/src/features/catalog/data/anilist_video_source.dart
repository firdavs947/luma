import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/media_item.dart';
import '../domain/video_source.dart';

/// Каталог аниме на базе AniList GraphQL.
///
/// Почему этот источник:
///  * официальный открытый GraphQL-API без ключа и регистрации;
///  * текущий сезон отдаётся сразу, поэтому в разделе всегда есть аниме,
///    которое выходит прямо сейчас;
///  * обложки `extraLarge` (около 1000 px по высоте) и широкие баннеры
///    вместо растянутых миниатюр;
///  * у каждой записи есть рейтинг, формат, число серий, студия и
///    официальный трейлер на YouTube.
///
/// Полнометражные версии аниме защищены авторским правом, поэтому в плеере
/// открывается официальный трейлер — без «битых» записей в каталоге.
class AniListVideoSource extends VideoSource {
  AniListVideoSource({
    http.Client? client,
    this.cacheTtl = const Duration(minutes: 10),
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now;

  final http.Client _client;
  final Duration cacheTtl;
  final DateTime Function() _clock;

  static const _endpoint = 'https://graphql.anilist.co';
  static const _timeout = Duration(seconds: 15);
  static const _maxPerPage = 50;

  /// Общие поля карточки: их хватает и ленте, и экрану описания,
  /// поэтому источник не делает лишних запросов за подробностями.
  static const _cardFields = '''
    id
    idMal
    format
    status
    episodes
    duration
    averageScore
    popularity
    favourites
    countryOfOrigin
    coverImage { extraLarge color }
    bannerImage
    title { english romaji native }
    description
    genres
    trailer { id site }
    studios(isMain: true) { nodes { name } }
    startDate { year month day }
    endDate { year month day }
    nextAiringEpisode { episode }
  ''';

  /// Один запрос обслуживает и сезонные ленты, и поиск: меняются только
  /// переменные, поэтому кэш и разбор ответа общие.
  static const _pageQuery =
      '''
      query(\$page: Int, \$perPage: Int, \$season: MediaSeason, \$seasonYear: Int, \$sort: [MediaSort], \$search: String) {
        Page(page: \$page, perPage: \$perPage) {
          pageInfo { hasNextPage total }
          media(
            type: ANIME
            season: \$season
            seasonYear: \$seasonYear
            sort: \$sort
            search: \$search
            isAdult: false
          ) {
            $_cardFields
          }
        }
      }
      ''';

  static const _detailQuery =
      '''
      query(\$id: Int) {
        Media(id: \$id, type: ANIME) {
          $_cardFields
          staff(perPage: 10, sort: RELEVANCE) {
            edges { role node { name { full } } }
          }
        }
      }
      ''';

  final Map<String, _AniListCacheEntry> _cache = {};

  @override
  Future<List<MediaItem>> featured() async {
    return byCategory(MediaCategory.anime, limit: 14);
  }

  @override
  Future<List<MediaItem>> byCategory(
    MediaCategory category, {
    VideoSort sort = VideoSort.popular,
    int limit = 24,
    int page = 1,
  }) async {
    if (category != MediaCategory.anime || limit <= 0 || page <= 0) {
      return const [];
    }

    final season = _currentSeason(_clock());
    final seasonal = sort != VideoSort.oldest && sort != VideoSort.title;

    final json = await _query(_pageQuery, {
      'page': page,
      'perPage': limit.clamp(1, _maxPerPage),
      'season': seasonal ? season.season : null,
      'seasonYear': seasonal ? season.year : null,
      'sort': [_mediaSort(sort)],
    });

    return _items(json);
  }

  @override
  Future<List<MediaItem>> search(
    String query, {
    int limit = 24,
    int page = 1,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || limit <= 0 || page <= 0) return const [];

    final json = await _query(_pageQuery, {
      'page': page,
      'perPage': limit.clamp(1, _maxPerPage),
      'sort': const ['SEARCH_MATCH'],
      'search': trimmed,
    });
    return _items(json);
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
      providerLabel: 'Официальный трейлер · AniList',
      pageUrl: watchUrl,
      mimeType: 'video/youtube',
    );
  }

  @override
  Future<MediaItem> enrich(MediaItem item) async {
    final id = int.tryParse(item.externalId ?? '');
    if (id == null) return item;

    final json = await _query(_detailQuery, {'id': id});
    final data = json?['data'];
    if (data is! Map) return item;
    final media = data['Media'];
    if (media is! Map) return item;

    final enriched = _toItem(media.cast<String, dynamic>());
    if (enriched == null) return item;

    final staff = media['staff'];
    final directors = <String>[];
    if (staff is Map && staff['edges'] is List) {
      for (final edge in staff['edges'] as List) {
        if (edge is! Map) continue;
        final role = '${edge['role'] ?? ''}'.toLowerCase();
        if (!role.contains('director')) continue;
        final node = edge['node'];
        if (node is Map) {
          final names = node['name'];
          if (names is Map) {
            final name = '${names['full'] ?? ''}'.trim();
            if (name.isNotEmpty && !directors.contains(name)) {
              directors.add(name);
            }
          }
        }
        if (directors.length >= 3) break;
      }
    }

    return enriched.copyWith(
      isFavorite: item.isFavorite,
      progress: item.progress,
      directors: directors.isEmpty ? null : directors,
    );
  }

  // ───────────────────────── Сетевой слой ─────────────────────────

  Future<Map<String, dynamic>?> _query(
    String query,
    Map<String, dynamic> variables,
  ) async {
    final key = '$query|${json.encode(variables)}';
    final cached = _cache[key];
    if (cached != null && !cached.isExpired(cacheTtl)) return cached.json;

    try {
      final response = await _client
          .post(
            Uri.parse(_endpoint),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode({'query': query, 'variables': variables}),
          )
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return cached?.json;
      }

      final decoded = json.decode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (decoded is! Map) return cached?.json;

      final map = decoded.cast<String, dynamic>();
      if (map['errors'] != null) return cached?.json;

      _cache[key] = _AniListCacheEntry(map, DateTime.now());
      return map;
    } on Exception {
      // Сеть недоступна — показываем последний удачный ответ, чтобы
      // каталог не пустел при кратком сбое.
      return cached?.json;
    }
  }

  List<MediaItem> _items(Map<String, dynamic>? json) {
    final data = json?['data'];
    if (data is! Map) return const [];
    final page = data['Page'];
    if (page is! Map) return const [];
    final media = page['media'];
    if (media is! List) return const [];

    final items = <MediaItem>[];
    final seen = <String>{};
    for (final raw in media) {
      if (raw is! Map) continue;
      final item = _toItem(raw.cast<String, dynamic>());
      if (item == null) continue;
      if (seen.add(item.id)) items.add(item);
    }
    return items;
  }

  // ───────────────────────── Маппинг ─────────────────────────

  MediaItem? _toItem(Map<String, dynamic> media) {
    final id = media['id'];
    if (id is! int) return null;

    final trailerId = _trailerId(media);
    if (trailerId == null) return null;

    final title = _title(media);
    if (title.isEmpty) return null;

    final format = '${media['format'] ?? ''}'.trim();
    final status = '${media['status'] ?? ''}'.trim();
    final isOngoing = status == 'RELEASING';
    final start = _dateParts(media['startDate']);
    final year = start?.year ?? 0;
    final formatLabel = _formatLabel(format);

    final studios = _studios(media);
    final episodes = media['episodes'] is int ? media['episodes'] as int : null;
    final duration = media['duration'] is int
        ? media['duration'] as int
        : null;
    final nextEpisode = media['nextAiringEpisode'] is Map
        ? (media['nextAiringEpisode'] as Map)['episode']
        : null;

    final score = (media['averageScore'] as num?)?.toDouble() ?? 0;
    final popularity = media['popularity'] is int
        ? media['popularity'] as int
        : 0;
    final countryCode = '${media['countryOfOrigin'] ?? ''}'.trim();

    final subtitle = studios.isNotEmpty
        ? studios.first
        : formatLabel.isNotEmpty
        ? formatLabel
        : 'Аниме';

    return MediaItem(
      id: 'al-$id',
      externalId: '$id',
      title: title,
      subtitle: subtitle,
      category: MediaCategory.anime,
      year: year,
      durationLabel: _durationLabel(
        format: format,
        episodes: episodes,
        minutes: duration,
        nextEpisode: nextEpisode is int ? nextEpisode : null,
        isOngoing: isOngoing,
      ),
      rating: score / 20,
      score: score,
      description: _clean('${media['description'] ?? ''}'),
      imageUrl: _coverUrl(media),
      backdropUrl: _stringOrNull(media['bannerImage']),
      trailerId: trailerId,
      origin: MediaOrigin.anilist,
      genres: _strings(media['genres']),
      directors: studios,
      country: countryCode == 'JP'
          ? 'Япония'
          : countryCode.isEmpty
          ? null
          : countryCode,
      releaseDate: start == null || start.month == null || start.day == null
          ? null
          : '${start.year.toString().padLeft(4, '0')}-'
                '${start.month!.toString().padLeft(2, '0')}-'
                '${start.day!.toString().padLeft(2, '0')}',
      popularity: popularity,
    );
  }

  static String? _trailerId(Map<String, dynamic> media) {
    final trailer = media['trailer'];
    if (trailer is! Map) return null;
    if ('${trailer['site'] ?? ''}'.toLowerCase() != 'youtube') return null;
    final id = '${trailer['id'] ?? ''}'.trim();
    return id.isEmpty ? null : id;
  }

  static String _title(Map<String, dynamic> media) {
    final raw = media['title'];
    if (raw is! Map) return '';
    for (final key in const ['english', 'romaji', 'native']) {
      final value = _clean('${raw[key] ?? ''}');
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static String? _coverUrl(Map<String, dynamic> media) {
    final cover = media['coverImage'];
    if (cover is! Map) return null;
    return _stringOrNull(cover['extraLarge']) ??
        _stringOrNull(cover['large']);
  }

  static List<String> _studios(Map<String, dynamic> media) {
    final studios = media['studios'];
    if (studios is! Map) return const [];
    final nodes = studios['nodes'];
    if (nodes is! List) return const [];
    return [
      for (final node in nodes.take(2))
        if (node is Map && '${node['name'] ?? ''}'.trim().isNotEmpty)
          _clean('${node['name']}'),
    ];
  }

  static String _formatLabel(String format) {
    return switch (format) {
      'TV' => 'Сериал',
      'TV_SHORT' => 'Короткометражный сериал',
      'MOVIE' => 'Фильм',
      'SPECIAL' => 'Спешл',
      'OVA' => 'OVA',
      'ONA' => 'ONA',
      'MUSIC' => 'Клип',
      _ => 'Аниме',
    };
  }

  static String _durationLabel({
    required String format,
    required int? episodes,
    required int? minutes,
    required int? nextEpisode,
    required bool isOngoing,
  }) {
    if (format == 'MOVIE' || format == 'SPECIAL') {
      return _runtimeLabel(minutes);
    }
    if (episodes != null && episodes > 0) {
      final base = '$episodes эп';
      return minutes == null ? base : '$base · $minutesм';
    }
    if (nextEpisode != null && nextEpisode > 1) {
      return '${nextEpisode - 1} эп · онгоинг';
    }
    return isOngoing ? 'Онгоинг' : 'Аниме';
  }

  static String _runtimeLabel(int? minutes) {
    if (minutes == null || minutes <= 0) return '';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (hours == 0) return '$restм';
    return rest == 0 ? '$hoursч' : '$hoursч $restм';
  }

  static String _mediaSort(VideoSort sort) {
    return switch (sort) {
      VideoSort.popular => 'POPULARITY_DESC',
      VideoSort.newest => 'START_DATE_DESC',
      VideoSort.oldest => 'START_DATE_ASC',
      VideoSort.title => 'TITLE_ROMAJI',
    };
  }

  /// Сезон AniList и его год для текущей даты.
  static _AniListSeason _currentSeason(DateTime now) {
    final season = switch (now.month) {
      12 || 1 || 2 => 'WINTER',
      3 || 4 || 5 => 'SPRING',
      6 || 7 || 8 => 'SUMMER',
      _ => 'FALL',
    };
    return _AniListSeason(season, now.year);
  }

  static _DateParts? _dateParts(Object? raw) {
    if (raw is! Map) return null;
    final year = raw['year'];
    final month = raw['month'];
    final day = raw['day'];
    if (year is! int) return null;
    return _DateParts(year, month is int ? month : null, day is int ? day : null);
  }

  static List<String> _strings(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final value in raw)
        if ('$value'.trim().isNotEmpty) _clean('$value'),
    ];
  }

  static String? _stringOrNull(Object? raw) {
    final value = '${raw ?? ''}'.trim();
    return value.isEmpty ? null : value;
  }

  static String _clean(String value) {
    return value
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–')
        .replaceAll('&hellip;', '…')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}

class _AniListSeason {
  const _AniListSeason(this.season, this.year);

  final String season;
  final int year;
}

class _DateParts {
  const _DateParts(this.year, this.month, this.day);

  final int year;
  final int? month;
  final int? day;
}

class _AniListCacheEntry {
  _AniListCacheEntry(this.json, this.storedAt);

  final Map<String, dynamic> json;
  final DateTime storedAt;

  bool isExpired(Duration ttl) => DateTime.now().difference(storedAt) > ttl;
}
