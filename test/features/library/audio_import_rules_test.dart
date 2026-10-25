import 'package:animation_test_app/src/features/library/domain/audio_import_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AudioImportRules.extensionOf', () {
    test('приводит расширение к нижнему регистру', () {
      expect(AudioImportRules.extensionOf('Track.MP3'), 'mp3');
      expect(AudioImportRules.extensionOf('Track.FlAc'), 'flac');
    });

    test('берёт только последнее расширение', () {
      expect(AudioImportRules.extensionOf('song.live.version.wav'), 'wav');
    });

    test('возвращает пустую строку, если расширения нет', () {
      expect(AudioImportRules.extensionOf('song'), '');
      expect(AudioImportRules.extensionOf('song.'), '');
      expect(AudioImportRules.extensionOf('.gitignore'), '');
    });
  });

  group('AudioImportRules.validateAudio', () {
    test('пропускает файл поддерживаемого формата', () {
      expect(
        AudioImportRules.validateAudio(fileName: 'song.mp3', sizeBytes: 1024),
        isNull,
      );
    });

    test('пропускает файл ровно на границе лимита', () {
      expect(
        AudioImportRules.validateAudio(
          fileName: 'song.flac',
          sizeBytes: AudioImportRules.maxAudioBytes,
        ),
        isNull,
      );
    });

    test('сообщает о неподдерживаемом формате', () {
      final message =
          AudioImportRules.validateAudio(fileName: 'song.ogg', sizeBytes: 1024);

      expect(message, contains('OGG'));
      expect(message, contains('не поддерживается'));
    });

    test('сообщает об отсутствии расширения', () {
      final message =
          AudioImportRules.validateAudio(fileName: 'song', sizeBytes: 1024);

      expect(message, contains('без расширения'));
    });

    test('сообщает о пустом файле', () {
      expect(
        AudioImportRules.validateAudio(fileName: 'song.wav', sizeBytes: 0),
        'Файл пуст — выберите другой.',
      );
    });

    test('сообщает о превышении лимита', () {
      final message = AudioImportRules.validateAudio(
        fileName: 'song.aac',
        sizeBytes: AudioImportRules.maxAudioBytes + 1,
      );

      expect(message, contains('больше лимита'));
      expect(message, contains('50 МБ'));
    });
  });

  group('AudioImportRules.validateCover', () {
    test('пропускает поддерживаемый формат', () {
      expect(
        AudioImportRules.validateCover(fileName: 'cover.png', sizeBytes: 2048),
        isNull,
      );
    });

    test('отклоняет неподдерживаемый формат', () {
      expect(
        AudioImportRules.validateCover(fileName: 'cover.gif', sizeBytes: 2048),
        contains('JPEG'),
      );
    });

    test('сообщает о пустом файле обложки', () {
      expect(
        AudioImportRules.validateCover(fileName: 'cover.jpg', sizeBytes: 0),
        'Файл обложки пуст — выберите другой.',
      );
    });

    test('сообщает о превышении лимита', () {
      expect(
        AudioImportRules.validateCover(
          fileName: 'cover.webp',
          sizeBytes: AudioImportRules.maxCoverBytes + 1,
        ),
        contains('8,0 МБ'),
      );
    });
  });

  group('AudioImportRules.formatBytes', () {
    test('показывает байты', () {
      expect(AudioImportRules.formatBytes(512), '512 Б');
    });

    test('показывает килобайты', () {
      expect(AudioImportRules.formatBytes(2048), '2 КБ');
    });

    test('показывает мегабайты с запятой в дробной части', () {
      expect(AudioImportRules.formatBytes(5 * 1024 * 1024), '5,0 МБ');
    });

    test('округляет крупные значения до целых', () {
      expect(AudioImportRules.formatBytes(AudioImportRules.maxAudioBytes), '50 МБ');
    });
  });

  test('audioFormatsLabel перечисляет форматы для подсказки', () {
    expect(AudioImportRules.audioFormatsLabel, 'MP3, WAV, FLAC, AAC');
  });
}
