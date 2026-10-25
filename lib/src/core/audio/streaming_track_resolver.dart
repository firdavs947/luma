import 'dart:convert';

import 'package:http/http.dart' as http;

import 'track_stream_resolver.dart';

/// Резолвер по умолчанию: Audius (только полные версии).
///
/// Согласно требованию, мы исключаем использование 30-секундных фрагментов
/// (Apple Music, Deezer), так как они не подходят для качественного прослушивания.
/// Поиск ведется исключительно по каталогам, отдающим полную запись.
class StreamingTrackResolver implements TrackStreamResolver {
  StreamingTrackResolver({http.Client? client})
      : _client = client ?? http.Client();

  static const _appName = 'LUMA';
  static const _audiusBase = 'https://api.audius.co';

  static const _timeout = Duration(seconds: 8); // Увеличили таймаут для более глубокого поиска

  static const _cacheTtl = Duration(minutes: 20);
  static const _cacheLimit = 200;

  static const _minSeconds = 45; // Подняли планку, чтобы исключить любые нарезки
  static const _maxSeconds = 900;

  /// Слова, которые ничего не говорят о совпадении.
  static const _stopWords = {
    'feat',
    'ft',
    'the',
    'and',
    'prod',
    'official',
    'video',
    'audio',
    'lyric',
    'lyrics',
    'remaster',
    'remastered',
    'explicit',
  };

  /// Пометки, по которым запись — не оригинал, а обработка чужого трека.
  ///
  /// Это главный фильтр от подмены: под названием «Billie Jean» чаще всего
  /// лежит ремикс или кавер, поэтому такие варианты отбрасываются целиком,
  /// а не понижаются в приоритете.
  static const _derivativeMarkers = {
    'remix',
    'remixed',
    'remixes',
    'rmx',
    'bootleg',
    'mashup',
    'cover',
    'edit',
    'flip',
    'rework',
    'refix',
    'nightcore',
    'sped',
    'slowed',
    'slowedreverb',
    'reverb',
    'karaoke',
    'instrumental',
    'acapella',
    'acappella',
    'vip',
    'ремикс',
    'ремих',
    'кавер',
    'мэшап',
  };

  final http.Client _client;

  /// Уже найденные записи. `null` тоже кэшируется: иначе каждый вход в трек
  /// без звука снова и снова опрашивал бы три провайдера.
  final _cache = <String, _CachedStream>{};

  @override
  Future<ResolvedTrackStream?> resolve({
    required String title,
    required String artist,
  }) async {
    final cleanTitle = _stripDecorations(title);
    final cleanArtist = _primaryArtist(artist);
    if (cleanTitle.isEmpty) return null;

    final key = '${cleanArtist.toLowerCase()}|${cleanTitle.toLowerCase()}';

    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.storedAt) <= _cacheTtl) {
      return cached.value;
    }

    final audius = _searchAudius(cleanTitle, cleanArtist);
    
    // В новой реализации мы полностью полагаемся на источники с полными треками.
    // Если первый поиск не дал результатов, пробуем альтернативный запрос.
    var stream = await audius;
    stream ??= await _searchAudius(cleanTitle, ''); // Поиск только по названию

    _store(key, stream);
    return stream;
  }

  /// Audius: свободный каталог, песня отдаётся целиком.
  Future<ResolvedTrackStream?> _searchAudius(
    String title,
    String artist,
  ) async {
    final payload = await _getJson(
      Uri.parse('$_audiusBase/v1/tracks/search').replace(
        queryParameters: {
          'query': '$artist $title',
          'app_name': _appName,
          'limit': '10',
        },
      ),
    );

    final data = payload?['data'];
    if (data is! List) return null;

    for (final raw in data) {
      if (raw is! Map<String, dynamic>) continue;
      if (raw['is_streamable'] != true) continue;

      final id = _nonEmpty(raw['id'] as String?);
      if (id == null || !_isSongLength((raw['duration'] as num?)?.toInt())) {
        continue;
      }

      final candidateTitle = raw['title'] as String? ?? '';
      // Ремиксы и каверы отбрасываются до сверки с оригиналом: на Audius
      // под нужным названием чаще всего лежит именно обработка.
      if (_isDerivative(candidateTitle)) continue;
      if (!_covers(candidateTitle, title)) continue;

      final user = raw['user'];
      final candidateArtist = user is Map<String, dynamic>
          ? '${user['name'] ?? ''} ${user['handle'] ?? ''}'
          : '';

      // Только запись самого исполнителя: чужие загрузки с тем же
      // названием — это почти всегда кавер.
      if (_covers(candidateArtist, artist) ||
          _covers(candidateTitle, artist)) {
        return _audiusStream(id);
      }
    }

    return null;
  }

  /// Ссылка на поток Audius.
  ///
  /// Отдаём адрес-перенаправление, а не подписанный адрес CDN: подпись
  /// живёт считаные минуты, поэтому её лучше получать в момент запроса,
  /// а не хранить.
  ResolvedTrackStream _audiusStream(String id) => ResolvedTrackStream(
        url: '$_audiusBase/v1/tracks/$id/stream?app_name=$_appName',
        source: 'Audius',
        isFullLength: true,
      );

  /// Все значимые слова [query] встречаются в [candidate].
  bool _covers(String candidate, String query) {
    final needles = _tokens(query);
    if (needles.isEmpty) return false;
    final haystack = _tokens(candidate);
    return needles.every(haystack.contains);
  }

  /// Запись — обработка чужого трека: ремикс, кавер, эдит, «ускоренная».
  ///
  /// Проверяется «сырое» название вместе со скобками: пометка живёт именно
  /// там — «Billie Jean (Laus Remix)», «Blinding Lights [Slowed + Reverb]».
  bool _isDerivative(String title) {
    final tokens = RegExp(r'[\p{L}\p{N}]+', unicode: true)
        .allMatches(title.toLowerCase())
        .map((match) => match.group(0)!);
    return tokens.any(_derivativeMarkers.contains);
  }

  /// Значимые слова строки: без регистра, пунктуации и служебных пометок.
  ///
  /// Благодаря разбору на слова «Blinding Lights», «Blinding Lights (Remix)»
  /// и «the weeknd - blinding lights» сводятся к одному набору.
  Set<String> _tokens(String value) {
    final cleaned = _stripDecorations(value).toLowerCase();
    return RegExp(r'[\p{L}\p{N}]+', unicode: true)
        .allMatches(cleaned)
        .map((match) => match.group(0)!)
        .where((token) => token.length > 1 && !_stopWords.contains(token))
        .toSet();
  }

  /// Убирает уточнения в скобках: «(Remix)», «[Live]», «(feat. …)».
  String _stripDecorations(String value) =>
      value.replaceAll(RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]'), ' ').trim();

  /// Первый исполнитель: Genius перечисляет соавторов через «&» и запятые.
  String _primaryArtist(String value) {
    var result = value;
    for (final separator
        in const [' & ', ', ', ' feat', ' featuring', ' with ', ' x ']) {
      final index = result.toLowerCase().indexOf(separator);
      if (index > 0) result = result.substring(0, index);
    }
    return result.trim();
  }

  bool _isSongLength(int? seconds) =>
      seconds != null && seconds >= _minSeconds && seconds <= _maxSeconds;

  /// GET JSON: любой сбой (сеть, статус, разбор) — это просто «не нашлось».
  ///
  /// Резолвер не должен ломать воспроизведение: за ним есть фолбэки,
  /// поэтому ошибки провайдера здесь не выбрасываются наружу.
  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    try {
      final response = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(_timeout);
      if (response.statusCode != 200) return null;

      final decoded = json.decode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      return decoded is Map<String, dynamic> ? decoded : null;
    } on Exception {
      return null;
    }
  }

  void _store(String key, ResolvedTrackStream? value) {
    if (_cache.length >= _cacheLimit) {
      final oldest = _cache.entries.reduce(
        (a, b) => a.value.storedAt.isBefore(b.value.storedAt) ? a : b,
      );
      _cache.remove(oldest.key);
    }
    _cache[key] = _CachedStream(value, DateTime.now());
  }

  String? _nonEmpty(String? value) =>
      (value == null || value.isEmpty) ? null : value;
}

/// Запись кэша: результат поиска и момент сохранения.
class _CachedStream {
  const _CachedStream(this.value, this.storedAt);

  final ResolvedTrackStream? value;
  final DateTime storedAt;
}
