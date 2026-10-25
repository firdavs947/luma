import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Направления медиатеки LUMA.
enum MediaCategory {
  music('Музыка', Icons.graphic_eq_rounded, AppColors.music),
  movies('Фильмы', Icons.movie_creation_rounded, AppColors.movies),
  anime('Аниме', Icons.auto_awesome_rounded, AppColors.anime),
  series('Сериалы', Icons.video_library_rounded, AppColors.series),
  cartoons('Мультфильмы', Icons.child_care_rounded, AppColors.cartoons);

  const MediaCategory(this.label, this.icon, this.accent);

  /// Отображаемое название раздела.
  final String label;

  /// Иконка раздела.
  final IconData icon;

  /// Фирменный акцент раздела.
  final Color accent;
}

/// Единица контента медиатеки.
///
/// Модель неизменяемая, что упрощает сравнение состояний в BLoC.
/// Видео наполняется локальным каталогом, музыка — источником музыки
/// (Genius либо локальный фолбэк), поэтому у элемента есть необязательные
/// поля сетевой обложки и превью-звука.
@immutable
class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.year,
    required this.durationLabel,
    required this.rating,
    this.description = '',
    this.isFavorite = false,
    this.progress = 0,
    this.imageUrl,
    this.previewUrl,
    this.albumId,
    this.playlistId,
    this.isTrack = false,
    this.externalId,
    this.popularity = 0,
  });

  final String id;
  final String title;
  final String subtitle;
  final MediaCategory category;
  final int year;
  final String durationLabel;

  /// Рейтинг по пятибалльной шкале; `0` — рейтинг неизвестен.
  final double rating;
  final String description;
  final bool isFavorite;

  /// Прогресс просмотра или прослушивания (0..1).
  final double progress;

  /// Сетевая обложка (например, из Genius). Если `null`, [`Artwork`]
  /// рисует процедурную обложку.
  final String? imageUrl;

  /// Готовая ссылка на звук: файл локальной библиотеки или превью источника.
  ///
  /// Для треков Genius остаётся пустой — плеер подбирает запись у
  /// стримингового провайдера по названию и исполнителю.
  final String? previewUrl;

  /// Идентификатор альбома в источнике — нужен для перехода к треклисту.
  final String? albumId;

  /// Идентификатор плейлиста в источнике — тоже открывает треклист.
  final String? playlistId;

  /// Музыкальный трек, а не альбом.
  ///
  /// По этому признаку выбирается экран: трек можно воспроизвести сразу,
  /// альбом сначала открывается треклистом.
  final bool isTrack;

  /// Идентификатор записи во внешнем источнике (например, identifier
  /// в Internet Archive). По нему запрашиваются метаданные и видеопоток.
  final String? externalId;

  /// Числовая популярность из источника (число просмотров/загрузок).
  ///
  /// Нужна для сортировки «По популярности» и для отбора лучшего
  /// результата при поиске. `0` — источник не сообщил значение.
  final int popularity;

  /// Детерминированный «сид» для генерации обложки.
  int get seed => id.codeUnits.fold<int>(0, (sum, unit) => sum + unit * 31);

  bool get isVideo => category != MediaCategory.music;

  /// Есть ли звук, который можно реально воспроизвести.
  bool get hasPreview => previewUrl != null && previewUrl!.isNotEmpty;

  /// Известен ли рейтинг.
  bool get hasRating => rating > 0;

  /// Можно ли открыть треклист альбома.
  bool get hasAlbum => albumId != null && albumId!.isNotEmpty;

  /// Можно ли открыть треклист плейлиста.
  bool get hasPlaylist => playlistId != null && playlistId!.isNotEmpty;

  /// Открывается ли элемент треклистом подборки, а не сразу плеером.
  bool get opensCollection => !isTrack && (hasAlbum || hasPlaylist);

  MediaItem copyWith({
    bool? isFavorite,
    double? progress,
  }) {
    return MediaItem(
      id: id,
      title: title,
      subtitle: subtitle,
      category: category,
      year: year,
      durationLabel: durationLabel,
      rating: rating,
      description: description,
      isFavorite: isFavorite ?? this.isFavorite,
      progress: progress ?? this.progress,
      imageUrl: imageUrl,
      previewUrl: previewUrl,
      albumId: albumId,
      playlistId: playlistId,
      isTrack: isTrack,
      externalId: externalId,
      popularity: popularity,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MediaItem &&
      other.id == id &&
      other.isFavorite == isFavorite &&
      other.progress == progress;

  @override
  int get hashCode => Object.hash(id, isFavorite, progress);
}
