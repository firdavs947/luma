import 'dart:convert';

import 'package:animation_test_app/src/features/catalog/data/anilist_video_source.dart';
import 'package:animation_test_app/src/features/catalog/domain/media_item.dart';
import 'package:animation_test_app/src/features/catalog/domain/video_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _media({
  int id = 21,
  String? trailerId = 'MGRm4IzK1SQ',
}) => {
  'id': id,
  'idMal': 21,
  'format': 'TV',
  'status': 'RELEASING',
  'episodes': 12,
  'duration': 24,
  'averageScore': 84,
  'popularity': 250000,
  'favourites': 9000,
  'countryOfOrigin': 'JP',
  'coverImage': {
    'extraLarge': 'https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx21.jpg',
    'color': '#e4a15d',
  },
  'bannerImage':
      'https://s4.anilist.co/file/anilistcdn/media/anime/banner/21.jpg',
  'title': {'english': 'One Piece', 'romaji': 'One Piece', 'native': 'ワンピース'},
  'description': '<p>Gol D. Roger was the <b>King of the Pirates</b>.</p>',
  'genres': ['Action', 'Adventure', 'Fantasy'],
  'trailer': trailerId == null ? null : {'id': trailerId, 'site': 'youtube'},
  'studios': {
    'nodes': [
      {'name': 'Toei Animation'},
    ],
  },
  'startDate': {'year': 1999, 'month': 10, 'day': 20},
  'endDate': {'year': null, 'month': null, 'day': null},
  'nextAiringEpisode': {'episode': 1147},
};

Map<String, dynamic> _page(Iterable<Map<String, dynamic>> media) => {
  'data': {
    'Page': {
      'pageInfo': {'hasNextPage': false, 'total': media.length},
      'media': media.toList(),
    },
  },
};

void main() {
  group('AniListVideoSource', () {
    test('maps seasonal anime with HD artwork and a trailer', () async {
      late Map<String, dynamic> body;
      final source = AniListVideoSource(
        clock: () => DateTime(2026, 10, 25),
        client: MockClient((request) async {
          body = json.decode(request.body) as Map<String, dynamic>;
          return http.Response.bytes(
            utf8.encode(json.encode(_page([_media()]))),
            200,
            headers: const {"content-type": "application/json; charset=utf-8"},
          );
        }),
      );

      final items = await source.byCategory(MediaCategory.anime, limit: 14);

      expect(items, hasLength(1));
      final item = items.single;
      expect(item.id, 'al-21');
      expect(item.externalId, '21');
      expect(item.title, 'One Piece');
      expect(item.subtitle, 'Toei Animation');
      expect(item.category, MediaCategory.anime);
      expect(item.origin, MediaOrigin.anilist);
      expect(item.score, 84);
      expect(item.rating, 4.2);
      expect(item.year, 1999);
      expect(item.releaseDate, '1999-10-20');
      expect(item.durationLabel, '12 эп · 24м');
      expect(item.country, 'Япония');
      expect(item.description, 'Gol D. Roger was the King of the Pirates .');
      expect(
        item.imageUrl,
        'https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx21.jpg',
      );
      expect(
        item.backdropUrl,
        'https://s4.anilist.co/file/anilistcdn/media/anime/banner/21.jpg',
      );
      expect(item.trailerId, 'MGRm4IzK1SQ');
      expect(item.directors, ['Toei Animation']);

      final variables = body['variables'] as Map<String, dynamic>;
      expect(variables['season'], 'FALL');
      expect(variables['seasonYear'], 2026);
      expect(variables['sort'], ['POPULARITY_DESC']);
    });

    test('search sends the term and maps results', () async {
      late Map<String, dynamic> body;
      final source = AniListVideoSource(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          body = json.decode(request.body) as Map<String, dynamic>;
          return http.Response.bytes(
            utf8.encode(json.encode(_page([_media()]))),
            200,
            headers: const {"content-type": "application/json; charset=utf-8"},
          );
        }),
      );

      final items = await source.search('one piece');

      expect(items.single.trailerId, 'MGRm4IzK1SQ');
      final variables = body['variables'] as Map<String, dynamic>;
      expect(variables['search'], 'one piece');
      expect(variables['sort'], ['SEARCH_MATCH']);
    });

    test('skips records without a YouTube trailer', () async {
      final source = AniListVideoSource(
        client: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(json.encode(_page([_media(trailerId: null)]))),
            200,
          ),
        ),
      );

      expect(await source.search('one piece'), isEmpty);
    });

    test('other categories are resolved without a network call', () async {
      var calls = 0;
      final source = AniListVideoSource(
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );

      expect(await source.byCategory(MediaCategory.movies), isEmpty);
      expect(calls, 0);
    });

    test('resolveStream opens the YouTube trailer', () async {
      final source = AniListVideoSource(
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      final stream = await source.resolveStream(
        const MediaItem(
          id: 'al-21',
          title: 'One Piece',
          subtitle: 'Toei Animation',
          category: MediaCategory.anime,
          year: 1999,
          durationLabel: '12 эп · 24м',
          rating: 4.2,
          score: 84,
          trailerId: 'MGRm4IzK1SQ',
          origin: MediaOrigin.anilist,
        ),
      );

      expect(stream!.kind, PlaybackKind.trailer);
      expect(stream.youtubeId, 'MGRm4IzK1SQ');
      expect(stream.providerLabel, 'Официальный трейлер · AniList');
      expect(stream.pageUrl, 'https://www.youtube.com/watch?v=MGRm4IzK1SQ');
    });
  });
}
