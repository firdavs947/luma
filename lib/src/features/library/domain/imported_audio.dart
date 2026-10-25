import 'package:flutter/foundation.dart';

import '../../catalog/domain/media_item.dart';
import 'audio_metadata.dart';

/// Трек, импортированный пользователем из файла и сохранённый на устройстве.
///
/// Модель описывает запись библиотеки целиком: ссылки на аудиофайл и
/// обложку в приватном каталоге приложения, технические метаданные и дату
/// добавления. Именно она сериализуется в хранилище и превращается в
/// [MediaItem] для лент и плеера.
@immutable
class ImportedAudio {
  const ImportedAudio({
    required this.id,
    required this.title,
    required this.artist,
    required this.audioLocation,
    required this.metadata,
    required this.sizeBytes,
    required this.addedAt,
    this.previewLocation,
    this.coverLocation,
  });

  /// Идентификатор записи; префикс `local-` отделяет её от контента Genius.
  final String id;
  final String title;

  /// Исполнитель; пустая строка, если пользователь его не указал.
  final String artist;

  /// `file://`-ссылка на аудиофайл в приватном каталоге приложения.
  final String audioLocation;

  /// `file://`-ссылка на короткий фрагмент для быстрого прослушивания.
  ///
  /// `null`, если из контейнера нельзя безопасно вырезать участок — тогда
  /// в интерфейсе предлагается только полное воспроизведение.
  final String? previewLocation;

  /// `file://`-ссылка на обложку, если пользователь её выбрал.
  final String? coverLocation;

  /// Есть ли готовый фрагмент для быстрого прослушивания.
  bool get hasPreview => previewLocation != null;

  /// Длительность, битрейт, кодек и параметры потока.
  final AudioMetadata metadata;

  /// Размер исходного аудиофайла в байтах.
  final int sizeBytes;

  /// Когда трек появился в библиотеке.
  final DateTime addedAt;

  /// Представление трека в каталоге.
  ///
  /// Плеер воспроизводит `previewUrl` напрямую с диска, поэтому звучит
  /// именно тот файл, который загрузил пользователь, а не демо-фрагмент.
  MediaItem toMediaItem() {
    return MediaItem(
      id: id,
      title: title,
      subtitle: artist.isEmpty ? 'Импортированный файл' : artist,
      category: MediaCategory.music,
      year: addedAt.year,
      durationLabel: metadata.durationLabel,
      rating: 0,
      description: 'Импортированный аудиофайл LUMA. ${metadata.summary}. '
          'Хранится на устройстве и доступен без интернета.',
      previewUrl: audioLocation,
      imageUrl: coverLocation,
      isTrack: true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'audio': audioLocation,
        if (previewLocation != null) 'preview': previewLocation,
        if (coverLocation != null) 'cover': coverLocation,
        'metadata': metadata.toJson(),
        'sizeBytes': sizeBytes,
        'addedAt': addedAt.toIso8601String(),
      };

  factory ImportedAudio.fromJson(Map<String, dynamic> json) => ImportedAudio(
        id: json['id'] as String,
        title: json['title'] as String,
        artist: (json['artist'] as String?) ?? '',
        audioLocation: json['audio'] as String,
        previewLocation: json['preview'] as String?,
        coverLocation: json['cover'] as String?,
        metadata: AudioMetadata.fromJson(
          json['metadata'] as Map<String, dynamic>,
        ),
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        addedAt: DateTime.parse(json['addedAt'] as String),
      );
}
