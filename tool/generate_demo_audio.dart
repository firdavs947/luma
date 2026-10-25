// Генератор демо-фрагмента, который играет, когда Spotify не отдаёт превью.
//
// Запуск: dart run tool/generate_demo_audio.dart
// Результат: assets/audio/luma_demo.wav (16 бит, моно, 22050 Гц)
//
// Ассет детерминированный: его можно пересобрать в любой момент, поэтому он
// не «магический бинарник», а воспроизводимый ресурс проекта.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const _sampleRate = 22050;
const _barSeconds = 2.0;
const _barCount = 15;

/// Аккордовая последовательность: Am7 → Fmaj7 → Cmaj7 → G7.
const _chords = <List<double>>[
  [220.00, 261.63, 329.63, 392.00], // A3 C4 E4 G4
  [174.61, 220.00, 261.63, 329.63], // F3 A3 C4 E4
  [261.63, 329.63, 392.00, 493.88], // C4 E4 G4 B4
  [196.00, 246.94, 293.66, 349.23], // G3 B3 D4 F4
];

void main() {
  final total = (_sampleRate * _barSeconds * _barCount).round();
  final samples = Float64List(total);

  for (var bar = 0; bar < _barCount; bar++) {
    final chord = _chords[bar % _chords.length];
    final start = (bar * _barSeconds * _sampleRate).round();
    final length = (_barSeconds * _sampleRate).round();

    for (var i = 0; i < length; i++) {
      final t = i / _sampleRate;
      final index = start + i;
      if (index >= total) break;

      var value = 0.0;

      // Мягкая «подушка» аккорда с медленной атакой.
      final padEnvelope =
          math.min(1.0, t / 0.35) * math.exp(-0.35 * math.max(0, t - 0.35));
      for (final frequency in chord) {
        value += _voice(frequency, t) * 0.09 * padEnvelope;
      }

      // Бас — тоника на октаву ниже.
      value += _voice(chord.first / 2, t) * 0.22 * math.exp(-1.1 * t);

      // Арпеджио: короткие «капли» по нотам аккорда четыре раза в секунду.
      final step = (t / 0.5).floor();
      final stepTime = t - step * 0.5;
      if (step < 4) {
        final note = chord[(step + bar) % chord.length] * 2;
        value += _voice(note, stepTime) * 0.16 * math.exp(-6.5 * stepTime);
      }

      samples[index] += value;
    }
  }

  final file = File('assets/audio/luma_demo.wav');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(_wav(samples));

  stdout.writeln(
    'Готово: ${file.path} (${(file.lengthSync() / 1024).round()} КБ, '
    '${total / _sampleRate} с)',
  );
}

/// Одна «нота»: основной тон плюс два обертона.
double _voice(double frequency, double t) {
  return math.sin(2 * math.pi * frequency * t) +
      0.35 * math.sin(2 * math.pi * frequency * 2 * t) +
      0.12 * math.sin(2 * math.pi * frequency * 3 * t);
}

/// Собирает WAV-контейнер с 16-битным PCM.
Uint8List _wav(Float64List samples) {
  final dataBytes = samples.length * 2;
  final bytes = BytesBuilder();

  void ascii(String value) => bytes.add(value.codeUnits);
  void u32(int value) =>
      bytes.add(Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little));
  void u16(int value) =>
      bytes.add(Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little));

  ascii('RIFF');
  u32(36 + dataBytes);
  ascii('WAVE');
  ascii('fmt ');
  u32(16); // размер блока fmt
  u16(1); // PCM без сжатия
  u16(1); // моно
  u32(_sampleRate);
  u32(_sampleRate * 2); // байт в секунду
  u16(2); // выравнивание блока
  u16(16); // бит на сэмпл
  ascii('data');
  u32(dataBytes);

  final pcm = Int16List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    pcm[i] = (samples[i].clamp(-1.0, 1.0) * 32767).round();
  }
  bytes.add(pcm.buffer.asUint8List());

  return bytes.toBytes();
}
