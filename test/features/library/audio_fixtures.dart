/// Синтетические аудиофайлы для тестов разбора и генерации превью.
///
/// Файлы собираются «руками» из заголовков: тесты не зависят от внешних
/// ресурсов и проверяют ровно те поля, которые читает приложение.
library;

import 'dart:typed_data';

/// Собирает WAV-файл (PCM) заданной длительности.
///
/// Байты звука — тишина: для проверки заголовков содержимое не важно, а
/// размер файла рассчитывается из частоты и разрядности.
Uint8List buildWav({
  int seconds = 60,
  int sampleRate = 8000,
  int channels = 1,
  int bitsPerSample = 16,
}) {
  final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
  final dataSize = byteRate * seconds;
  const dataHeader = 12 + 8 + 16; // RIFF-заголовок и блок fmt.
  final bytes = Uint8List(dataHeader + 8 + dataSize);
  final view = ByteData.view(bytes.buffer);

  writeAscii(bytes, 0, 'RIFF');
  view.setUint32(4, bytes.length - 8, Endian.little);
  writeAscii(bytes, 8, 'WAVE');
  writeAscii(bytes, 12, 'fmt ');
  view.setUint32(16, 16, Endian.little);
  view.setUint16(20, 1, Endian.little); // Формат PCM.
  view.setUint16(22, channels, Endian.little);
  view.setUint32(24, sampleRate, Endian.little);
  view.setUint32(28, byteRate, Endian.little);
  view.setUint16(32, channels * (bitsPerSample ~/ 8), Endian.little);
  view.setUint16(34, bitsPerSample, Endian.little);
  writeAscii(bytes, 36, 'data');
  view.setUint32(40, dataSize, Endian.little);

  return bytes;
}

/// Размер кадра MPEG-1 Layer III 128 кбит/с 44,1 кГц без паддинга.
const int mp3FrameLength = 417;

/// Собирает MP3-поток из одинаковых кадров.
Uint8List buildMp3({int frames = 1200}) {
  final bytes = Uint8List(frames * mp3FrameLength);

  for (var index = 0; index < frames; index++) {
    final offset = index * mp3FrameLength;
    bytes[offset] = 0xFF;
    bytes[offset + 1] = 0xFB; // MPEG-1, Layer III, без CRC.
    bytes[offset + 2] = 0x90; // 128 кбит/с, 44,1 кГц, без паддинга.
    bytes[offset + 3] = 0x00; // Стерео.
  }

  return bytes;
}

/// Собирает начало FLAC-потока с блоком STREAMINFO.
///
/// Данные STREAMINFO начинаются с восьмого байта (4 байта сигнатуры и
/// 4 байта заголовка блока), поэтому упакованные поля лежат с 18-го байта.
Uint8List buildFlac({int totalSamples = 1323000, int sampleRate = 44100}) {
  final bytes = Uint8List(42);

  writeAscii(bytes, 0, 'fLaC');
  bytes[4] = 0x80; // Последний блок метаданных, тип 0 — STREAMINFO.
  bytes[7] = 34; // Длина блока STREAMINFO.
  bytes[18] = (sampleRate >> 12) & 0xFF;
  bytes[19] = (sampleRate >> 4) & 0xFF;
  // Младшие 4 бита частоты, стерео (каналы − 1 = 1), 16 бит (старший бит).
  bytes[20] = ((sampleRate & 0x0F) << 4) | (1 << 1);
  bytes[21] = 0xF0 | ((totalSamples >> 32) & 0x0F);
  bytes[22] = (totalSamples >> 24) & 0xFF;
  bytes[23] = (totalSamples >> 16) & 0xFF;
  bytes[24] = (totalSamples >> 8) & 0xFF;
  bytes[25] = totalSamples & 0xFF;

  return bytes;
}

/// Длина одного ADTS-кадра в синтетическом AAC-потоке.
const int aacFrameLength = 100;

/// Собирает AAC-поток в контейнере ADTS.
Uint8List buildAac({int frames = 1400}) {
  final bytes = Uint8List(frames * aacFrameLength);

  for (var index = 0; index < frames; index++) {
    final offset = index * aacFrameLength;
    bytes[offset] = 0xFF;
    bytes[offset + 1] = 0xF1; // Sync-слово, без CRC.
    bytes[offset + 2] = 0x50; // AAC LC, 44,1 кГц, стерео.
    bytes[offset + 3] = 0x80 | ((aacFrameLength >> 11) & 0x03);
    bytes[offset + 4] = (aacFrameLength >> 3) & 0xFF;
    bytes[offset + 5] = ((aacFrameLength & 0x07) << 5) | 0x1F;
  }

  return bytes;
}

/// Записывает ASCII-строку в буфер, начиная с [offset].
void writeAscii(Uint8List bytes, int offset, String value) {
  for (var index = 0; index < value.length; index++) {
    bytes[offset + index] = value.codeUnitAt(index);
  }
}
