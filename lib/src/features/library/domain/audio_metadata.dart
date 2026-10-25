import 'package:flutter/foundation.dart';

/// Метаданные аудиофайла, полученные разбором контейнера.
///
/// Хранятся вместе с треком: по ним в интерфейсе видно, что именно за файл
/// загрузил пользователь — длительность, битрейт, кодек и частоту.
@immutable
class AudioMetadata {
  const AudioMetadata({
    required this.codec,
    required this.duration,
    required this.bitrateKbps,
    required this.sampleRate,
    required this.channels,
  });

  /// Кодек и контейнер в понятном виде: `MP3`, `WAV / PCM 16 бит`…
  final String codec;

  /// Длительность записи.
  final Duration duration;

  /// Битрейт в кбит/с.
  final int bitrateKbps;

  /// Частота дискретизации в герцах.
  final int sampleRate;

  /// Число каналов: 1 — моно, 2 — стерео.
  final int channels;

  /// Длительность в формате плеера: `3:42` или `1:04:20`.
  String get durationLabel {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '${duration.inMinutes}:$seconds';
  }

  /// Раскладка каналов словами.
  String get channelLabel => switch (channels) {
        1 => 'моно',
        2 => 'стерео',
        _ => '$channels канала',
      };

  /// Короткая сводка: `MP3 · 320 kbps · 44,1 кГц · стерео`.
  String get summary {
    final kilohertz = (sampleRate / 1000)
        .toStringAsFixed(1)
        .replaceAll('.', ',')
        .replaceAll(',0', '');
    return '$codec · $bitrateKbps kbps · $kilohertz кГц · $channelLabel';
  }

  Map<String, dynamic> toJson() => {
        'codec': codec,
        'durationMs': duration.inMilliseconds,
        'bitrateKbps': bitrateKbps,
        'sampleRate': sampleRate,
        'channels': channels,
      };

  factory AudioMetadata.fromJson(Map<String, dynamic> json) => AudioMetadata(
        codec: json['codec'] as String,
        duration: Duration(milliseconds: json['durationMs'] as int),
        bitrateKbps: json['bitrateKbps'] as int,
        sampleRate: json['sampleRate'] as int,
        channels: json['channels'] as int,
      );

  @override
  bool operator ==(Object other) =>
      other is AudioMetadata &&
      other.codec == codec &&
      other.duration == duration &&
      other.bitrateKbps == bitrateKbps &&
      other.sampleRate == sampleRate &&
      other.channels == channels;

  @override
  int get hashCode =>
      Object.hash(codec, duration, bitrateKbps, sampleRate, channels);
}
