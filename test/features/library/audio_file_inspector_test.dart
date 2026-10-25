import 'dart:typed_data';

import 'package:animation_test_app/src/features/library/data/audio_file_inspector.dart';
import 'package:animation_test_app/src/features/library/domain/audio_import_exception.dart';
import 'package:animation_test_app/src/features/library/domain/audio_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

import 'audio_fixtures.dart';

void main() {
  const inspector = AudioFileInspector();

  group('AudioFileInspector: WAV', () {
    test('читает длительность, битрейт и каналы', () {
      final metadata = inspector.inspect(
        bytes: buildWav(seconds: 60, sampleRate: 8000),
        fileName: 'demo.wav',
      );

      expect(metadata.codec, 'WAV / PCM 16 бит');
      expect(metadata.duration, const Duration(seconds: 60));
      expect(metadata.bitrateKbps, 128);
      expect(metadata.sampleRate, 8000);
      expect(metadata.channels, 1);
    });

    test('разбирает стереофайл', () {
      final metadata = inspector.inspect(
        bytes: buildWav(seconds: 10, sampleRate: 44100, channels: 2),
        fileName: 'demo.wav',
      );

      expect(metadata.channels, 2);
      expect(metadata.sampleRate, 44100);
      expect(metadata.bitrateKbps, 1411);
      expect(metadata.duration, const Duration(seconds: 10));
    });

    test('отклоняет файл без контейнера RIFF', () {
      final bytes = buildWav();
      writeAscii(bytes, 0, 'RIFX');

      expect(
        () => inspector.inspect(bytes: bytes, fileName: 'demo.wav'),
        throwsA(isA<AudioImportException>()),
      );
    });
  });

  group('AudioFileInspector: FLAC', () {
    test('берёт длительность из блока STREAMINFO', () {
      final metadata = inspector.inspect(
        bytes: buildFlac(totalSamples: 1323000, sampleRate: 44100),
        fileName: 'demo.flac',
      );

      expect(metadata.codec, 'FLAC / 16 бит');
      expect(metadata.duration, const Duration(seconds: 30));
      expect(metadata.sampleRate, 44100);
      expect(metadata.channels, 2);
    });

    test('отклоняет поток без звуковых данных', () {
      expect(
        () => inspector.inspect(
          bytes: buildFlac(totalSamples: 0),
          fileName: 'demo.flac',
        ),
        throwsA(isA<AudioImportException>()),
      );
    });
  });

  group('AudioFileInspector: MP3', () {
    test('читает параметры кадра MPEG-1 Layer III', () {
      final metadata = inspector.inspect(
        bytes: buildMp3(frames: 1200),
        fileName: 'demo.mp3',
      );

      expect(metadata.codec, 'MP3');
      expect(metadata.bitrateKbps, 128);
      expect(metadata.sampleRate, 44100);
      expect(metadata.channels, 2);
      expect(metadata.duration.inMilliseconds, closeTo(31275, 60));
    });

    test('находит поток после тега ID3v2', () {
      const frames = 60;
      final tagged = Uint8List(frames * mp3FrameLength + 10);
      tagged.setRange(10, tagged.length, buildMp3(frames: frames));
      writeAscii(tagged, 0, 'ID3');

      final metadata = inspector.inspect(bytes: tagged, fileName: 'demo.mp3');

      expect(metadata.codec, 'MP3');
      expect(metadata.sampleRate, 44100);
      expect(metadata.duration.inMilliseconds, greaterThan(1000));
    });

    test('отклоняет поток без кадров MPEG', () {
      expect(
        () => inspector.inspect(
          bytes: Uint8List(64),
          fileName: 'demo.mp3',
        ),
        throwsA(isA<AudioImportException>()),
      );
    });
  });

  group('AudioFileInspector: AAC', () {
    test('считает длительность по числу кадров ADTS', () {
      final metadata = inspector.inspect(
        bytes: buildAac(frames: 1400),
        fileName: 'demo.aac',
      );

      expect(metadata.codec, 'AAC LC');
      expect(metadata.sampleRate, 44100);
      expect(metadata.channels, 2);
      expect(metadata.duration.inMilliseconds, closeTo(32508, 60));
    });

    test('отклоняет нарушенную структуру кадров', () {
      final bytes = buildAac(frames: 2);
      bytes[aacFrameLength] = 0x00; // Ломаем sync-слово второго кадра.

      expect(
        () => inspector.inspect(bytes: bytes, fileName: 'demo.aac'),
        throwsA(isA<AudioImportException>()),
      );
    });
  });

  group('AudioFileInspector: защита от подмены', () {
    test('отклоняет исполняемый файл Windows', () {
      final bytes = buildWav();
      writeAscii(bytes, 0, 'MZ');

      expect(
        () => inspector.inspect(bytes: bytes, fileName: 'demo.wav'),
        throwsA(
          isA<AudioImportException>().having(
            (exception) => exception.message,
            'message',
            contains('исполняемый файл Windows'),
          ),
        ),
      );
    });

    test('отклоняет архив, переименованный в аудио', () {
      final bytes = buildFlac()
        ..[0] = 0x50
        ..[1] = 0x4B
        ..[2] = 0x03
        ..[3] = 0x04;

      expect(
        () => inspector.inspect(bytes: bytes, fileName: 'demo.flac'),
        throwsA(isA<AudioImportException>()),
      );
    });

    test('отклоняет сценарий командной оболочки', () {
      final bytes = buildMp3(frames: 1);
      writeAscii(bytes, 0, '#!/bin/sh');

      expect(
        () => inspector.inspect(bytes: bytes, fileName: 'demo.mp3'),
        throwsA(isA<AudioImportException>()),
      );
    });

    test('отклоняет слишком короткий файл', () {
      expect(
        () => inspector.inspect(bytes: Uint8List(8), fileName: 'demo.mp3'),
        throwsA(isA<AudioImportException>()),
      );
    });

    test('отклоняет несоответствие содержимого расширению', () {
      expect(
        () => inspector.inspect(bytes: buildWav(), fileName: 'demo.mp3'),
        throwsA(isA<AudioImportException>()),
      );
    });

    test('отклоняет неподдерживаемое расширение', () {
      expect(
        () => inspector.inspect(bytes: buildWav(), fileName: 'demo.ogg'),
        throwsA(isA<AudioImportException>()),
      );
    });
  });

  group('AudioMetadata', () {
    test('форматирует длительность', () {
      const short = AudioMetadata(
        codec: 'MP3',
        duration: Duration(minutes: 3, seconds: 42),
        bitrateKbps: 320,
        sampleRate: 44100,
        channels: 2,
      );
      const long = AudioMetadata(
        codec: 'MP3',
        duration: Duration(hours: 1, minutes: 4, seconds: 20),
        bitrateKbps: 320,
        sampleRate: 44100,
        channels: 2,
      );

      expect(short.durationLabel, '3:42');
      expect(long.durationLabel, '1:04:20');
    });

    test('подписывает раскладку каналов', () {
      const stereo = AudioMetadata(
        codec: 'AAC LC',
        duration: Duration(seconds: 30),
        bitrateKbps: 34,
        sampleRate: 44100,
        channels: 2,
      );

      expect(stereo.channelLabel, 'стерео');
      expect(stereo.summary, 'AAC LC · 34 kbps · 44,1 кГц · стерео');
    });
  });
}
