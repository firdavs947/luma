import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/media_item.dart';
import '../domain/music_source.dart';

/// Источник музыки на базе открытого каталога Audius.
///
/// Audius отдаёт записи целиком — это не 30-секундные ознакомительные
/// фрагменты Spotify, Apple Music или Deezer, — и поддерживает постраничную
/// выдачу через `offset`. Благодаря этому лента и результаты поиска
/// собираются из неограниченной библиотеки: сколько треков попросит
/// интерфейс, столько источник и вернёт.
///
/// Ссылка на звук кладётся прямо в [MediaItem.previewUrl], поэтому плеер
/// запускает полную версию сразу, без обращения к резолверу.
class AudiusMusicSource implements MusicSource {
  AudiusMusicSource({http.Client? client, this._fallback})
      : _client = client ?? http.Client();

  static const _base = 'https://api.audius.co';
  static const _appName = 'LUMA';

  /// Размер страницы поисковой выдачи.
  static const _pageSize = 20;

  /// Сколько треков показывать в ленте главного экрана.
  static const _featuredLimit = 40;

  /// Снисходительный таймаут: поиск по каталогу иногда отвечает не сразу.
  static const _timeout = Duration(seconds: 10);

  /// Границы длительности: отсекаем короткие нарезки и длинные диджей-сеты.
  static const _minSeconds = 30;
  static const _maxSeconds = 3600;

  final http.Client _client;

  /// Источник, к которому обращаемся, если Audius недоступен: приложение
  /// не должно оставаться без музыки из-за внешнего сервиса.
  final MusicSource? _fallback;

  @override
  Future<List<MediaItem>> featured() async {
    final page = await _tracks('/v1/tracks/trending', {
      'app_name': _appName,
      'limit': '$_featuredLimit',
      'time': 'week',
    });

    if (page.items.isNotEmpty) return page.items;
    return await _fallback?.featured() ?? const [];
  }

  @override
  Future<MusicSearchPage> search(String query, {int offset = 0}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return MusicSearchPage.empty;

    final page = await _tracks('/v1/tracks/search', {
      'query': trimmed,
      'app_name': _appName,
      'limit': '$_pageSize',
      'offset': '$offset',
    });

    // Пустая первая страница означает, что каталог не ответил: отдаём
    // фолбэк, чтобы поиск не «опустел» целиком из-за сети.
    if (page.items.isEmpty && offset == 0) {
      final fallback = _fallback;
      if (fallback != null) return fallback.search(trimmed);
    }

    return MusicSearchPage(items: page.items, hasMore: page.hasMore);
  }

  /// Запрашивает треки и приводит их к модели каталога.
  Future<({List<MediaItem> items, bool hasMore})> _tracks(
    String path,
    Map<String, String> query,
  ) async {
    final payload = await _getJson(
      Uri.parse('$_base$path').replace(queryParameters: query),
    );

    final data = payload?['data'];
    if (data is! List) return (items: const <MediaItem>[], hasMore: false);

    final items = <MediaItem>[];
    for (final raw in data) {
      if (raw is! Map<String, dynamic>) continue;
      final item = _map(raw);
      if (item != null) items.add(item);
    }

    // Признак «есть ещё» считается по сырой выдаче, а не по числу
    // отфильтрованных позиций: иначе одна нарезка в конце страницы
    // обрывала бы постраничную загрузку раньше времени.
    return (items: items, hasMore: data.length >= _pageSize);
  }

  /// Преобразует запись Audius в элемент каталога.
  ///
  /// Возвращает `null`, если запись нельзя воспроизвести или её длительность
  /// вне допустимых границ.
  MediaItem? _map(Map<String, dynamic> raw) {
    if (raw['is_streamable'] != true) return null;
    if (raw['is_available'] == false) return null;

    final id = _nonEmpty(raw['id'] as String?);
    final title = _nonEmpty(raw['title'] as String?);
    final seconds = (raw['duration'] as num?)?.toInt();

    if (id == null || title == null || !_isTrackLength(seconds)) return null;

    return MediaItem(
      id: 'audius_$id',
      title: title,
      subtitle: _artistOf(raw),
      category: MediaCategory.music,
      year: _yearOf(raw),
      durationLabel: _durationLabel(seconds!),
      // У Audius нет пользовательского рейтинга — оценку не показываем.
      rating: 0,
      description: 'Полная версия трека из открытого каталога Audius.',
      imageUrl: _artworkOf(raw),
      previewUrl: '$_base/v1/tracks/$id/stream?app_name=$_appName',
      isTrack: true,
    );
  }

  /// Исполнитель трека: имя, а если его нет — служебный `handle`.
  String _artistOf(Map<String, dynamic> raw) {
    final user = raw['user'];
    if (user is Map<String, dynamic>) {
      final name = _nonEmpty(user['name'] as String?);
      if (name != null) return name;

      final handle = _nonEmpty(user['handle'] as String?);
      if (handle != null) return handle;
    }
    return 'Audius';
  }

  /// Обложка максимально доступного размера.
  String? _artworkOf(Map<String, dynamic> raw) {
    final artwork = raw['artwork'];
    if (artwork is! Map<String, dynamic>) return null;

    for (final size in const ['480x480', '1000x1000', '150x150']) {
      final url = _nonEmpty(artwork[size] as String?);
      if (url != null) return url;
    }
    return null;
  }

  /// Год выпуска: сначала дата релиза, затем дата загрузки в каталог.
  int _yearOf(Map<String, dynamic> raw) {
    for (final key in const ['release_date', 'created_at']) {
      final value = raw[key];
      if (value is! String || value.length < 4) continue;

      final year = int.tryParse(value.substring(0, 4));
      if (year != null && year > 1900) return year;
    }
    return DateTime.now().year;
  }

  bool _isTrackLength(int? seconds) =>
      seconds != null && seconds >= _minSeconds && seconds <= _maxSeconds;

  /// Длительность в формате `3:42`.
  String _durationLabel(int seconds) {
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }

  /// GET JSON: любой сбой (сеть, статус, разбор) — это просто «нет данных».
  ///
  /// Источник не должен ломать каталог: за ним есть фолбэк, поэтому ошибки
  /// провайдера здесь не выбрасываются наружу.
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

  String? _nonEmpty(String? value) =>
      (value == null || value.isEmpty) ? null : value;
}
