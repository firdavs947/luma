import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/media_item.dart';
import '../domain/video_source.dart';

/// Полные фильмы общественного достояния из Internet Archive.
///
/// Почему именно архив:
///  * фильмы можно смотреть целиком и бесплатно, без подписки и ключа API;
///  * файлы отдаются с CORS `*`, поэтому поток работает и в вебе, и на
///    мобильных платформах;
///  * у записей есть несколько кодировок (h.264, MPEG4, лёгкая 512Kb) —
///    плеер перебирает их по очереди, если первая не открылась.
///
/// Каталог курируемый: в него попадают только проверенные классические
/// фильмы, у которых есть полный файл в открытом доступе. Это защищает от
/// случайного контента и «обрезков» вместо фильма. Свежие релизы защищены
/// авторским правом, поэтому они приходят из Cinemeta и AniList с официальным
/// трейлером, а полные версии — из этого архива.
///
/// Обложки и фоны не берутся из миниатюр архива (180×124): они строятся по
/// IMDb-идентификатору через Metahub в разрешении 780×1170 и 1920×1080,
/// поэтому на больших экранах карточки остаются чёткими.
class ArchiveVideoSource extends VideoSource {
  ArchiveVideoSource({
    http.Client? client,
    this.cacheTtl = const Duration(minutes: 30),
  }) : _client = client ?? http.Client();

  final http.Client _client;

  /// Время жизни кэша метаданных записи: список файлов меняется редко.
  final Duration cacheTtl;

  static const _metadataEndpoint = 'https://archive.org/metadata';
  static const _detailsBase = 'https://archive.org/details';
  static const _downloadBase = 'https://archive.org/download';
  static const _posterBase = 'https://images.metahub.space/poster/large';
  static const _backdropBase =
      'https://images.metahub.space/background/large';
  static const _logoBase = 'https://images.metahub.space/logo/medium';

  static const _timeout = Duration(seconds: 18);

  /// Полный фильм, а не трейлер или фрагмент: файл короче 20 минут
  /// отбрасывается, чтобы в плеер не попал ролик.
  static const _minFilmSeconds = 20 * 60;

  final Map<String, _ArchiveMetadata> _cache = {};

  @override
  Future<List<MediaItem>> featured() async => _curated().take(10).toList();

  @override
  Future<List<MediaItem>> freeFull({int limit = 24}) async =>
      _curated().take(limit).toList();

  @override
  Future<List<MediaItem>> byCategory(
    MediaCategory category, {
    VideoSort sort = VideoSort.popular,
    int limit = 24,
    int page = 1,
  }) async {
    // Бесплатные полные версии — это полнометражные фильмы. Разделы
    // сериалов, мультфильмов и аниме наполняют Cinemeta и AniList.
    if (category != MediaCategory.movies || page > 1) return const [];

    final items = _curated();
    switch (sort) {
      case VideoSort.popular:
        items.sort((a, b) => b.displayScore.compareTo(a.displayScore));
      case VideoSort.newest:
        items.sort((a, b) => b.releaseYear.compareTo(a.releaseYear));
      case VideoSort.oldest:
        items.sort((a, b) => a.releaseYear.compareTo(b.releaseYear));
      case VideoSort.title:
        items.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
    }
    return items.take(limit).toList();
  }

  @override
  Future<List<MediaItem>> search(
    String query, {
    int limit = 24,
    int page = 1,
  }) async {
    final needle = _normalize(query);
    if (needle.isEmpty || page > 1) return const [];

    final matches = <MediaItem>[];
    for (final film in _films) {
      final haystack = _normalize(
        '${film.title} ${film.originalTitle} ${film.genres.join(' ')} '
        '${film.directors.join(' ')}',
      );
      if (haystack.contains(needle)) matches.add(film.toItem());
    }
    return matches.take(limit).toList();
  }

  @override
  Future<VideoStream?> resolveStream(MediaItem item) async {
    final identifier = item.externalId;
    if (identifier == null || identifier.isEmpty) return null;

    final metadata = await _metadata(identifier);
    if (metadata == null) return null;

    final variants = <VideoVariant>[];
    final seen = <String>{};

    for (final raw in metadata.files) {
      if (raw is! Map) continue;
      final file = raw.cast<String, dynamic>();
      final name = '${file['name'] ?? ''}'.trim();
      if (name.isEmpty) continue;

      final lower = name.toLowerCase();
      if (lower.contains('trailer') || lower.contains('sample')) continue;

      final mime = _videoMime(lower);
      if (mime == null) continue;

      final length = double.tryParse('${file['length'] ?? ''}');
      if (length != null && length > 0 && length < _minFilmSeconds) continue;

      final size = int.tryParse('${file['size'] ?? ''}');
      if (size != null && size < 5 * 1024 * 1024) continue;

      final height = int.tryParse('${file['height'] ?? ''}') ??
          _heightFromName(name) ??
          _declaredHeight('${file['format'] ?? ''}');
      final width = int.tryParse('${file['width'] ?? ''}');
      final bandwidth = size != null && length != null && length > 0
          ? (size * 8 / length).round()
          : _declaredBandwidth('${file['format']}');

      final url = '$_downloadBase/$identifier/${_encodePath(name)}';
      if (!seen.add(url)) continue;

      variants.add(
        VideoVariant(
          url: url,
          label: _qualityLabel(
            height: height,
            width: width,
            bandwidth: bandwidth,
          ),
          height: height,
          bandwidth: bandwidth,
          mimeType: mime,
        ),
      );
    }

    if (variants.isEmpty) return null;

    // Лучшее качество первым. Плеер пробует его и при ошибке переходит
    // к следующему варианту, поэтому даже тяжёлый файл не блокирует
    // просмотр: всегда есть запасная кодировка.
    variants.sort((a, b) {
      final byHeight = (b.height ?? 0).compareTo(a.height ?? 0);
      if (byHeight != 0) return byHeight;
      return b.weight.compareTo(a.weight);
    });
    if (variants.length > 6) variants.removeRange(6, variants.length);

    return VideoStream(
      url: variants.first.url,
      variants: variants,
      mimeType: variants.first.mimeType,
      kind: PlaybackKind.fullFilm,
      providerLabel: 'Internet Archive · полный фильм',
      pageUrl: '$_detailsBase/$identifier',
    );
  }

  @override
  Future<MediaItem?> fullVersionOf(MediaItem item) async {
    if (item.origin == MediaOrigin.archive) return item;

    final imdb = item.imdbId ?? item.externalId;
    if (imdb != null && imdb.isNotEmpty) {
      for (final film in _films) {
        if (film.imdb == imdb) return film.toItem();
      }
    }

    final title = _normalize(item.title);
    if (title.isEmpty) return null;

    final matches = [
      for (final film in _films)
        if (_normalize(film.originalTitle) == title ||
            _normalize(film.title) == title)
          film,
    ];
    if (matches.isEmpty) return null;

    // Одноимённых фильмов много: год выхода отсекает случайные совпадения.
    final year = item.releaseYear;
    final exact = matches.where(
      (film) => year == 0 || (film.year - year).abs() <= 2,
    );
    return (exact.isNotEmpty ? exact.first : matches.first).toItem();
  }

  @override
  Future<MediaItem> enrich(MediaItem item) async {
    // Курируемая запись уже содержит все данные карточки.
    return item;
  }

  // ───────────────────────── Данные и сеть ─────────────────────────

  List<MediaItem> _curated() {
    final items = [for (final film in _films) film.toItem()];
    items.sort((a, b) => b.displayScore.compareTo(a.displayScore));
    return items;
  }

  Future<_ArchiveMetadata?> _metadata(String identifier) async {
    final cached = _cache[identifier];
    if (cached != null && !cached.isExpired(cacheTtl)) return cached;

    try {
      final response = await _client
          .get(Uri.parse('$_metadataEndpoint/$identifier'))
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return cached;
      }

      final decoded = json.decode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (decoded is! Map) return cached;

      final files = decoded['files'];
      if (files is! List) return cached;

      final metadata = _ArchiveMetadata(files, DateTime.now());
      _cache[identifier] = metadata;
      return metadata;
    } on Exception {
      return cached;
    }
  }

  // ───────────────────────── Служебные функции ─────────────────────────

  static String? _videoMime(String name) {
    if (name.endsWith('.mp4') || name.endsWith('.m4v')) return 'video/mp4';
    if (name.endsWith('.webm')) return 'video/webm';
    // OGV на мобильных платформах воспроизводится нестабильно, поэтому
    // в варианты он не попадает: лучше меньше вариантов, но рабочих.
    return null;
  }

  /// Высота кадра из имени файла: «..._720p.mp4» → 720.
  static int? _heightFromName(String name) {
    final match = RegExp(r'(2160|1440|1080|720|576|480|360|240)p')
        .firstMatch(name.toLowerCase());
    return int.tryParse(match?.group(1) ?? '');
  }

  static int? _declaredHeight(String format) {
    final match = RegExp(r'(\d{3,4})\s*[xх]').firstMatch(format.toLowerCase());
    return int.tryParse(match?.group(1) ?? '');
  }

  static int? _declaredBandwidth(String format) {
    final match = RegExp(r'(\d+)\s*[Kk]b').firstMatch(format);
    return match == null ? null : int.parse(match.group(1)!) * 1000;
  }

  static String _qualityLabel({
    int? height,
    int? width,
    int? bandwidth,
  }) {
    if (height != null && height > 0) {
      const standards = [240, 360, 480, 576, 720, 1080, 1440, 2160];
      final standard = standards.reduce(
        (a, b) => (a - height).abs() <= (b - height).abs() ? a : b,
      );
      return '${standard}p';
    }
    if (width != null && width > 0) return '${width}px';
    if (bandwidth != null && bandwidth > 0) {
      final mbps = bandwidth / 1000000;
      return mbps >= 1
          ? '${mbps.toStringAsFixed(1)} Мбит/с'
          : '${(bandwidth / 1000).round()} кбит/с';
    }
    return 'Оригинал';
  }

  static String _encodePath(String name) =>
      name.split('/').map(Uri.encodeComponent).join('/');

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Курируемый список: только фильмы с полным файлом в открытом доступе.
  ///
  /// IMDb-идентификатор нужен для постеров Metahub и точного сопоставления
  /// с карточками Cinemeta, поэтому он проверен для каждой записи.
  static const List<_ArchiveFilm> _films = [
    _ArchiveFilm(
      identifier: 'his_girl_friday',
      imdb: 'tt0032599',
      title: 'Его девушка Пятница',
      originalTitle: 'His Girl Friday',
      year: 1940,
      runtime: '1ч 32м',
      score: 7.8,
      genres: ['Comedy', 'Drama', 'Romance'],
      directors: ['Howard Hawks'],
      cast: ['Cary Grant', 'Rosalind Russell', 'Ralph Bellamy'],
      country: 'США',
      description:
          'Редактор Уолтер Бёрнс пытается вернуть жену Хильди, лучшего '
          'репортёра города, и одновременно спасти газету. Ради сенсации он '
          'готов на всё, а Хильди не может устоять перед хорошей историей.',
    ),
    _ArchiveFilm(
      identifier: 'HouseOnHauntedHill_201605',
      imdb: 'tt0051744',
      title: 'Дом на холме призраков',
      originalTitle: 'House on Haunted Hill',
      year: 1959,
      runtime: '1ч 15м',
      score: 6.7,
      genres: ['Crime', 'Horror', 'Mystery'],
      directors: ['William Castle'],
      cast: ['Vincent Price', 'Carol Ohmart', 'Richard Long'],
      country: 'США',
      description:
          'Эксцентричный миллионер приглашает гостей в дом, где, по слухам, '
          'водятся призраки. Тот, кто выживет до утра, получит крупную сумму. '
          'Гости ещё не знают, что хозяин подготовил им собственную игру.',
    ),
    _ArchiveFilm(
      identifier: 'suddenly_201606',
      imdb: 'tt0047542',
      title: 'Внезапно',
      originalTitle: 'Suddenly',
      year: 1954,
      runtime: '1ч 17м',
      score: 6.8,
      genres: ['Crime', 'Drama', 'Film-Noir'],
      directors: ['Lewis Allen'],
      cast: ['Frank Sinatra', 'Sterling Hayden', 'James Gleason'],
      country: 'США',
      description:
          'В тихий городок приезжает убийца, чтобы занять дом напротив '
          'вокзала: через него должен проехать президент. Шериф и его семья '
          'оказываются заложниками в собственной гостиной.',
    ),
    _ArchiveFilm(
      identifier: 'TheStranger_0',
      imdb: 'tt0038991',
      title: 'Незнакомец',
      originalTitle: 'The Stranger',
      year: 1946,
      runtime: '1ч 31м',
      score: 7.3,
      genres: ['Crime', 'Drama', 'Film-Noir'],
      directors: ['Orson Welles'],
      cast: ['Orson Welles', 'Edward G. Robinson', 'Loretta Young'],
      country: 'США',
      description:
          'Нацистский преступник скрывается под чужим именем в маленьком '
          'американском городке и готовит новую жизнь. Но за ним приезжает '
          'охотник за нацистами, и прошлое начинает разрушать выстроенный мир.',
    ),
    _ArchiveFilm(
      identifier: 'mclintok_widescreen',
      imdb: 'tt0057298',
      title: 'Маклинток!',
      originalTitle: 'McLintock!',
      year: 1963,
      runtime: '2ч 7м',
      score: 7.1,
      genres: ['Comedy', 'Western'],
      directors: ['Andrew V. McLaglen'],
      cast: ['John Wayne', 'Maureen O’Hara', 'Patrick Wayne'],
      country: 'США',
      description:
          'Строптивый владелец ранчо пытается вернуть ушедшую жену и '
          'одновременно разобраться с коррумпированными чиновниками. Большая '
          'комедия о семье, гордости и умении вовремя уступить.',
    ),
    _ArchiveFilm(
      identifier: 'silent-the-phantom-of-the-opera',
      imdb: 'tt0016220',
      title: 'Призрак оперы',
      originalTitle: 'The Phantom of the Opera',
      year: 1925,
      runtime: '1ч 32м',
      score: 7.5,
      genres: ['Horror', 'Music'],
      directors: ['Rupert Julian'],
      cast: ['Lon Chaney', 'Mary Philbin', 'Norman Kerry'],
      country: 'США',
      description:
          'Таинственный музыкант в маске живёт в подвалах парижской оперы и '
          'превращает юную певицу в звезду. Когда она решает уйти, его '
          'одержимость становится опасной.',
    ),
    _ArchiveFilm(
      identifier: 'meet_john_doe',
      imdb: 'tt0033891',
      title: 'Познакомьтесь с Джоном Доу',
      originalTitle: 'Meet John Doe',
      year: 1941,
      runtime: '2ч 3м',
      score: 7.6,
      genres: ['Comedy', 'Drama', 'Romance'],
      directors: ['Frank Capra'],
      cast: ['Gary Cooper', 'Barbara Stanwyck', 'Edward Arnold'],
      country: 'США',
      description:
          'Журналистка придумывает героя-простака, чтобы вернуть газете '
          'читателей. Вымышленный Джон Доу неожиданно становится голосом '
          'народа, а его создатели оказываются между правдой и политикой.',
    ),
    _ArchiveFilm(
      identifier: 'CarnivalofSouls',
      imdb: 'tt0055830',
      title: 'Карнавал душ',
      originalTitle: 'Carnival of Souls',
      year: 1962,
      runtime: '1ч 23м',
      score: 7.0,
      genres: ['Horror', 'Mystery'],
      directors: ['Herk Harvey'],
      cast: ['Candace Hilligoss', 'Frances Feist', 'Sidney Berger'],
      country: 'США',
      description:
          'После аварии женщина чудом остаётся жива и переезжает в другой '
          'город. Её тянет к заброшенному карнавалу, а странные встречи '
          'постепенно стирают границу между жизнью и смертью.',
    ),
    _ArchiveFilm(
      identifier: 'Nosferatu1922',
      imdb: 'tt0013442',
      title: 'Носферату. Симфония ужаса',
      originalTitle: 'Nosferatu',
      year: 1922,
      runtime: '1ч 32м',
      score: 7.8,
      genres: ['Fantasy', 'Horror'],
      directors: ['F. W. Murnau'],
      cast: ['Max Schreck', 'Alexander Granach', 'Gustav von Wangenheim'],
      country: 'Германия',
      description:
          'Немецкий ремейк «Дракулы»: вампир граф Орлок переезжает в город, '
          'принося с собой чуму. Его жертва понимает, что остановить '
          'чудовище можно только ценой собственной жизни.',
    ),
    _ArchiveFilm(
      identifier: 'Detour',
      imdb: 'tt0037638',
      title: 'Объезд',
      originalTitle: 'Detour',
      year: 1946,
      runtime: '1ч 8м',
      score: 7.3,
      genres: ['Crime', 'Drama', 'Film-Noir'],
      directors: ['Edgar G. Ulmer'],
      cast: ['Tom Neal', 'Ann Savage', 'Claudia Drake'],
      country: 'США',
      description:
          'Пианист автостопом едет к невесте и случайно оказывается в машине '
          'убийцы. Теперь ему нужно доказать свою невиновность, но каждая '
          'новая попытка делает положение хуже.',
    ),
    _ArchiveFilm(
      identifier: 'TheLittleShopOfHorrors1960',
      imdb: 'tt0054033',
      title: 'Маленький магазинчик ужасов',
      originalTitle: 'The Little Shop of Horrors',
      year: 1960,
      runtime: '1ч 13м',
      score: 6.2,
      genres: ['Comedy', 'Horror'],
      directors: ['Roger Corman'],
      cast: ['Jonathan Haze', 'Jackie Joseph', 'Mel Welles'],
      country: 'США',
      description:
          'Флорист-неудачник выращивает странное говорящее растение, которое '
          'требует человеческой крови. Чёрная комедия, ставшая основой '
          'легендарного мюзикла.',
    ),
    _ArchiveFilm(
      identifier: 'night-of-the-living-dead-1968-english',
      imdb: 'tt0063350',
      title: 'Ночь живых мертвецов',
      originalTitle: 'Night of the Living Dead',
      year: 1968,
      runtime: '1ч 36м',
      score: 7.8,
      genres: ['Horror', 'Thriller'],
      directors: ['George A. Romero'],
      cast: ['Duane Jones', 'Judith O’Dea', 'Karl Hardman'],
      country: 'США',
      description:
          'Незнакомые люди прячутся в загородном доме, пока полчища зомби '
          'окружают их. Фильм, который задал правила жанра и остаётся '
          'эталоном независимого хоррора.',
    ),
    _ArchiveFilm(
      identifier: 'The_General_Buster_Keaton',
      imdb: 'tt0017925',
      title: 'Генерал',
      originalTitle: 'The General',
      year: 1926,
      runtime: '1ч 19м',
      score: 8.1,
      genres: ['Action', 'Adventure', 'Comedy'],
      directors: ['Clyde Bruckman', 'Buster Keaton'],
      cast: ['Buster Keaton', 'Marion Mack', 'Glen Cavender'],
      country: 'США',
      description:
          'Машинист без армии бросается спасать любимую и свой паровоз во '
          'время Гражданской войны в США. Немая комедия, где трюки до сих пор '
          'выглядят невозможными.',
    ),
    _ArchiveFilm(
      identifier: 'TheHunchbackOfNotreDame1923_201312',
      imdb: 'tt0014142',
      title: 'Собор Парижской Богоматери',
      originalTitle: 'The Hunchback of Notre Dame',
      year: 1923,
      runtime: '1ч 56м',
      score: 7.2,
      genres: ['Drama', 'Horror', 'Romance'],
      directors: ['Wallace Worsley'],
      cast: ['Lon Chaney', 'Patsy Ruth Miller', 'Norman Kerry'],
      country: 'США',
      description:
          'Звонарь Квазимодо влюбляется в цыганку Эсмеральду и защищает её '
          'от жестокого судьи. Классика по роману Виктора Гюго с знаменитой '
          'ролью Лона Чейни.',
    ),
    _ArchiveFilm(
      identifier: 'doa-1950_202506',
      imdb: 'tt0042369',
      title: 'Мёртв по прибытии',
      originalTitle: 'D.O.A.',
      year: 1950,
      runtime: '1ч 23м',
      score: 7.2,
      genres: ['Crime', 'Drama', 'Film-Noir'],
      directors: ['Rudolph Maté'],
      cast: ['Edmond O’Brien', 'Pamela Britton', 'Luther Adler'],
      country: 'США',
      description:
          'Бухгалтер узнаёт, что его отравили, и теряет несколько дней жизни. '
          'Он отправляется на поиски собственного убийцы, пока время не '
          'закончилось.',
    ),
  ];
}

/// Курируемая запись архива: метаданные карточки и правила поиска файла.
class _ArchiveFilm {
  const _ArchiveFilm({
    required this.identifier,
    required this.imdb,
    required this.title,
    required this.originalTitle,
    required this.year,
    required this.runtime,
    required this.score,
    required this.genres,
    required this.directors,
    required this.cast,
    required this.country,
    required this.description,
  });

  final String identifier;
  final String imdb;
  final String title;
  final String originalTitle;
  final int year;
  final String runtime;
  final double score;
  final List<String> genres;
  final List<String> directors;
  final List<String> cast;
  final String country;
  final String description;

  MediaItem toItem() {
    return MediaItem(
      id: 'ia-$identifier',
      externalId: identifier,
      imdbId: imdb,
      title: title,
      subtitle: directors.isNotEmpty
          ? directors.first
          : genres.isNotEmpty
          ? genres.first
          : 'Фильм',
      category: MediaCategory.movies,
      year: year,
      durationLabel: runtime,
      rating: score / 2,
      score: score,
      description: description,
      imageUrl: '${ArchiveVideoSource._posterBase}/$imdb/img',
      backdropUrl: '${ArchiveVideoSource._backdropBase}/$imdb/img',
      logoUrl: '${ArchiveVideoSource._logoBase}/$imdb/img',
      origin: MediaOrigin.archive,
      genres: genres,
      cast: cast,
      directors: directors,
      country: country,
      popularity: (score * 10000).round(),
    );
  }
}

/// Кэш списка файлов записи.
class _ArchiveMetadata {
  _ArchiveMetadata(this.files, this.storedAt);

  final List<dynamic> files;
  final DateTime storedAt;

  bool isExpired(Duration ttl) => DateTime.now().difference(storedAt) > ttl;
}
