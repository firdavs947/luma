import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/genius_exception.dart';
import 'genius_config.dart';

/// Низкоуровневый клиент Genius API.
///
/// Отвечает только за транспорт: подстановку токена, кэширование ответов,
/// разворачивание конверта `{ meta, response }` и превращение не-200
/// ответов в [GeniusException].
class GeniusApi {
  GeniusApi({required this._config, http.Client? client})
      : _client = client ?? http.Client();

  static const _baseUrl = 'https://api.genius.com';
  static const _timeout = Duration(seconds: 15);

  /// Сколько живёт закэшированный ответ.
  static const _cacheTtl = Duration(minutes: 10);

  /// Предел размера кэша: каталог листается долго, память не должна расти.
  static const _cacheLimit = 250;

  /// Предохранитель от бесконечного обхода страниц.
  static const _maxPages = 20;

  final GeniusConfig _config;
  final http.Client _client;

  /// Кэш успешных ответов по полному URL запроса.
  ///
  /// Лента, треклист и поиск многократно обращаются к одним и тем же
  /// эндпоинтам (лента → альбом → назад), поэтому повторные запросы
  /// отдаются из памяти — это заметно ускоряет переходы и бережёт лимит.
  final _cache = <String, _CacheEntry>{};

  bool get isConfigured => _config.isConfigured;

  /// GET-запрос с кэшированием.
  ///
  /// Возвращает содержимое узла `response` — именно там Genius размещает
  /// данные (`hits`, `songs`, `album`, `tracks`).
  Future<Map<String, dynamic>> get(
    String path, [
    Map<String, String>? query,
  ]) async {
    if (!_config.isConfigured) throw const GeniusNotConfiguredException();

    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    final key = uri.toString();

    final cached = _readCache(key);
    if (cached != null) return cached;

    final response = await _send(uri);

    if (response.statusCode != 200) {
      throw GeniusException(response.statusCode, _describe(response));
    }

    final decoded = json.decode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const GeniusException(200, 'Неожиданный формат ответа Genius');
    }

    final payload = decoded['response'];
    if (payload is! Map<String, dynamic>) {
      throw const GeniusException(200, 'В ответе Genius нет узла response');
    }

    _writeCache(key, payload);
    return payload;
  }

  /// Проходит ВСЕ страницы эндпоинта вида `{ tracks: [...], next_page: 2 }`.
  ///
  /// Genius отдаёт коллекции порциями и вместо `offset` сообщает номер
  /// следующей страницы в поле `next_page`. Без обхода в приложение
  /// попадала бы только первая часть треклиста — именно поэтому «загружалась
  /// не вся музыка». Здесь запрос повторяется, пока `next_page` не опустеет.
  Future<List<Map<String, dynamic>>> getAll(
    String path, {
    required String itemsKey,
    Map<String, String>? query,
    int perPage = 50,
  }) async {
    final items = <Map<String, dynamic>>[];
    var page = 1;
    var guard = 0;

    while (guard++ < _maxPages) {
      final data = await get(path, {
        ...?query,
        'per_page': '$perPage',
        'page': '$page',
      });

      final chunk = (data[itemsKey] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();

      if (chunk.isEmpty) break;
      items.addAll(chunk);

      final next = data['next_page'];
      if (next is! num) break;
      page = next.toInt();
    }

    return items;
  }

  /// Возвращает закэшированный ответ, если он ещё не устарел.
  Map<String, dynamic>? _readCache(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.storedAt) > _cacheTtl) {
      _cache.remove(key);
      return null;
    }
    return entry.body;
  }

  /// Складывает ответ в кэш, вытесняя самые старые записи при переполнении.
  void _writeCache(String key, Map<String, dynamic> body) {
    if (_cache.length >= _cacheLimit) {
      final oldest = _cache.entries.reduce(
        (a, b) => a.value.storedAt.isBefore(b.value.storedAt) ? a : b,
      );
      _cache.remove(oldest.key);
    }
    _cache[key] = _CacheEntry(body, DateTime.now());
  }

  Future<http.Response> _send(Uri uri) async {
    try {
      return await _client.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${_config.accessToken}',
          'Content-Type': 'application/json',
        },
      ).timeout(_timeout);
    } on Exception catch (error) {
      throw GeniusNetworkException('Сеть недоступна: $error');
    }
  }

  /// Достаёт человекочитаемое сообщение об ошибке из тела ответа.
  String _describe(http.Response response) {
    final decoded = _tryDecode(response.body);

    final meta = decoded?['meta'];
    if (meta is Map<String, dynamic>) {
      final message = meta['message'] as String?;
      if (message != null && message.isNotEmpty) return message;
    }

    // Genius на неверный токен отвечает `{"error":"invalid_token"}`.
    final error = decoded?['error'];
    if (error is String && error.isNotEmpty) {
      return error == 'invalid_token'
          ? 'Неверный токен Genius. Проверьте GENIUS_ACCESS_TOKEN.'
          : error;
    }

    if (response.body.isEmpty) return 'Ошибка ${response.statusCode}';
    return response.body;
  }

  Map<String, dynamic>? _tryDecode(String body) {
    try {
      final decoded = json.decode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}

/// Запись кэша: тело ответа и момент сохранения.
class _CacheEntry {
  const _CacheEntry(this.body, this.storedAt);

  final Map<String, dynamic> body;
  final DateTime storedAt;
}
