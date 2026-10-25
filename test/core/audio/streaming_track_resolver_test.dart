import 'dart:convert';

import 'package:animation_test_app/src/core/audio/streaming_track_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Собирает ответ провайдера с заданным телом.
http.Response _json(Object body) => http.Response(
  json.encode(body),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

/// Ответ Audius: одна запись каталога.
Map<String, dynamic> _audiusTrack({
  required String id,
  required String title,
  required String userName,
  String handle = 'artist',
  int duration = 200,
  bool streamable = true,
}) => {
  'id': id,
  'title': title,
  'duration': duration,
  'is_streamable': streamable,
  'user': {'name': userName, 'handle': handle},
};

/// Резолвер, отвечающий фиксированным телом Audius.
///
/// Запросы считаются: по их числу проверяются кэш и повторный поиск.
StreamingTrackResolver _resolver({
  Object? audius,
  void Function(Uri url)? onRequest,
}) {
  return StreamingTrackResolver(
    client: MockClient((request) async {
      onRequest?.call(request.url);
      if (request.url.host == 'api.audius.co') {
        if (audius == null) return http.Response('', 500);
        return _json(audius);
      }
      return http.Response('', 404);
    }),
  );
}

void main() {
  group('StreamingTrackResolver.resolve', () {
    test('берёт полную запись из Audius', () async {
      final resolver = _resolver(
        audius: {
          'data': [
            _audiusTrack(
              id: 'y9a7Z',
              title: 'Blinding Lights',
              userName: 'The Weeknd',
            ),
          ],
        },
      );

      final stream = await resolver.resolve(
        title: 'Blinding Lights',
        artist: 'The Weeknd',
      );

      expect(stream, isNotNull);
      expect(stream!.source, 'Audius');
      expect(stream.isFullLength, isTrue);
      expect(stream.url, contains('/v1/tracks/y9a7Z/stream'));
    });

    test('предпочитает записи исполнителя, а не первый кавер', () async {
      final resolver = _resolver(
        audius: {
          'data': [
            _audiusTrack(
              id: 'cover1',
              title: 'Blinding Lights (Cover)',
              userName: 'Kamileon',
            ),
            _audiusTrack(
              id: 'official',
              title: 'Blinding Lights',
              userName: 'The Weeknd',
            ),
          ],
        },
      );

      final stream = await resolver.resolve(
        title: 'Blinding Lights',
        artist: 'The Weeknd',
      );

      expect(stream!.url, contains('/tracks/official/stream'));
    });

    test('отбрасывает короткие нарезки и длинные подкасты', () async {
      final resolver = _resolver(
        audius: {
          'data': [
            _audiusTrack(
              id: 'podcast',
              title: 'The Bodhi Show Ep. 155',
              userName: 'DJ Bodhi',
              duration: 1904,
            ),
            _audiusTrack(
              id: 'sample',
              title: 'Blinding Lights',
              userName: 'The Weeknd',
              duration: 16,
            ),
          ],
        },
      );

      final stream = await resolver.resolve(
        title: 'Blinding Lights',
        artist: 'The Weeknd',
      );

      expect(stream, isNull);
    });

    test('пропускает недоступные для прослушивания записи', () async {
      final resolver = _resolver(
        audius: {
          'data': [
            _audiusTrack(
              id: 'locked',
              title: 'Blinding Lights',
              userName: 'The Weeknd',
              streamable: false,
            ),
          ],
        },
      );

      final stream = await resolver.resolve(
        title: 'Blinding Lights',
        artist: 'The Weeknd',
      );

      expect(stream, isNull);
    });

    test('не подменяет оригинал ремиксом', () async {
      final resolver = _resolver(
        audius: {
          'data': [
            _audiusTrack(
              id: 'remix',
              title: 'Billie Jean (Remix)',
              userName: 'Michael Jackson',
            ),
            _audiusTrack(
              id: 'cover',
              title: 'Billie Jean (Michael Jackson Cover)',
              userName: 'Katar',
            ),
          ],
        },
      );

      final stream = await resolver.resolve(
        title: 'Billie Jean',
        artist: 'Michael Jackson',
      );

      // 30-секундные фрагменты исключены из проекта, поэтому единственный
      // корректный ответ здесь — «полной записи нет».
      expect(stream, isNull);
    });

    test('возвращает null, если подходящей записи нет', () async {
      final resolver = _resolver(
        audius: {
          'data': [
            _audiusTrack(
              id: 'other',
              title: 'Совсем другая песня',
              userName: 'Кто-то',
            ),
          ],
        },
      );

      final stream = await resolver.resolve(
        title: 'Blinding Lights',
        artist: 'The Weeknd',
      );

      expect(stream, isNull);
    });

    test('сбой сети не выбрасывает исключение', () async {
      final resolver = _resolver(audius: null);

      final stream = await resolver.resolve(
        title: 'Blinding Lights',
        artist: 'The Weeknd',
      );

      expect(stream, isNull);
    });

    test('если поиск по названию и исполнителю пуст, ищет только по названию',
        () async {
      final queries = <String>[];
      final resolver = _resolver(
        audius: {
          'data': [
            _audiusTrack(
              id: 'alt',
              title: 'Blinding Lights',
              userName: 'The Weeknd',
            ),
          ],
        },
        onRequest: (url) => queries.add(url.queryParameters['query'] ?? ''),
      );

      await resolver.resolve(title: 'Blinding Lights', artist: 'The Weeknd');

      expect(queries.first, contains('The Weeknd'));
      expect(queries.first, contains('Blinding Lights'));
    });

    test('повторный запрос берётся из кэша', () async {
      var requests = 0;
      final resolver = _resolver(
        audius: {
          'data': [
            _audiusTrack(
              id: 'y9a7Z',
              title: 'Blinding Lights',
              userName: 'The Weeknd',
            ),
          ],
        },
        onRequest: (_) => requests++,
      );

      await resolver.resolve(title: 'Blinding Lights', artist: 'The Weeknd');
      final afterFirstSearch = requests;

      // Уточнения в скобках не меняют ключ кэша: «(Remix)» отбрасывается,
      // поэтому повторный запрос не идёт в сеть.
      await resolver.resolve(
        title: 'Blinding Lights (Remix)',
        artist: 'The Weeknd',
      );

      expect(requests, afterFirstSearch);
    });

    test('кэширует и отсутствие результата', () async {
      var requests = 0;
      final resolver = _resolver(
        audius: {'data': <Object>[]},
        onRequest: (_) => requests++,
      );

      await resolver.resolve(title: 'Ничего', artist: 'Никто');
      final afterFirstSearch = requests;

      await resolver.resolve(title: 'Ничего', artist: 'Никто');

      expect(requests, afterFirstSearch);
      // Пустая выдача приводит к повторному поиску только по названию,
      // поэтому первый проход — это два обращения к каталогу.
      expect(afterFirstSearch, 2);
    });
  });
}
