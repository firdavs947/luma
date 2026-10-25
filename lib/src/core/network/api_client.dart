import 'dart:async';
import 'dart:convert';

import 'package:animation_test_app/src/core/network/token_storage.dart';
import 'package:http/http.dart' as http;

/// HTTP-клиент для СВОЕГО бэкенда (Strapi).
/// Для Genius и других сторонних API он не используется — у них свои клиенты.
///
/// Что делает:
///  1. подставляет access-токен в каждый запрос;
///  2. если пришёл 401 — один раз обновляет токены и повторяет запрос;
///  3. если обновить не удалось — чистит сессию и вызывает [onSessionExpired].
class ApiClient {
  ApiClient._();

  static const baseUrl = 'http://10.0.2.2:1337';
  static const _timeout = Duration(seconds: 15);

  /// Вызывается, когда refresh-токен не сработал (например, показать экран логина).
  static void Function()? onSessionExpired;

  /// Общий refresh: если несколько запросов получили 401 одновременно,
  /// токен обновится только один раз.
  static Future<bool>? _refreshing;

  // ───────────────────────── Публичные методы ─────────────────────────

  static Future<http.Response> get(String path) => _send('GET', path);

  static Future<http.Response> post(String path, {Object? body}) =>
      _send('POST', path, body: body);

  static Future<http.Response> put(String path, {Object? body}) =>
      _send('PUT', path, body: body);

  static Future<http.Response> delete(String path) => _send('DELETE', path);

  // ───────────────────────── Отправка запроса ─────────────────────────

  static Future<http.Response> _send(
    String method,
    String path, {
    Object? body,
  }) async {
    final token = await TokenStorage.readAccess();
    final response = await _request(method, path, body, token);

    // Всё хорошо, либо это логин/регистрация (там 401 = неверный пароль,
    // а не истёкший токен).
    if (response.statusCode != 401 || _isAuthPath(path)) return response;

    final refreshed = await _refreshTokens();
    if (!refreshed) return response;

    final newToken = await TokenStorage.readAccess();
    return _request(method, path, body, newToken);
  }

  static Future<http.Response> _request(
    String method,
    String path,
    Object? body,
    String? token,
  ) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers.addAll(_headers(token));

    if (body != null) request.body = json.encode(body);

    final streamed = await request.send().timeout(_timeout);
    return http.Response.fromStream(streamed);
  }

  static Map<String, String> _headers(String? token) => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  static bool _isAuthPath(String path) => path.startsWith('/api/auth/');

  // ───────────────────────── Обновление токена ─────────────────────────

  static Future<bool> _refreshTokens() {
    return _refreshing ??= _doRefresh()
        .then((ok) async {
          if (!ok) {
            await TokenStorage.clear();
            onSessionExpired?.call();
          }
          return ok;
        })
        .whenComplete(() => _refreshing = null);
  }

  static Future<bool> _doRefresh() async {
    final refreshToken = await TokenStorage.readRefresh();
    if (refreshToken == null) return false;

    final response = await http
        .post(
          Uri.parse('$baseUrl/api/auth/refresh'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'refreshToken': refreshToken}),
        )
        .timeout(_timeout);

    // Ошибка сервера — это не «сессия истекла», поэтому не разлогиниваем.
    if (response.statusCode >= 500) {
      throw http.ClientException('Server error ${response.statusCode}');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) return false;

    final data = json.decode(response.body) as Map<String, dynamic>;
    await TokenStorage.save(
      jwt: data['jwt'],
      refreshToken: data['refreshToken'] ?? refreshToken,
    );
    return true;
  }
}
