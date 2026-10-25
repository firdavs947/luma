import '../domain/genius_models.dart';
import '../domain/genius_repository.dart';
import 'genius_api.dart';
import 'genius_config.dart';

/// Реализация [GeniusRepository] поверх официального Genius API.
///
/// Ключевой момент: там, где Genius отдаёт коллекцию порциями (треклист
/// альбома), запрос повторяется по `next_page` до конца списка. Иначе в
/// приложение попадала бы только первая часть треклиста.
class GeniusRemoteRepository implements GeniusRepository {
  GeniusRemoteRepository({required this._api, required this._config});

  /// Собирает репозиторий из параметров окружения (`--dart-define`).
  factory GeniusRemoteRepository.fromEnvironment() {
    final config = GeniusConfig.fromEnvironment();
    return GeniusRemoteRepository(
      api: GeniusApi(config: config),
      config: config,
    );
  }

  final GeniusApi _api;
  final GeniusConfig _config;

  @override
  bool get isConfigured => _config.isConfigured;

  @override
  Future<List<GeniusSong>> searchSongs(String query) async {
    final data = await _api.get('/search', {'q': query});
    final hits = data['hits'] as List<dynamic>? ?? const [];

    return hits
        .whereType<Map<String, dynamic>>()
        // Genius возвращает в выдаче разные типы; приложению нужны песни.
        .where((hit) => hit['type'] == null || hit['type'] == 'song')
        .map((hit) => hit['result'])
        .whereType<Map<String, dynamic>>()
        .map(GeniusSong.fromJson)
        .where((song) => song.id.isNotEmpty)
        .toList();
  }

  @override
  Future<GeniusSong> getSong(String id) async {
    final data = await _api.get('/songs/$id');
    final song = data['song'] as Map<String, dynamic>? ?? const {};
    return GeniusSong.fromJson(song);
  }

  @override
  Future<GeniusAlbum> getAlbum(String id) async {
    final data = await _api.get('/albums/$id');
    final album = data['album'] as Map<String, dynamic>? ?? const {};

    // `/albums/{id}` не отдаёт треки: полный треклист выгружается
    // отдельным пагинируемым эндпоинтом `/albums/{id}/tracks`.
    final items = await _api.getAll(
      '/albums/$id/tracks',
      itemsKey: 'tracks',
      perPage: 50,
    );

    final tracks = items
        .map((entry) => entry['song'])
        .whereType<Map<String, dynamic>>()
        .map(GeniusSong.fromJson)
        .where((song) => song.id.isNotEmpty)
        .toList();

    return GeniusAlbum.fromJson(album, tracks: tracks);
  }

  @override
  Future<List<GeniusSong>> songsByArtist(
    String artistId, {
    int perPage = 20,
    int page = 1,
  }) async {
    final data = await _api.get('/artists/$artistId/songs', {
      'sort': 'popularity',
      'per_page': '$perPage',
      'page': '$page',
    });

    return (data['songs'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(GeniusSong.fromJson)
        .where((song) => song.id.isNotEmpty)
        .toList();
  }
}
