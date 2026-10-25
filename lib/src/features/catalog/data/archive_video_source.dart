import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/media_item.dart';
import '../domain/video_source.dart';

/// Источник видео на базе Internet Archive (archive.org).
///
/// Почему именно он:
///  * контент легальный — общественное достояние и открытые лицензии
///    (поле `licenseurl` у каждой записи);
///  * не нужен API-ключ и нет жёсткого лимита запросов, поэтому каталог
///    работает «из коробки» и не упирается в квоту;
///  * архив покрывает все четыре видеорасдела: полнометражные фильмы
///    (`feature_films`), аниме, мультфильмы (`animationandcartoons`)
///    и классические сериалы (`classic_tv`);
///  * на каждую запись есть несколько кодировок (h.264, 512Kb MPEG4,
///    MPEG4), что позволяет подбирать битрейт под скорость соединения.
class ArchiveVideoSource implements VideoSource {
  ArchiveVideoSource({
    http.Client? client,
    this.cacheTtl = const Duration(minutes: 20),
  }) : _client = client ?? http.Client();

  final http.Client _client;

  /// Время жизни кэша ответов: каталог не дёргает API на каждую перерисовку.
  final Duration cacheTtl;

  static const _searchEndpoint = 'https://archive.org/advancedsearch.php';
  static const _metadataEndpoint = 'https://archive.org/metadata';
  static const _downloadBase = 'https://archive.org/download';
  static const _thumbBase = 'https://archive.org/services/img';

  static const _timeout = Duration(seconds: 18);

  /// Поля, которые нужны карточке: без описания и обложки она выглядит пустой.
  static const _fields = [
    'identifier',
    'title',
    'description',
    'year',
    'date',
    'creator',
    'runtime',
    'downloads',
    'subject',
    'licenseurl',
  ];

  /// Раздел → запрос к архиву.
  ///
  /// `format:"MPEG4"` оставляет только записи с готовым потоковым файлом —
  /// иначе в каталог попадали бы элементы без воспроизводимой копии.
  static const Map<MediaCategory, String> _categoryQueries = {
    MediaCategory.movies: 'collection:feature_films AND format:"MPEG4"',
    MediaCategory.anime:
        'subject:"anime" AND mediatype:movies AND format:"MPEG4"',
    MediaCategory.cartoons:
        'collection:animationandcartoons AND format:"MPEG4"',
    MediaCategory.series: 'collection:classic_tv AND format:"MPEG4"',
  };

  /// Кэш выдачи поиска и метаданных: ключ → (момент записи, значение).
  final Map<String, _CacheEntry> _cache = {};

  @override
  Future<List<MediaItem>> featured() async {
    // Разделы грузятся параллельно: главный экран не ждёт четыре запроса
    // последовательно.
    final pages = await Future.wait([
      byCategory(MediaCategory.movies, limit: 12),
      byCategory(MediaCategory.anime, limit: 12),
      byCategory(MediaCategory.cartoons, limit: 12),
      byCategory(MediaCategory.series, limit: 12),
    ]);

    // Чередуем разделы, чтобы ленты наполнялись равномерно, а не блоками.
    final mixed = <MediaItem>[];
    final longest = pages.fold<int>(0, (max, page) =>
        page.length > max ? page.length : max);
    for (var i = 0; i < longest; i++) {
      for (final page in pages) {
        if (i < page.length) mixed.add(page[i]);
      }
    }
    return mixed;
  }

  @override
  Future<List<MediaItem>> byCategory(
    MediaCategory category, {
    VideoSort sort = VideoSort.popular,
    int limit = 24,
    int page = 1,
  }) async {
    final query = _categoryQueries[category];
    if (query == null) return const [];

    final docs = await _search(query, sort: sort, limit: limit, page: page);
    return [
      for (final doc in docs) ?_toItem(doc, category),
    ];
  }

  @override
  Future<List<MediaItem>> search(
    String query, {
    int limit = 24,
    int page = 1,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    // Ищем по названию и описанию среди видео с готовым потоком.
    final expression =
        'mediatype:movies AND format:"MPEG4" AND (title:("$trimmed") '
        'OR description:("$trimmed"))';

    final docs = await _search(
      expression,
      sort: VideoSort.popular,
      limit: limit,
      page: page,
    );

    return [
      for (final doc in docs) ?_toItem(doc, _guessCategory(doc)),
    ];
  }

  @override
  Future<VideoStream?> resolveStream(MediaItem item) async {
    final identifier = item.externalId;
    if (identifier == null || identifier.isEmpty) return null;

    final metadata = await _metadata(identifier);
    if (metadata == null) return null;

    final files = (metadata['files'] as List?) ?? const [];
    final variants = <VideoVariant>[];

    for (final raw in files) {
      if (raw is! Map) continue;
      final file = raw.cast<String, dynamic>();
      final name = file['name'] as String?;
      if (name == null) continue;

      final mime = _videoMime(name);
      if (mime == null) continue;

      final size = int.tryParse('${file['size'] ?? ''}');
      final length = double.tryParse('${file['length'] ?? ''}');
      final height = int.tryParse('${file['height'] ?? ''}');

      // Битрейт: либо из имени кодировки («512Kb MPEG4»), либо из размера
      // файла и его длительности. По нему выбирается качество под сеть.
      final bandwidth = _declaredBandwidth('${file['format']}') ??
          (size != null && length != null && length > 0
              ? (size * 8 / length).round()
              : null);

      variants.add(
        VideoVariant(
          url: '$_downloadBase/$identifier/${_encodePath(name)}',
          label: _qualityLabel(height: height, bandwidth: bandwidth),
          height: height,
          bandwidth: bandwidth,
          mimeType: mime,
        ),
      );
    }

    if (variants.isEmpty) return null;

    // Лучшее качество — первым: пользователь видит внятный список.
    variants.sort((a, b) => b.weight.compareTo(a.weight));

    final selected = await _selectVariant(variants);

    return VideoStream(
      url: selected.url,
      variants: variants,
      mimeType: selected.mimeType,
    );
  }

  // ───────────────────────── Внутренняя работа ─────────────────────────

  /// Выполняет поисковый запрос и возвращает список документов.
  Future<List<Map<String, dynamic>>> _search(
    String query, {
    required VideoSort sort,
    required int limit,
    required int page,
  }) async {
    final uri = Uri.parse(_searchEndpoint).replace(
      queryParameters: {
        'q': query,
        'rows': '$limit',
        'page': '$page',
        'output': 'json',
        'sort[]': _sortParam(sort),
        for (var i = 0; i < _fields.length; i++) 'fl[$i]': _fields[i],
      },
    );

    final body = await _getCached(uri.toString());
    if (body == null) return const [];

    try {
      final decoded = json.decode(body) as Map<String, dynamic>;
      final response = decoded['response'] as Map<String, dynamic>?;
      final docs = (response?['docs'] as List?) ?? const [];
      return [
        for (final doc in docs)
          if (doc is Map) doc.cast<String, dynamic>(),
      ];
    } on FormatException {
      return const [];
    }
  }

  /// Метаданные одной записи: из них собирается поток.
  Future<Map<String, dynamic>?> _metadata(String identifier) async {
    final uri = Uri.parse('$_metadataEndpoint/$identifier');
    final body = await _getCached(uri.toString(), ttl: cacheTtl * 3);
    if (body == null) return null;

    try {
      final decoded = json.decode(body);
      if (decoded is! Map) return null;
      return decoded.cast<String, dynamic>();
    } on FormatException {
      return null;
    }
  }

  /// GET с кэшем: повторные открытия карточки не бьют по сети.
  Future<String?> _getCached(String url, {Duration? ttl}) async {
    final lifetime = ttl ?? cacheTtl;
    final cached = _cache[url];
    if (cached != null && !cached.isExpired(lifetime)) return cached.body;

    try {
      final response = await _client.get(Uri.parse(url)).timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;

      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      _cache[url] = _CacheEntry(body, DateTime.now());
      return body;
    } on Exception {
      // Сеть недоступна — отдаём устаревший кэш, если он есть.
      return cached?.body;
    }
  }

  /// Документ поиска → карточка каталога.
  MediaItem? _toItem(Map<String, dynamic> doc, MediaCategory category) {
    final identifier = '${doc['identifier'] ?? ''}'.trim();
    if (identifier.isEmpty) return null;

    final title = _clean('${doc['title'] ?? ''}');
    if (title.isEmpty) return null;

    final runtime = '${doc['runtime'] ?? ''}';
    final creator = _clean('${doc['creator'] ?? ''}');

    return MediaItem(
      id: 'ia-$identifier',
      externalId: identifier,
      title: title,
      subtitle: creator.isEmpty ? 'Internet Archive' : creator,
      category: category,
      year: _parseYear(doc),
      durationLabel: _durationLabel(runtime),
      rating: 0,
      description: _clean('${doc['description'] ?? ''}'),
      imageUrl: '$_thumbBase/$identifier',
      popularity: int.tryParse('${doc['downloads'] ?? ''}') ?? 0,
    );
  }

  /// Раздел для результата поиска: точный коллекционный признак есть не
  /// всегда, поэтому опираемся на предметные метки записи.
  MediaCategory _guessCategory(Map<String, dynamic> doc) {
    final subjects = [
      for (final subject in (doc['subject'] as List?) ?? const [])
        '$subject'.toLowerCase(),
    ].join(' ');

    if (subjects.contains('anime')) return MediaCategory.anime;
    if (subjects.contains('cartoon') || subjects.contains('animation')) {
      return MediaCategory.cartoons;
    }
    if (subjects.contains('television') || subjects.contains('tv')) {
      return MediaCategory.series;
    }
    return MediaCategory.movies;
  }

  /// Выбор варианта под скорость соединения.
  ///
  /// Сначала измеряем реальную пропускную способность на самом лёгком
  /// файле, затем берём лучшее качество, которое заведомо пролезет в канал
  /// с запасом. Если замер не удался — безопасная середина.
  Future<VideoVariant> _selectVariant(List<VideoVariant> variants) async {
    if (variants.length == 1) return variants.first;

    final lightest = variants.last;
    final throughput = await _probeThroughput(lightest.url);

    if (throughput == null) return variants[variants.length ~/ 2];

    final budget = throughput * 0.7;
    for (final variant in variants) {
      final bandwidth = variant.bandwidth;
      if (bandwidth == null || bandwidth <= budget) return variant;
    }
    return lightest;
  }

  /// Оценка скорости в битах в секунду по загрузке первых 256 КБ.
  Future<double?> _probeThroughput(String url) async {
    final stopwatch = Stopwatch()..start();
    try {
      final request = http.Request('GET', Uri.parse(url))
        ..headers['Range'] = 'bytes=0-262143';
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 6));
      if (response.statusCode >= 400) return null;

      var received = 0;
      await for (final chunk in response.stream) {
        received += chunk.length;
        // Хватит 128 КБ: на медленном канале замер и так займёт время.
        if (received >= 131072) break;
      }
      stopwatch.stop();

      final seconds = stopwatch.elapsedMilliseconds / 1000;
      if (seconds <= 0 || received <= 0) return null;
      return received * 8 / seconds;
    } on Exception {
      return null;
    }
  }

  /// Параметр сортировки архива.
  static String _sortParam(VideoSort sort) {
    return switch (sort) {
      VideoSort.popular => 'downloads desc',
      VideoSort.newest => 'year desc',
      VideoSort.oldest => 'year asc',
      VideoSort.title => 'title asc',
    };
  }

  /// Год выпуска: архив хранит его и в `year`, и в `date`.
  static int _parseYear(Map<String, dynamic> doc) {
    final year = int.tryParse('${doc['year'] ?? ''}');
    if (year != null && year > 1800) return year;

    final date = '${doc['date'] ?? ''}';
    final match = RegExp(r'(\d{4})').firstMatch(date);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  /// Длительность из строки архива («1:32:10») в формат LUMA («1ч 32м»).
  static String _durationLabel(String runtime) {
    final match = RegExp(r'(\d+):(\d{2})(?::(\d{2}))?').firstMatch(runtime);
    if (match == null) return '';

    final first = int.parse(match.group(1)!);
    final second = int.parse(match.group(2)!);
    final third = match.group(3);

    // «20:33» — это минуты и секунды, «1:32:10» — часы, минуты, секунды.
    final hours = third == null ? first ~/ 60 : first;
    final minutes = third == null ? first % 60 : second;

    if (hours == 0) return '$minutesм';
    return '$hoursч $minutesм';
  }

  /// Битрейт из подписи кодировки: «512Kb MPEG4» → 512000.
  static int? _declaredBandwidth(String format) {
    final match = RegExp(r'(\d+)\s*[Kk]b').firstMatch(format);
    if (match == null) return null;
    return int.parse(match.group(1)!) * 1000;
  }

  /// Подпись качества по высоте кадра, а при её отсутствии — по битрейту.
  static String _qualityLabel({int? height, int? bandwidth}) {
    if (height != null && height > 0) {
      // Округляем к ближайшему стандарту: 478 → 480p.
      final standard = [240, 360, 480, 576, 720, 1080, 1440, 2160]
          .reduce((a, b) => (a - height).abs() <= (b - height).abs() ? a : b);
      return '${standard}p';
    }
    if (bandwidth != null && bandwidth > 0) {
      return '${(bandwidth / 1000).round()} кбит/с';
    }
    return 'Оригинал';
  }

  /// MIME-тип для расширений, которые понимают мобильные плееры.
  static String? _videoMime(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.mp4') || lower.endsWith('.m4v')) return 'video/mp4';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.ogv')) return 'video/ogg';
    if (lower.endsWith('.m3u8')) return 'application/x-mpegURL';
    return null;
  }

  /// Кодирует путь файла, сохраняя разделители вложенных каталогов.
  static String _encodePath(String name) {
    return name.split('/').map(Uri.encodeComponent).join('/');
  }

  /// Убирает HTML-разметку из описаний архива и лишние пробелы.
  static String _clean(String value) {
    final withoutTags = value
        .replaceAll(RegExp('<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ');
    return withoutTags.trim();
  }
}

/// Запись в кэше ответов.
class _CacheEntry {
  _CacheEntry(this.body, this.storedAt);

  final String body;
  final DateTime storedAt;

  bool isExpired(Duration ttl) => DateTime.now().difference(storedAt) > ttl;
}
