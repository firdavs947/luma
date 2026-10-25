import 'dart:convert';

import 'package:animation_test_app/src/features/catalog/data/cinemeta_video_source.dart';
import 'package:animation_test_app/src/features/catalog/domain/media_item.dart';
import 'package:animation_test_app/src/features/catalog/domain/video_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _movie({
  String id = 'tt0133093',
  String name = 'The Matrix',
  List<String> genres = const ['Action', 'Sci-Fi'],
}) => {
  'id': id,
  'imdb_id': id,
  'type': 'movie',
  'name': name,
  'genres': genres,
  'cast': ['Keanu Reeves', 'Laurence Fishburne', 'Carrie-Anne Moss'],
  'director': ['Lana Wachowski', 'Lilly Wachowski'],
  'country': 'USA',
  'released': '1999-03-31T00:00:00.000Z',
  'runtime': '136 min',
  'imdbRating': '8.7',
  'popularity': 1234.5,
  'description': 'A hacker learns the truth about his reality.',
  'trailers': [
    {'source': 'vKQi3bBA1y8'},
  ],
};

Map<String, dynamic> _cartoon() => {
  ..._movie(id: 'tt0114709', name: 'Toy Story'),
  'genres': ['Animation', 'Comedy'],
};

Map<String, dynamic> _payload(Iterable<Map<String, dynamic>> metas) => {
  'metas': metas.toList(),
};

void main() {
  group('CinemetaVideoSource', () {
    test(
      'maps catalog metas and drops animation from the movies feed',
      () async {
        final requested = <Uri>[];
        final source = CinemetaVideoSource(
          client: MockClient((request) async {
            requested.add(request.url);
            return http.Response(
              json.encode(_payload([_movie(), _cartoon()])),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );

        final items = await source.byCategory(MediaCategory.movies, limit: 24);

        expect(requested.single.path, '/top/catalog/movie/top.json');
        expect(items, hasLength(1));

        final item = items.single;
        expect(item.id, 'cm-movie-tt0133093');
        expect(item.imdbId, 'tt0133093');
        expect(item.externalId, 'tt0133093');
        expect(item.category, MediaCategory.movies);
        expect(item.origin, MediaOrigin.cinemeta);
        expect(item.score, 8.7);
        expect(item.rating, closeTo(4.35, 0.001));
        expect(item.durationLabel, '2ч 16м');
        expect(item.releaseDate, '1999-03-31');
        expect(item.year, 1999);
        expect(item.country, 'USA');
        expect(item.cast, hasLength(3));
        expect(item.directors, ['Lana Wachowski', 'Lilly Wachowski']);
        expect(item.subtitle, 'Lana Wachowski');
        expect(
          item.imageUrl,
          'https://images.metahub.space/poster/large/tt0133093/img',
        );
        expect(
          item.backdropUrl,
          'https://images.metahub.space/background/large/tt0133093/img',
        );
        expect(
          item.logoUrl,
          'https://images.metahub.space/logo/medium/tt0133093/img',
        );
        expect(item.trailerId, 'vKQi3bBA1y8');
        expect(item.popularity, 1234500);
      },
    );

    test('search maps categories and trailers', () async {
      final source = CinemetaVideoSource(
        client: MockClient((request) async {
          expect(request.url.path, contains('/top/search=matrix.json'));
          return http.Response(
            json.encode(_payload([_movie(), _cartoon()])),
            200,
          );
        }),
      );

      final items = await source.search('matrix');

      expect(items, hasLength(2));
      final animated = items.firstWhere(
        (item) => item.category == MediaCategory.cartoons,
      );
      expect(animated.id, 'cm-movie-tt0114709');
      expect(animated.genres, contains('Animation'));
    });

    test('skips records without a trailer or IMDb id', () async {
      final source = CinemetaVideoSource(
        client: MockClient(
          (_) async => http.Response(
            json.encode(
              _payload([
                {..._movie(id: 'tmdb-123'), 'imdb_id': ''},
                {..._movie(), 'trailers': const <Object>[]},
              ]),
            ),
            200,
          ),
        ),
      );

      expect(await source.search('matrix'), isEmpty);
    });

    test('resolveStream opens the official trailer', () async {
      final source = CinemetaVideoSource(
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      final stream = await source.resolveStream(
        MediaItem(
          id: 'cm-movie-tt0133093',
          title: 'The Matrix',
          subtitle: 'Фильм',
          category: MediaCategory.movies,
          year: 1999,
          durationLabel: '2ч 16м',
          rating: 4.35,
          score: 8.7,
          trailerId: 'vKQi3bBA1y8',
          origin: MediaOrigin.cinemeta,
        ),
      );

      expect(stream, isNotNull);
      expect(stream!.kind, PlaybackKind.trailer);
      expect(stream.isYoutube, isTrue);
      expect(stream.isTrailer, isTrue);
      expect(stream.youtubeId, 'vKQi3bBA1y8');
      expect(stream.pageUrl, 'https://www.youtube.com/watch?v=vKQi3bBA1y8');
      expect(stream.providerLabel, 'Официальный трейлер');
    });

    test('enrich merges details while keeping local progress', () async {
      final source = CinemetaVideoSource(
        client: MockClient((request) async {
          expect(
            request.url.toString(),
            'https://v3-cinemeta.strem.io/meta/movie/tt0133093.json',
          );
          return http.Response(
            json.encode({
              'meta': {
                ..._movie(),
                'cast': ['Keanu Reeves', 'Carrie-Anne Moss'],
                'trailers': [
                  {'source': 'vKQi3bBA1y8'},
                ],
              },
            }),
            200,
          );
        }),
      );

      final enriched = await source.enrich(
        const MediaItem(
          id: 'cm-movie-tt0133093',
          title: 'The Matrix',
          subtitle: 'Фильм',
          category: MediaCategory.movies,
          year: 1999,
          durationLabel: '',
          rating: 0,
          isFavorite: true,
          progress: 0.42,
          imdbId: 'tt0133093',
          externalId: 'tt0133093',
          origin: MediaOrigin.cinemeta,
        ),
      );

      expect(enriched.title, 'The Matrix');
      expect(enriched.cast, ['Keanu Reeves', 'Carrie-Anne Moss']);
      expect(enriched.isFavorite, isTrue);
      expect(enriched.progress, 0.42);
    });
  });
}
