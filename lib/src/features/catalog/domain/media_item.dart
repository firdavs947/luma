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

/// Откуда пришла видеозапись.
///
/// От источника зависит способ воспроизведения: Cinemeta и AniList отдают
/// метаданные и официальный трейлер, Internet Archive — полный фильм,
/// который можно посмотреть целиком и бесплатно.
enum MediaOrigin {
  unknown,
  cinemeta,
  anilist,
  archive;

  /// Запись из метаданных: в приложении доступен официальный трейлер.
  bool get isTrailerOnly => this == cinemeta || this == anilist;

  /// Полнометражная запись общественного достояния.
  bool get isFreeFull => this == archive;
}

/// Единица контента медиатеки.
///
/// Модель неизменяемая, что упрощает сравнение состояний в BLoC.
/// Видео наполняется бесплатными источниками (Cinemeta, AniList и Internet
/// Archive), музыка — источником музыки (Audius → Genius → локальный фолбэк),
/// поэтому у элемента есть необязательные поля сетевой обложки, фона,
/// логотипа и превью-звука.
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
    this.backdropUrl,
    this.logoUrl,
    this.trailerId,
    this.origin = MediaOrigin.unknown,
    this.score = 0,
    this.genres = const [],
    this.cast = const [],
    this.directors = const [],
    this.country,
    this.releaseDate,
    this.previewUrl,
    this.albumId,
    this.playlistId,
    this.isTrack = false,
    this.externalId,
    this.imdbId,
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

  /// Широкий кадр 16:9 для hero-баннера и экрана описания.
  final String? backdropUrl;

  /// Прозрачный логотип фильма или сериала для премиального заголовка.
  final String? logoUrl;

  /// Идентификатор официального трейлера на YouTube.
  ///
  /// По нему встроенный плеер открывает ролик прямо в приложении, а кнопка
  /// «Открыть на YouTube» — на сайте.
  final String? trailerId;

  /// Источник записи: он определяет, что именно играет плеер.
  final MediaOrigin origin;

  /// Оценка по десятибалльной шкале (IMDb/AniList); `0` — неизвестна.
  ///
  /// Хранится отдельно от [rating], потому что музыкальные источники
  /// исторически отдают пятибалльную оценку. Для видео интерфейс показывает
  /// именно [score], как в IMDb.
  final double score;

  /// Жанры записи на языке источника.
  final List<String> genres;

  /// Актёрский состав (до пяти имён).
  final List<String> cast;

  /// Режиссёры.
  final List<String> directors;

  /// Страна производства.
  final String? country;

  /// Дата выхода в формате ISO 8601 (`YYYY-MM-DD`).
  final String? releaseDate;

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

  /// Идентификатор фильма или сериала на IMDb (`tt…`).
  ///
  /// По нему строятся постеры Metahub и сопоставляются карточки разных
  /// источников, поэтому он не зависит от [externalId].
  final String? imdbId;

  /// Числовая популярность из источника (число просмотров/загрузок).
  ///
  /// Нужна для сортировки «По популярности» и для отбора лучшего
  /// результата при поиске. `0` — источник не сообщил значение.
  final int popularity;

  /// Детерминированный «сид» для генерации обложки.
  int get seed => id.codeUnits.fold<int>(0, (sum, unit) => sum + unit * 31);

  bool get isVideo => category != MediaCategory.music;

  /// Полный фильм из Internet Archive: доступен целиком и бесплатно.
  bool get isFreeFull => origin.isFreeFull;

  /// У записи есть официальный трейлер для встроенного плеера.
  bool get hasTrailer => trailerId != null && trailerId!.isNotEmpty;

  /// Есть ли звук, который можно реально воспроизвести.
  bool get hasPreview => previewUrl != null && previewUrl!.isNotEmpty;

  /// Известен ли рейтинг.
  bool get hasRating => rating > 0;

  /// Оценка для интерфейса: для видео — IMDb/AniList, для музыки — 5-балльная.
  double get displayScore => score > 0 ? score : rating * 2;

  /// Известна ли оценка по десятибалльной шкале.
  bool get hasScore => displayScore > 0;

  /// Подпись оценки с одним знаком после запятой.
  String get scoreLabel => displayScore.toStringAsFixed(1);

  /// Короткая строка для карточки: год и первый жанр.
  String get shortMeta {
    final genre = genres.isNotEmpty ? genres.first : category.label;
    return year > 0 ? '$year · $genre' : genre;
  }

  /// Год выхода числом с учётом диапазона сериалов («2026–»).
  int get releaseYear {
    if (year > 0) return year;
    final match = RegExp(r'(\d{4})').firstMatch(releaseDate ?? '');
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  /// Можно ли открыть треклист альбома.
  bool get hasAlbum => albumId != null && albumId!.isNotEmpty;

  /// Можно ли открыть треклист плейлиста.
  bool get hasPlaylist => playlistId != null && playlistId!.isNotEmpty;

  /// Открывается ли элемент треклистом подборки, а не сразу плеером.
  bool get opensCollection => !isTrack && (hasAlbum || hasPlaylist);

  MediaItem copyWith({
    bool? isFavorite,
    double? progress,
    String? description,
    String? imageUrl,
    String? backdropUrl,
    String? logoUrl,
    String? trailerId,
    MediaOrigin? origin,
    double? score,
    List<String>? genres,
    List<String>? cast,
    List<String>? directors,
    String? country,
    String? releaseDate,
    String? durationLabel,
  }) {
    return MediaItem(
      id: id,
      title: title,
      subtitle: subtitle,
      category: category,
      year: year,
      durationLabel: durationLabel ?? this.durationLabel,
      rating: rating,
      description: description ?? this.description,
      isFavorite: isFavorite ?? this.isFavorite,
      progress: progress ?? this.progress,
      imageUrl: imageUrl ?? this.imageUrl,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      logoUrl: logoUrl ?? this.logoUrl,
      trailerId: trailerId ?? this.trailerId,
      origin: origin ?? this.origin,
      score: score ?? this.score,
      genres: genres ?? this.genres,
      cast: cast ?? this.cast,
      directors: directors ?? this.directors,
      country: country ?? this.country,
      releaseDate: releaseDate ?? this.releaseDate,
      previewUrl: previewUrl,
      albumId: albumId,
      playlistId: playlistId,
      isTrack: isTrack,
      externalId: externalId,
      imdbId: imdbId,
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
