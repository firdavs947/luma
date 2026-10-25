import 'dart:typed_data';

import '../domain/audio_import_exception.dart';
import '../domain/audio_import_rules.dart';
import '../domain/audio_metadata.dart';

/// Разбор аудиофайлов: проверка целостности и извлечение метаданных.
///
/// Разбор идёт по заголовкам контейнеров (WAV, FLAC, MP3, AAC/ADTS) — без
/// декодирования звука, поэтому занимает миллисекунды. Проверяются три
/// вещи: файл действительно является аудио заявленного формата, структура
/// заголовка не нарушена и из неё можно получить длительность, битрейт,
/// кодек и частоту дискретизации.
class AudioFileInspector {
  const AudioFileInspector();

  /// Меньше этого размера корректный аудиофайл быть не может.
  static const int _minBytes = 16;

  /// Подписи потенциально опасного содержимого: исполняемые файлы, архивы и
  /// сценарии, переименованные в аудио. Такая проверка не заменяет
  /// антивирус, но не даёт сохранить в библиотеке замаскированный файл.
  static const List<(List<int>, String)> _unsafeSignatures = [
    ([0x4D, 0x5A], 'исполняемый файл Windows'),
    ([0x7F, 0x45, 0x4C, 0x46], 'исполняемый файл Linux'),
    ([0xCF, 0xFA, 0xED, 0xFE], 'исполняемый файл macOS'),
    ([0xCA, 0xFE, 0xBA, 0xBE], 'исполняемый файл macOS'),
    ([0x50, 0x4B, 0x03, 0x04], 'архив или пакет приложения'),
    ([0x64, 0x65, 0x78, 0x0A], 'исполняемый файл Android'),
    ([0x23, 0x21], 'сценарий командной оболочки'),
  ];

  /// Разбирает файл и возвращает метаданные.
  ///
  /// Бросает [AudioImportException] с текстом для пользователя, если файл
  /// повреждён, не является аудио или его формат не соответствует
  /// расширению.
  AudioMetadata inspect({required Uint8List bytes, required String fileName}) {
    if (bytes.length < _minBytes) {
      throw const AudioImportException('Файл повреждён: данных слишком мало.');
    }
    _rejectUnsafeContent(bytes);

    return switch (AudioImportRules.extensionOf(fileName)) {
      'wav' => _inspectWav(bytes),
      'flac' => _inspectFlac(bytes),
      'mp3' => _inspectMp3(bytes),
      'aac' => _inspectAac(bytes),
      _ => throw const AudioImportException('Неподдерживаемый формат файла.'),
    };
  }

  /// Отсекает файлы, замаскированные под музыку.
  void _rejectUnsafeContent(Uint8List bytes) {
    for (final (signature, kind) in _unsafeSignatures) {
      if (_matches(bytes, 0, signature)) {
        throw AudioImportException(
          'Файл похож на $kind и не может быть добавлен в библиотеку.',
        );
      }
    }
  }

  // --- WAV -------------------------------------------------------------------

  /// Разбирает RIFF/WAVE-контейнер.
  AudioMetadata _inspectWav(Uint8List bytes) {
    if (!_matchesAscii(bytes, 0, 'RIFF') || !_matchesAscii(bytes, 8, 'WAVE')) {
      throw const AudioImportException('Файл не является WAV-контейнером.');
    }

    var offset = 12;
    var format = 0;
    var channels = 0;
    var sampleRate = 0;
    var byteRate = 0;
    var bitsPerSample = 0;
    var dataOffset = -1;
    var dataSize = 0;

    while (offset + 8 <= bytes.length) {
      final size = _u32le(bytes, offset + 4);
      final body = offset + 8;

      if (_matchesAscii(bytes, offset, 'fmt ') && body + 16 <= bytes.length) {
        format = _u16le(bytes, body);
        channels = _u16le(bytes, body + 2);
        sampleRate = _u32le(bytes, body + 4);
        byteRate = _u32le(bytes, body + 8);
        bitsPerSample = _u16le(bytes, body + 14);
      } else if (_matchesAscii(bytes, offset, 'data')) {
        dataOffset = body;
        dataSize = size;
      }

      if (size <= 0) break; // Некорректный размер — дальше идти нет смысла.
      offset = body + size + (size.isOdd ? 1 : 0); // Чанки выравнены по 2 байта.
    }

    if (channels <= 0 || sampleRate <= 0 || byteRate <= 0) {
      throw const AudioImportException('Заголовок WAV повреждён.');
    }
    if (dataOffset < 0 || dataOffset >= bytes.length) {
      throw const AudioImportException('Файл не содержит звуковых данных.');
    }

    // Размер блока `data` может быть нулевым или завышенным — доверяем
    // фактическому объёму файла.
    final available = bytes.length - dataOffset;
    final effective = dataSize <= 0 || dataSize > available ? available : dataSize;
    if (effective <= 0) {
      throw const AudioImportException('Файл не содержит звуковых данных.');
    }

    return AudioMetadata(
      codec: _wavCodec(format, bitsPerSample),
      duration: Duration(
        microseconds: (effective * 1000000 / byteRate).round(),
      ),
      bitrateKbps: (byteRate * 8 / 1000).round(),
      sampleRate: sampleRate,
      channels: channels,
    );
  }

  String _wavCodec(int format, int bitsPerSample) {
    final name = switch (format) {
      1 => 'PCM',
      3 => 'Float',
      6 => 'A-law',
      7 => 'µ-law',
      0xFFFE => 'Extensible',
      _ => 'codec $format',
    };
    return bitsPerSample > 0 ? 'WAV / $name $bitsPerSample бит' : 'WAV / $name';
  }

  // --- FLAC ------------------------------------------------------------------

  /// Разбирает поток FLAC: длительность берётся из блока STREAMINFO.
  AudioMetadata _inspectFlac(Uint8List bytes) {
    if (!_matchesAscii(bytes, 0, 'fLaC')) {
      throw const AudioImportException('Файл не является FLAC-потоком.');
    }
    if (bytes.length < 42 || (bytes[4] & 0x7F) != 0) {
      throw const AudioImportException('Заголовок FLAC повреждён.');
    }

    const body = 8; // 4 байта сигнатуры + 4 байта заголовка блока.
    final sampleRate = (bytes[body + 10] << 12) |
        (bytes[body + 11] << 4) |
        (bytes[body + 12] >> 4);
    final channels = ((bytes[body + 12] >> 1) & 0x07) + 1;
    final bitsPerSample = (((bytes[body + 12] & 0x01) << 4) |
            (bytes[body + 13] >> 4)) +
        1;
    final totalSamples = ((bytes[body + 13] & 0x0F) << 32) |
        (bytes[body + 14] << 24) |
        (bytes[body + 15] << 16) |
        (bytes[body + 16] << 8) |
        bytes[body + 17];

    if (sampleRate <= 0 || totalSamples <= 0) {
      throw const AudioImportException('FLAC-поток не содержит звуковых данных.');
    }

    final seconds = totalSamples / sampleRate;
    return AudioMetadata(
      codec: 'FLAC / $bitsPerSample бит',
      duration: Duration(microseconds: (seconds * 1000000).round()),
      bitrateKbps: (bytes.length * 8 / seconds / 1000).round(),
      sampleRate: sampleRate,
      channels: channels,
    );
  }

  // --- MP3 -------------------------------------------------------------------

  /// Битрейты Layer III для MPEG-1, кбит/с (индекс 0 и 15 недопустимы).
  static const List<int> _mpeg1Bitrates = [
    0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0,
  ];

  /// Битрейты Layer III для MPEG-2 и MPEG-2.5, кбит/с.
  static const List<int> _mpeg2Bitrates = [
    0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0,
  ];

  static const List<int> _mpeg1Rates = [44100, 48000, 32000];
  static const List<int> _mpeg2Rates = [22050, 24000, 16000];
  static const List<int> _mpeg25Rates = [11025, 12000, 8000];

  /// Разбирает поток MPEG-1/2/2.5 Layer III.
  AudioMetadata _inspectMp3(Uint8List bytes) {
    final start = _mp3FrameStart(bytes);
    if (start < 0) {
      throw const AudioImportException('В файле не найден поток MPEG-аудио.');
    }

    final header = _mp3Header(bytes, start)!;

    // Заголовок Xing/Info хранит точное число кадров — так определяется
    // длительность VBR-файлов; иначе считаем по битрейту первого кадра.
    final xing = start + 4 + header.sideInfo;
    var frames = 0;
    if (_matchesAscii(bytes, xing, 'Xing') || _matchesAscii(bytes, xing, 'Info')) {
      if ((_u32be(bytes, xing + 4) & 0x01) != 0) {
        frames = _u32be(bytes, xing + 8);
      }
    }

    final seconds = frames > 0
        ? frames * header.samplesPerFrame / header.sampleRate
        : (bytes.length - start) * 8 / (header.bitrate * 1000);

    if (seconds <= 0.05) {
      throw const AudioImportException('Поток MP3 пуст или повреждён.');
    }

    return AudioMetadata(
      codec: 'MP3',
      duration: Duration(microseconds: (seconds * 1000000).round()),
      bitrateKbps: header.bitrate,
      sampleRate: header.sampleRate,
      channels: header.channels,
    );
  }

  /// Ищет первый корректный кадр, пропуская тег ID3v2.
  int _mp3FrameStart(Uint8List bytes) {
    var offset = 0;
    if (_matchesAscii(bytes, 0, 'ID3') && bytes.length > 10) {
      // Размер ID3v2 хранится в «синхро-безопасном» виде: по 7 бит на байт.
      final size = ((bytes[6] & 0x7F) << 21) |
          ((bytes[7] & 0x7F) << 14) |
          ((bytes[8] & 0x7F) << 7) |
          (bytes[9] & 0x7F);
      final hasFooter = (bytes[5] & 0x10) != 0;
      offset = 10 + size + (hasFooter ? 10 : 0);
    }

    for (var index = offset; index + 4 <= bytes.length; index++) {
      if (_mp3Header(bytes, index) != null) return index;
    }
    return -1;
  }

  /// Разбирает заголовок кадра; `null` — байты не являются заголовком.
  ({
    int bitrate,
    int sampleRate,
    int channels,
    int samplesPerFrame,
    int sideInfo,
  })? _mp3Header(Uint8List bytes, int offset) {
    if (offset + 4 > bytes.length) return null;
    if (bytes[offset] != 0xFF || (bytes[offset + 1] & 0xE0) != 0xE0) return null;

    final version = (bytes[offset + 1] >> 3) & 0x03; // 3 — MPEG-1, 2 — MPEG-2.
    final layer = (bytes[offset + 1] >> 1) & 0x03; // 1 — Layer III.
    final bitrateIndex = (bytes[offset + 2] >> 4) & 0x0F;
    final rateIndex = (bytes[offset + 2] >> 2) & 0x03;
    final mono = ((bytes[offset + 3] >> 6) & 0x03) == 3;

    if (version == 1 || layer != 1 || rateIndex == 3) return null;
    if (bitrateIndex == 0 || bitrateIndex == 15) return null;

    final isMpeg1 = version == 3;
    final bitrate = (isMpeg1 ? _mpeg1Bitrates : _mpeg2Bitrates)[bitrateIndex];
    final rates = switch (version) {
      3 => _mpeg1Rates,
      2 => _mpeg2Rates,
      _ => _mpeg25Rates,
    };

    return (
      bitrate: bitrate,
      sampleRate: rates[rateIndex],
      channels: mono ? 1 : 2,
      samplesPerFrame: isMpeg1 ? 1152 : 576,
      sideInfo: isMpeg1 ? (mono ? 17 : 32) : (mono ? 9 : 17),
    );
  }

  // --- AAC (ADTS) ------------------------------------------------------------

  static const List<int> _aacRates = [
    96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050,
    16000, 12000, 11025, 8000, 7350,
  ];

  /// Разбирает AAC-поток в контейнере ADTS.
  ///
  /// Каждый кадр независим, поэтому длительность считается как число кадров
  /// на 1024 сэмпла — это точное значение, а не оценка.
  AudioMetadata _inspectAac(Uint8List bytes) {
    if (_matchesAscii(bytes, 0, 'ADIF')) {
      throw const AudioImportException(
        'Поддерживается только AAC-поток ADTS, а не ADIF.',
      );
    }

    var offset = 0;
    var frames = 0;
    var sampleRate = 0;
    var channels = 0;
    var profile = 1;

    while (offset + 7 <= bytes.length) {
      // Sync-слово ADTS: 0xFFF и нулевой слой.
      if (bytes[offset] != 0xFF || (bytes[offset + 1] & 0xF6) != 0xF0) {
        throw const AudioImportException(
          'Поток AAC повреждён: нарушена структура кадров.',
        );
      }

      final rateIndex = (bytes[offset + 2] >> 2) & 0x0F;
      final frameLength = ((bytes[offset + 3] & 0x03) << 11) |
          (bytes[offset + 4] << 3) |
          ((bytes[offset + 5] >> 5) & 0x07);

      if (rateIndex >= _aacRates.length || frameLength < 7) {
        throw const AudioImportException('Заголовок кадра AAC повреждён.');
      }

      if (frames == 0) {
        sampleRate = _aacRates[rateIndex];
        profile = (bytes[offset + 2] >> 6) & 0x03;
        final config =
            ((bytes[offset + 2] & 0x01) << 2) | ((bytes[offset + 3] >> 6) & 0x03);
        // 0 означает, что раскладка задана вне ADTS — показываем стерео.
        channels = config == 0 ? 2 : config;
      }

      frames++;
      offset += frameLength;
    }

    if (frames == 0 || sampleRate <= 0) {
      throw const AudioImportException('Файл не содержит звуковых данных.');
    }

    final seconds = frames * 1024 / sampleRate;
    return AudioMetadata(
      codec: switch (profile) {
        0 => 'AAC Main',
        2 => 'AAC SSR',
        3 => 'AAC LTP',
        _ => 'AAC LC',
      },
      duration: Duration(microseconds: (seconds * 1000000).round()),
      bitrateKbps: (bytes.length * 8 / seconds / 1000).round(),
      sampleRate: sampleRate,
      channels: channels,
    );
  }

  // --- Вспомогательные методы ------------------------------------------------

  bool _matchesAscii(Uint8List bytes, int offset, String value) {
    if (offset + value.length > bytes.length) return false;
    for (var index = 0; index < value.length; index++) {
      if (bytes[offset + index] != value.codeUnitAt(index)) return false;
    }
    return true;
  }

  bool _matches(Uint8List bytes, int offset, List<int> signature) {
    if (offset + signature.length > bytes.length) return false;
    for (var index = 0; index < signature.length; index++) {
      if (bytes[offset + index] != signature[index]) return false;
    }
    return true;
  }

  int _u16le(Uint8List bytes, int offset) =>
      bytes[offset] | (bytes[offset + 1] << 8);

  int _u32le(Uint8List bytes, int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);

  int _u32be(Uint8List bytes, int offset) {
    if (offset + 4 > bytes.length) return 0;
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }
}
