import 'dart:convert';

import 'package:animation_test_app/src/features/catalog/data/archive_video_source.dart';
import 'package:animation_test_app/src/features/catalog/domain/media_item.dart';
import 'package:animation_test_app/src/features/catalog/domain/video_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _metadata(Iterable<Map<String, Object>> files) =>
    http.Response(json.encode({'files': files.toList()}), 200);

Map<String, Object> _file(
  String name, {
  required String length,
  required String size,
  String format = 'h.264',
}) => {'name': name, 'length': length, 'size': size, 'format': format};

void main() {
  group('ArchiveVideoSource', () {
    test('curated films are free full versions with HD posters', () async {
      final source = ArchiveVideoSource(
        client: MockClient((_) async => _metadata(const [])),
      );

      final films = await source.freeFull();
      final item = films.firstWhere(
        (film) => film.externalId == 'his_girl_friday',
      );

      expect(item.origin, MediaOrigin.archive);
      expect(item.isFreeFull, isTrue);
      expect(item.isVideo, isTrue);
      expect(item.title, 'Его девушка Пятница');
      expect(item.imdbId, 'tt0032599');
      expect(item.score, 7.8);
      expect(
        item.imageUrl,
        'https://images.metahub.space/poster/large/tt0032599/img',
      );
      expect(
        item.backdropUrl,
        'https://images.metahub.space/background/large/tt0032599/img',
      );
      expect(item.category, MediaCategory.movies);
      expect(item.durationLabel, '1ч 32м');
    });

    test('search finds curated films by Russian and original titles', () async {
      final source = ArchiveVideoSource(
        client: MockClient((_) async => _metadata(const [])),
      );

      final byOriginal = await source.search('his girl');
      final byRussian = await source.search('его девушка');

      expect(byOriginal.single.externalId, 'his_girl_friday');
      expect(byRussian.single.externalId, 'his_girl_friday');
      expect(await source.search(''), isEmpty);
    });

    test(
      'resolveStream keeps only full-length MP4 variants, best first',
      () async {
        final requested = <Uri>[];
        final source = ArchiveVideoSource(
          client: MockClient((request) async {
            requested.add(request.url);
            return _metadata([
              _file('trailer.mp4', length: '120', size: '9000000'),
              _file('sample.mp4', length: '5520', size: '900000000'),
              _file('short.mp4', length: '300', size: '90000000'),
              _file('tiny.mp4', length: '5520', size: '1000'),
              _file('film.ogv', length: '5520', size: '900000000'),
              _file(
                'His_Girl_Friday_512kb.mp4',
                length: '5520',
                size: '700000000',
                format: '512Kb MPEG4',
              ),
              _file(
                'His Girl Friday 480p.mp4',
                length: '5520',
                size: '800000000',
              ),
              _file(
                'His_Girl_Friday_720p.mp4',
                length: '5520',
                size: '1200000000',
              ),
              _file(
                'His_Girl_Friday_1080p.mp4',
                length: '5520',
                size: '2200000000',
              ),
            ]);
          }),
        );

        final item = (await source.search('his girl')).single;
        final stream = await source.resolveStream(item);

        expect(
          requested.single.toString(),
          'https://archive.org/metadata/his_girl_friday',
        );

        expect(stream, isNotNull);
        expect(stream!.kind, PlaybackKind.fullFilm);
        expect(stream.isTrailer, isFalse);
        expect(stream.isYoutube, isFalse);
        expect(stream.mimeType, 'video/mp4');
        expect(stream.pageUrl, 'https://archive.org/details/his_girl_friday');
        expect(stream.providerLabel, 'Internet Archive · полный фильм');

        expect(stream.variants, hasLength(4));
        expect(stream.variants.map((variant) => variant.label).toList(), [
          '1080p',
          '720p',
          '480p',
          '1.0 Мбит/с',
        ]);
        expect(
          stream.variants.first.url,
          'https://archive.org/download/his_girl_friday/'
          'His_Girl_Friday_1080p.mp4',
        );
        expect(
          stream.variants[2].url,
          'https://archive.org/download/his_girl_friday/'
          'His%20Girl%20Friday%20480p.mp4',
        );
        expect(stream.variants.first.weight, greaterThan(0));
        expect(stream.url, stream.variants.first.url);
        expect(stream.isAdaptive, isFalse);
      },
    );

    test('returns no stream when metadata has no playable file', () async {
      final source = ArchiveVideoSource(
        client: MockClient(
          (_) async => _metadata([
            _file('trailer.mp4', length: '120', size: '9000000'),
            _file('bonus.ogv', length: '5520', size: '900000000'),
          ]),
        ),
      );

      final item = (await source.search('his girl')).single;
      expect(await source.resolveStream(item), isNull);
    });

    test('returns no stream on network failure', () async {
      final source = ArchiveVideoSource(
        client: MockClient((_) async => http.Response('unavailable', 503)),
      );

      final item = (await source.search('his girl')).single;
      expect(await source.resolveStream(item), isNull);
    });

    test('fullVersionOf matches a Cinemeta record by IMDb id', () async {
      final source = ArchiveVideoSource(
        client: MockClient((_) async => _metadata(const [])),
      );

      final full = await source.fullVersionOf(
        const MediaItem(
          id: 'cm-movie-tt0032599',
          title: 'His Girl Friday',
          subtitle: 'Howard Hawks',
          category: MediaCategory.movies,
          year: 1940,
          durationLabel: '1ч 32м',
          rating: 3.9,
          score: 7.8,
          imdbId: 'tt0032599',
          externalId: 'tt0032599',
          origin: MediaOrigin.cinemeta,
        ),
      );

      expect(full, isNotNull);
      expect(full!.origin, MediaOrigin.archive);
      expect(full.externalId, 'his_girl_friday');
      expect(full.title, 'Его девушка Пятница');
    });
  });
}
