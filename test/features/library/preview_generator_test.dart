import 'dart:typed_data';

import 'package:animation_test_app/src/features/library/data/audio_file_inspector.dart';
import 'package:animation_test_app/src/features/library/data/preview_generator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'audio_fixtures.dart';

/// Читает 32-битное число little-endian — так записаны размеры в RIFF.
int readUint32(Uint8List bytes, int offset) =>
    ByteData.view(bytes.buffer, bytes.offsetInBytes)
        .getUint32(offset, Endian.little);

void main() {
  const inspector = AudioFileInspector();

  group('PreviewGenerator: WAV', () {
    final source = buildWav(seconds: 60, sampleRate: 8000);

    test('пересобирает контейнер RIFF на 30 секунд', () {
      final preview = PreviewGenerator.build(bytes: source, fileName: 'demo.wav');

      expect(preview, isNotNull);
      expect(String.fromCharCodes(preview!.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(preview.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(preview.sublist(36, 40)), 'data');
      // 16000 байт/с × 30 с.
      expect(readUint32(preview, 40), 16000 * 30);
      expect(readUint32(preview, 4), preview.length - 8);
    });

    test('фрагмент остаётся корректным WAV', () {
      final preview = PreviewGenerator.build(bytes: source, fileName: 'demo.wav')!;
      final metadata = inspector.inspect(bytes: preview, fileName: 'preview.wav');

      expect(metadata.duration, PreviewGenerator.length);
      expect(metadata.sampleRate, 8000);
      expect(metadata.channels, 1);
    });

    test('оставляет файл целиком, если он короче превью', () {
      final short = buildWav(seconds: 20, sampleRate: 8000);
      final preview = PreviewGenerator.build(bytes: short, fileName: 'demo.wav')!;
      final metadata = inspector.inspect(bytes: preview, fileName: 'preview.wav');

      expect(metadata.duration, const Duration(seconds: 20));
    });
  });

  group('PreviewGenerator: MP3', () {
    final source = buildMp3(frames: 1200);

    test('отбирает целые кадры MPEG', () {
      final preview = PreviewGenerator.build(bytes: source, fileName: 'demo.mp3');

      expect(preview, isNotNull);
      expect(preview!.length, lessThan(source.length));
      expect(preview.length % mp3FrameLength, 0);
      expect(preview[0], 0xFF);
      expect(preview[1], 0xFB);
    });

    test('длительность фрагмента близка к 30 секундам', () {
      final preview = PreviewGenerator.build(bytes: source, fileName: 'demo.mp3')!;
      final metadata = inspector.inspect(bytes: preview, fileName: 'preview.mp3');

      expect(metadata.duration.inMilliseconds, closeTo(30000, 150));
      expect(metadata.bitrateKbps, 128);
      expect(metadata.sampleRate, 44100);
    });
  });

  group('PreviewGenerator: AAC', () {
    final source = buildAac(frames: 1400);

    test('отбирает целые кадры ADTS', () {
      final preview = PreviewGenerator.build(bytes: source, fileName: 'demo.aac');

      expect(preview, isNotNull);
      expect(preview!.length, lessThan(source.length));
      expect(preview.length % aacFrameLength, 0);
    });

    test('длительность фрагмента близка к 30 секундам', () {
      final preview = PreviewGenerator.build(bytes: source, fileName: 'demo.aac')!;
      final metadata = inspector.inspect(bytes: preview, fileName: 'preview.aac');

      expect(metadata.duration.inMilliseconds, closeTo(30000, 150));
      expect(metadata.sampleRate, 44100);
    });
  });

  group('PreviewGenerator: ограничения', () {
    test('для FLAC фрагмент не собирается', () {
      expect(
        PreviewGenerator.build(bytes: buildFlac(), fileName: 'demo.flac'),
        isNull,
      );
    });

    test('для неподдерживаемого формата возвращает null', () {
      expect(
        PreviewGenerator.build(bytes: buildWav(), fileName: 'demo.ogg'),
        isNull,
      );
    });

    test('для слишком короткого файла возвращает null', () {
      expect(
        PreviewGenerator.build(bytes: Uint8List(8), fileName: 'demo.wav'),
        isNull,
      );
    });

    test('для повреждённого WAV возвращает null', () {
      final broken = buildWav()..[0] = 0x00;

      expect(PreviewGenerator.build(bytes: broken, fileName: 'demo.wav'), isNull);
    });
  });
}
