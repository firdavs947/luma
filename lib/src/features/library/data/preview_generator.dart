import 'dart:typed_data';

import '../domain/audio_import_rules.dart';

/// Готовит короткий фрагмент трека для быстрого прослушивания.
///
/// Превью собирается прямо в исходном контейнере: у WAV пересобирается
/// заголовок RIFF, у MP3 и AAC отбирается нужное число целых кадров. Звук
/// не декодируется и не перекодируется, поэтому подготовка занимает
/// миллисекунды даже для файла в десятки мегабайт, а качество фрагмента
/// совпадает с качеством оригинала.
///
/// Для FLAC-потока фрагмент не собирается: кадры опираются на сквозные
/// контрольные суммы, и вырезание произвольного участка сделало бы файл
/// нечитаемым. В этом случае плеер воспроизводит исходный файл целиком.
abstract final class PreviewGenerator {
  /// Длина превью — 30 секунд, как у стриминговых сервисов.
  static const Duration length = Duration(seconds: 30);

  /// Собирает превью или возвращает `null`, если формат не позволяет
  /// безопасно вырезать фрагмент.
  static Uint8List? build({
    required Uint8List bytes,
    required String fileName,
  }) {
    if (bytes.length < 16) return null;

    return switch (AudioImportRules.extensionOf(fileName)) {
      'wav' => _wav(bytes),
      'mp3' => _mp3(bytes),
      'aac' => _aac(bytes),
      _ => null,
    };
  }

  // --- WAV -------------------------------------------------------------------

  /// Пересобирает RIFF/WAVE: блок `fmt ` копируется целиком, из `data`
  /// берётся столько байт, сколько звучит за [length].
  static Uint8List? _wav(Uint8List bytes) {
    if (!_ascii(bytes, 0, 'RIFF') || !_ascii(bytes, 8, 'WAVE')) return null;

    var offset = 12;
    var formatStart = -1;
    var formatLength = 0;
    var byteRate = 0;
    var dataStart = -1;
    var dataSize = 0;

    while (offset + 8 <= bytes.length) {
      final size = _u32le(bytes, offset + 4);
      final body = offset + 8;

      if (formatStart < 0 && _ascii(bytes, offset, 'fmt ')) {
        formatStart = offset;
        formatLength = 8 + size;
        if (body + 12 <= bytes.length) byteRate = _u32le(bytes, body + 8);
      } else if (dataStart < 0 && _ascii(bytes, offset, 'data')) {
        dataStart = body;
        dataSize = size;
      }

      if (size <= 0) break;
      offset = body + size + (size.isOdd ? 1 : 0); // Чанки выравнены по 2 байта.
    }

    if (formatStart < 0 || byteRate <= 0 || dataStart < 0) return null;
    if (formatStart + formatLength > bytes.length) return null;

    final available = bytes.length - dataStart;
    final total = dataSize <= 0 || dataSize > available ? available : dataSize;
    final wanted = byteRate * length.inSeconds;
    final take = total < wanted ? total : wanted;
    if (take <= 0) return null;

    final padded = take.isOdd ? take + 1 : take;
    final dataHeader = 12 + formatLength;
    final output = Uint8List(dataHeader + 8 + padded);
    final view = ByteData.view(output.buffer);

    _writeAscii(output, 0, 'RIFF');
    view.setUint32(4, output.length - 8, Endian.little);
    _writeAscii(output, 8, 'WAVE');

    output.setRange(12, dataHeader, bytes, formatStart);
    _writeAscii(output, dataHeader, 'data');
    view.setUint32(dataHeader + 4, take, Endian.little);
    output.setRange(dataHeader + 8, dataHeader + 8 + take, bytes, dataStart);

    return output;
  }

  // --- MP3 -------------------------------------------------------------------

  /// Битрейты Layer III для MPEG-1, кбит/с (индексы 0 и 15 недопустимы).
  static const List<int> _mpeg1Bitrates = [
    0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0,
  ];

  /// Битрейты Layer III для MPEG-2 и MPEG-2.5, кбит/с.
  static const List<int> _mpeg2Bitrates = [
    0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0,
  ];

  static const List<int> _rates1 = [44100, 48000, 32000];
  static const List<int> _rates2 = [22050, 24000, 16000];
  static const List<int> _rates25 = [11025, 12000, 8000];

  /// Отбирает целые кадры MPEG-аудио от первого кадра до [length].
  ///
  /// Кадр Layer III самодостаточен, поэтому последовательность кадров
  /// остаётся валидным MP3 — без заголовков ID3, которые здесь не нужны.
  static Uint8List? _mp3(Uint8List bytes) {
    final start = _mp3FrameStart(bytes);
    if (start < 0) return null;

    var offset = start;
    var seconds = 0.0;

    while (offset + 4 <= bytes.length && seconds < length.inSeconds) {
      final frame = _mp3Frame(bytes, offset);
      if (frame == null || offset + frame.length > bytes.length) break;
      seconds += frame.samplesPerFrame / frame.sampleRate;
      offset += frame.length;
    }

    if (offset <= start) return null;
    return bytes.sublist(start, offset);
  }

  /// Ищет первый кадр, пропуская тег ID3v2.
  static int _mp3FrameStart(Uint8List bytes) {
    var offset = 0;
    if (_ascii(bytes, 0, 'ID3') && bytes.length > 10) {
      // Размер ID3v2 хранится по 7 бит на байт.
      final size = ((bytes[6] & 0x7F) << 21) |
          ((bytes[7] & 0x7F) << 14) |
          ((bytes[8] & 0x7F) << 7) |
          (bytes[9] & 0x7F);
      offset = 10 + size + ((bytes[5] & 0x10) != 0 ? 10 : 0);
    }

    for (var index = offset; index + 4 <= bytes.length; index++) {
      if (_mp3Frame(bytes, index) != null) return index;
    }
    return -1;
  }

  /// Размер и параметры кадра; `null` — байты не являются заголовком.
  static ({int length, int samplesPerFrame, int sampleRate})? _mp3Frame(
    Uint8List bytes,
    int offset,
  ) {
    if (offset + 4 > bytes.length) return null;
    if (bytes[offset] != 0xFF || (bytes[offset + 1] & 0xE0) != 0xE0) return null;

    final version = (bytes[offset + 1] >> 3) & 0x03; // 3 — MPEG-1, 2 — MPEG-2.
    final layer = (bytes[offset + 1] >> 1) & 0x03; // 1 — Layer III.
    final bitrateIndex = (bytes[offset + 2] >> 4) & 0x0F;
    final rateIndex = (bytes[offset + 2] >> 2) & 0x03;
    final padding = (bytes[offset + 2] >> 1) & 0x01;

    if (version == 1 || layer != 1 || rateIndex == 3) return null;
    if (bitrateIndex == 0 || bitrateIndex == 15) return null;

    final isMpeg1 = version == 3;
    final bitrate =
        (isMpeg1 ? _mpeg1Bitrates : _mpeg2Bitrates)[bitrateIndex] * 1000;
    final sampleRate = switch (version) {
      3 => _rates1,
      2 => _rates2,
      _ => _rates25,
    }[rateIndex];

    final samplesPerFrame = isMpeg1 ? 1152 : 576;
    final length = (isMpeg1 ? 144 : 72) * bitrate ~/ sampleRate + padding;
    if (length < 4) return null;

    return (
      length: length,
      samplesPerFrame: samplesPerFrame,
      sampleRate: sampleRate,
    );
  }

  // --- AAC (ADTS) ------------------------------------------------------------

  static const List<int> _aacRates = [
    96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050,
    16000, 12000, 11025, 8000, 7350,
  ];

  /// Отбирает целые кадры ADTS от начала потока до [length].
  static Uint8List? _aac(Uint8List bytes) {
    if (bytes.length < 7) return null;
    if (bytes[0] != 0xFF || (bytes[1] & 0xF6) != 0xF0) return null;

    var offset = 0;
    var seconds = 0.0;

    while (offset + 7 <= bytes.length && seconds < length.inSeconds) {
      // Sync-слово ADTS: 0xFFF и нулевой слой.
      if (bytes[offset] != 0xFF || (bytes[offset + 1] & 0xF6) != 0xF0) break;

      final rateIndex = (bytes[offset + 2] >> 2) & 0x0F;
      if (rateIndex >= _aacRates.length) break;

      final frameLength = ((bytes[offset + 3] & 0x03) << 11) |
          (bytes[offset + 4] << 3) |
          ((bytes[offset + 5] >> 5) & 0x07);
      if (frameLength < 7 || offset + frameLength > bytes.length) break;

      seconds += 1024 / _aacRates[rateIndex];
      offset += frameLength;
    }

    if (offset <= 0) return null;
    return bytes.sublist(0, offset);
  }

  // --- Вспомогательные методы ------------------------------------------------

  static bool _ascii(Uint8List bytes, int offset, String value) {
    if (offset + value.length > bytes.length) return false;
    for (var index = 0; index < value.length; index++) {
      if (bytes[offset + index] != value.codeUnitAt(index)) return false;
    }
    return true;
  }

  static void _writeAscii(Uint8List bytes, int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      bytes[offset + index] = value.codeUnitAt(index);
    }
  }

  static int _u32le(Uint8List bytes, int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}
