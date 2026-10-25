import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/artwork.dart';
import '../../../core/widgets/media_card.dart';
import '../../../core/widgets/motion.dart';
import '../../album/presentation/album_screen.dart';
import '../../catalog/domain/media_item.dart';
import '../../catalog/domain/video_source.dart';
import '../../catalog/presentation/bloc/catalog_cubit.dart';
import '../../catalog/presentation/bloc/catalog_state.dart';
import '../../player/presentation/player_screen.dart';

/// Экран описания контента.
///
/// Карточка дополняется данными источника (описание, актёры, режиссёр,
/// страна) уже после открытия, поэтому экран рисуется сразу, а не ждёт
/// сеть. Для новых релизов ниже показывается честное пояснение: в
/// приложении доступен официальный трейлер, полная версия — в кинотеатрах.
class DetailsScreen extends StatefulWidget {
  const DetailsScreen({super.key, required this.item, this.queue = const []});

  final MediaItem item;

  /// Подборка, из которой открыт элемент: результаты поиска или лента
  /// раздела. Становится очередью плеера; пустая — плеер соберёт её сам из
  /// каталога того же раздела.
  final List<MediaItem> queue;

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  /// Карточка с полным описанием и составом.
  MediaItem? _enriched;

  /// Бесплатная полная версия в Internet Archive, если она нашлась.
  MediaItem? _fullVersion;

  bool _expanded = false;
  bool _detailsLoading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDetails());
  }

  Future<void> _loadDetails() async {
    final source = context.read<VideoSource>();
    final base =
        context.read<CatalogCubit>().state.byId(widget.item.id) ??
        widget.item;

    if (mounted) setState(() => _detailsLoading = true);

    MediaItem enriched = base;
    MediaItem? full;
    try {
      enriched = await source
          .enrich(base)
          .timeout(const Duration(seconds: 18));
    } catch (_) {
      // Метаданные не пришли — карточка уже показывает всё, что известно.
    }

    try {
      full = base.isFreeFull
          ? enriched
          : await source
                .fullVersionOf(enriched)
                .timeout(const Duration(seconds: 12));
    } catch (_) {
      full = null;
    }

    if (!mounted) return;
    setState(() {
      _enriched = enriched;
      _fullVersion = full;
      _detailsLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CatalogCubit, CatalogState>(
      builder: (context, state) {
        final base = state.byId(widget.item.id) ?? widget.item;
        // Свежие избранное и прогресс берём из каталога, остальные поля —
        // из дополненной карточки.
        final item = _enriched == null
            ? base
            : _enriched!.copyWith(
                isFavorite: base.isFavorite,
                progress: base.progress,
              );
        final recommendations = _recommendationsFor(state, item);
        final heroTag = 'artwork-${item.id}';

        return Scaffold(
          backgroundColor: AppColors.ink,
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: 420.h,
                pinned: true,
                stretch: true,
                backgroundColor: AppColors.ink,
                leading: Padding(
                  padding: EdgeInsets.all(8.r),
                  child: _RoundIconButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.of(context).maybePop(),
                    tooltip: 'Назад',
                  ),
                ),
                actions: [
                  Padding(
                    padding: EdgeInsets.only(right: 8.w),
                    child: _RoundIconButton(
                      icon: item.isFavorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: item.isFavorite ? AppColors.music : Colors.white,
                      onTap: () =>
                          context.read<CatalogCubit>().toggleFavorite(item),
                      tooltip: 'В избранное',
                    ),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  stretchModes: const [StretchMode.zoomBackground],
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Hero(
                        tag: heroTag,
                        child: Artwork(
                          item: item,
                          borderRadius: 0,
                          showMonogram: false,
                          useBackdrop: true,
                        ),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0x73000000),
                              Colors.transparent,
                              AppColors.ink,
                            ],
                            stops: [0, 0.38, 1],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 20.w,
                        right: 20.w,
                        bottom: 18.h,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ContentBadge(item: item),
                            SizedBox(height: 12.h),
                            _DetailsTitle(item: item),
                            SizedBox(height: 12.h),
                            _HeroMeta(item: item),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20.w, 6.h, 20.w, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.isVideo) ...[
                        Reveal(
                          child: Text(
                            item.genres.isEmpty
                                ? item.subtitle
                                : item.genres.join(' · '),
                            style: TextStyle(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                        SizedBox(height: 16.h),
                      ],
                      if (item.progress > 0 && item.isFreeFull)
                        Reveal(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6.r),
                            child: LinearProgressIndicator(
                              value: item.progress,
                              minHeight: 5.h,
                              backgroundColor: AppColors.surfaceHigh,
                              valueColor: AlwaysStoppedAnimation(
                                item.category.accent,
                              ),
                            ),
                          ),
                        ),
                      if (item.progress > 0 && item.isFreeFull)
                        SizedBox(height: 18.h),
                      Reveal(
                        child: Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _openPlayer(context, item),
                                icon: Icon(
                                  Icons.play_arrow_rounded,
                                  size: 22.r,
                                ),
                                label: Text(
                                  item.progress > 0.02 && item.isFreeFull
                                      ? 'Продолжить'
                                      : 'Смотреть',
                                ),
                                style: FilledButton.styleFrom(
                                  minimumSize: Size.fromHeight(52.h),
                                  backgroundColor: item.category.accent,
                                  foregroundColor: AppColors.ink,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16.r),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 10.w),
                            _RoundIconButton(
                              icon: Icons.ios_share_rounded,
                              size: 52,
                              onTap: () => _share(item),
                              tooltip: 'Поделиться',
                            ),
                            SizedBox(width: 8.w),
                            _RoundIconButton(
                              icon: Icons.open_in_new_rounded,
                              size: 52,
                              onTap: () => _openSource(item),
                              tooltip: 'Открыть источник',
                            ),
                          ],
                        ),
                      ),
                      if (_fullVersion != null &&
                          _fullVersion!.id != item.id) ...[
                        SizedBox(height: 12.h),
                        Reveal(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _openPlayer(context, _fullVersion!),
                            icon: Icon(
                              Icons.play_circle_fill_rounded,
                              size: 20.r,
                            ),
                            label: const Text('Бесплатная полная версия'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: Size.fromHeight(48.h),
                              foregroundColor: AppColors.textPrimary,
                              side: BorderSide(
                                color: AppColors.success.withValues(alpha: 0.5),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16.r),
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (item.origin.isTrailerOnly) ...[
                        SizedBox(height: 14.h),
                        _SourceNotice(
                          loading: _detailsLoading,
                          fullAvailable: _fullVersion != null,
                        ),
                      ],
                      SizedBox(height: 24.h),
                      Reveal(
                        delay: const Duration(milliseconds: 90),
                        child: _Description(
                          text: item.description.isEmpty
                              ? 'Описание пока недоступно: источник не отдал '
                                    'текст для этого релиза.'
                              : item.description,
                          expanded: _expanded,
                          onToggle: () =>
                              setState(() => _expanded = !_expanded),
                        ),
                      ),
                      SizedBox(height: 26.h),
                      _MetaGrid(item: item),
                      if (item.cast.isNotEmpty) ...[
                        SizedBox(height: 24.h),
                        _CastList(names: item.cast),
                      ],
                      SizedBox(height: 28.h),
                    ],
                  ),
                ),
              ),
              if (recommendations.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: SectionHeader(
                    title: 'Похожее',
                    icon: Icons.auto_awesome_rounded,
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: item.category == MediaCategory.music
                        ? 232.h
                        : 292.h,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.symmetric(horizontal: 20.w),
                      itemCount: recommendations.length,
                      separatorBuilder: (_, _) => SizedBox(width: 14.w),
                      itemBuilder: (context, index) {
                        final related = recommendations[index];
                        return Reveal(
                          delay: Duration(milliseconds: 60 * index),
                          child: PosterCard(
                            item: related,
                            onTap: () => openMediaItem(
                              context,
                              related,
                              queue: recommendations,
                            ),
                            onFavoriteToggle: () => context
                                .read<CatalogCubit>()
                                .toggleFavorite(related),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
              SliverToBoxAdapter(child: SizedBox(height: 60.h)),
            ],
          ),
        );
      },
    );
  }

  /// Рекомендации для блока «Похожее».
  ///
  /// Только настоящие элементы каталога того же раздела: их можно открыть
  /// и посмотреть. Если раздел ещё пуст, блок не показывается вовсе —
  /// вымышленных карточек в интерфейсе нет.
  List<MediaItem> _recommendationsFor(CatalogState state, MediaItem current) {
    return state.items
        .where(
          (entry) => entry.category == current.category && entry.id != current.id,
        )
        .take(10)
        .toList();
  }

  /// Альбом сначала открывает треклист, трек и видео — плеер.
  void _openPlayer(BuildContext context, MediaItem item) {
    if (item.hasAlbum && !item.isTrack) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => AlbumScreen(album: item)),
      );
      return;
    }

    final queue = widget.queue.isNotEmpty
        ? widget.queue
        : [
            item,
            ...context
                .read<CatalogCubit>()
                .state
                .forCategory(item.category)
                .where((entry) => entry.id != item.id),
          ];

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(item: item, queue: queue),
      ),
    );
  }

  /// Копирует ссылку на источник в буфер обмена.
  Future<void> _share(MediaItem item) async {
    final url = _sourceUrl(item);
    final date = item.releaseYear > 0 ? ' (${item.releaseYear})' : '';
    final text = url == null
        ? '${item.title}$date — LUMA'
        : '${item.title}$date — $url';

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          url == null
              ? 'Название скопировано'
              : 'Ссылка на «${item.title}» скопирована',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Открывает исходную страницу: YouTube, Internet Archive или IMDb.
  Future<void> _openSource(MediaItem item) async {
    final url = _sourceUrl(item);
    if (url == null) {
      await _share(item);
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) return;

    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть ссылку')),
      );
    }
  }

  static String? _sourceUrl(MediaItem item) {
    if (item.hasTrailer) {
      return 'https://www.youtube.com/watch?v=${item.trailerId}';
    }
    if (item.origin == MediaOrigin.archive &&
        item.externalId != null &&
        item.externalId!.isNotEmpty) {
      return 'https://archive.org/details/${item.externalId}';
    }
    if (item.imdbId != null && item.imdbId!.isNotEmpty) {
      return 'https://www.imdb.com/title/${item.imdbId}/';
    }
    return null;
  }
}

/// Открывает подходящий экран для элемента каталога.
///
/// Альбом или плейлист из источника музыки ведёт к треклисту, трек и видео —
/// к описанию: так поведение одинаково во всех лентах, поиске и библиотеке.
/// [queue] — подборка, из которой открыт элемент: она доедет до плеера, чтобы
/// кнопки «Следующий»/«Предыдущий» работали в том же порядке, что и список.
void openMediaItem(
  BuildContext context,
  MediaItem item, {
  List<MediaItem> queue = const [],
}) {
  final route = item.opensCollection
      ? MaterialPageRoute<void>(builder: (_) => AlbumScreen(album: item))
      : MaterialPageRoute<void>(
          builder: (_) => DetailsScreen(item: item, queue: queue),
        );
  Navigator.of(context).push(route);
}

/// Название или прозрачный логотип поверх фона.
class _DetailsTitle extends StatelessWidget {
  const _DetailsTitle({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final logo = item.logoUrl;
    if (logo != null && logo.isNotEmpty) {
      return SizedBox(
        height: 58.h,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Image.network(
            logo,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            errorBuilder: (_, _, _) => _title(),
          ),
        ),
      );
    }
    return _title();
  }

  Widget _title() {
    return Text(
      item.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 28.sp,
        height: 1.08,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.9,
        color: AppColors.textPrimary,
      ),
    );
  }
}

/// Оценка, год и длительность под названием.
class _HeroMeta extends StatelessWidget {
  const _HeroMeta({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (item.releaseYear > 0) '${item.releaseYear}',
      if (item.durationLabel.isNotEmpty) item.durationLabel,
      if (item.country != null && item.country!.isNotEmpty) item.country!,
    ];

    return Row(
      children: [
        if (item.hasScore) ...[
          Container(
            padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 5.h),
            decoration: BoxDecoration(
              color: AppColors.series.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.star_rounded,
                  size: 14.r,
                  color: AppColors.series,
                ),
                SizedBox(width: 4.w),
                Text(
                  item.scoreLabel,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w900,
                    color: AppColors.series,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 10.w),
        ],
        Flexible(
          child: Text(
            parts.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

/// Метка формата: трейлер или полный фильм.
class _ContentBadge extends StatelessWidget {
  const _ContentBadge({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final full = item.isFreeFull;
    final tone = full ? AppColors.success : AppColors.secondary;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: tone.withValues(alpha: 0.36)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            full
                ? Icons.play_circle_fill_rounded
                : Icons.smart_display_rounded,
            size: 13.r,
            color: tone,
          ),
          SizedBox(width: 5.w),
          Text(
            full ? 'ПОЛНЫЙ ФИЛЬМ · БЕСПЛАТНО' : 'ОФИЦИАЛЬНЫЙ ТРЕЙЛЕР',
            style: TextStyle(
              fontSize: 9.5.sp,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }
}

/// Пояснение о формате и источнике.
class _SourceNotice extends StatelessWidget {
  const _SourceNotice({required this.loading, required this.fullAvailable});

  final bool loading;
  final bool fullAvailable;

  @override
  Widget build(BuildContext context) {
    final text = loading
        ? 'Ищем бесплатную полную версию…'
        : fullAvailable
        ? 'Нашлась полная версия в Internet Archive — она откроется бесплатно.'
        : 'Это официальный трейлер. Полная версия фильма доступна в '
              'кинотеатрах и на официальных сервисах.';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 11.h),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (loading)
            SizedBox(
              width: 14.r,
              height: 14.r,
              child: const CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              fullAvailable
                  ? Icons.check_circle_outline_rounded
                  : Icons.info_outline_rounded,
              size: 15.r,
              color: fullAvailable
                  ? AppColors.success
                  : AppColors.textMuted,
            ),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.sp,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Описание с раскрытием длинного текста.
class _Description extends StatelessWidget {
  const _Description({
    required this.text,
    required this.expanded,
    required this.onToggle,
  });

  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'О фильме',
          style: TextStyle(
            fontSize: 17.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(height: 10.h),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topLeft,
          child: Text(
            text,
            maxLines: expanded ? null : 5,
            overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14.5.sp,
              height: 1.6,
              color: AppColors.textMuted,
            ),
          ),
        ),
        SizedBox(height: 6.h),
        GestureDetector(
          onTap: onToggle,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 6.h),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  expanded ? 'Свернуть' : 'Читать полностью',
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w800,
                    color: AppColors.secondary,
                  ),
                ),
                SizedBox(width: 4.w),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18.r,
                  color: AppColors.secondary,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Сетка фактов о фильме.
class _MetaGrid extends StatelessWidget {
  const _MetaGrid({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final entries = <(String, String, IconData)>[
      if (item.directors.isNotEmpty)
        ('Режиссёр', item.directors.take(2).join(', '), Icons.movie_edit),
      if (item.country != null && item.country!.isNotEmpty)
        ('Страна', item.country!, Icons.public_rounded),
      if (item.genres.isNotEmpty)
        ('Жанры', item.genres.take(3).join(', '), Icons.theater_comedy_rounded),
      if (item.releaseDate != null)
        ('Премьера', _formatDate(item.releaseDate!), Icons.event_rounded),
      if (item.durationLabel.isNotEmpty)
        ('Длительность', item.durationLabel, Icons.schedule_rounded),
      if (item.hasScore)
        (
          'Оценка',
          '${item.scoreLabel} / 10',
          Icons.star_outline_rounded,
        ),
    ];

    if (entries.isEmpty) return const SizedBox.shrink();
    final cardWidth = (MediaQuery.sizeOf(context).width - 52.w) / 2;

    return Wrap(
      spacing: 12.w,
      runSpacing: 12.h,
      children: [
        for (final (label, value, icon) in entries)
          Container(
            width: cardWidth,
            padding: EdgeInsets.all(14.r),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18.r),
              border: Border.all(color: AppColors.outline),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 17.r, color: AppColors.textMuted),
                SizedBox(width: 9.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9.5.sp,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                          color: AppColors.textMuted,
                        ),
                      ),
                      SizedBox(height: 5.h),
                      Text(
                        value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.sp,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _formatDate(String iso) {
    final date = DateTime.tryParse(iso);
    if (date == null) return iso;
    const months = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

/// Актёрский состав в виде чипов.
class _CastList extends StatelessWidget {
  const _CastList({required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'В ролях',
          style: TextStyle(
            fontSize: 17.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(height: 10.h),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: [
            for (final name in names)
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 12.w,
                  vertical: 7.h,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: AppColors.outline),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.person_outline_rounded,
                      size: 14.r,
                      color: AppColors.textMuted,
                    ),
                    SizedBox(width: 5.w),
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 12.5.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 44,
    this.color = Colors.white,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: size.r,
          height: size.r,
          decoration: BoxDecoration(
            color: AppColors.ink.withValues(alpha: 0.55),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
          child: Icon(icon, size: (size * 0.45).r, color: color),
        ),
      ),
    );
  }
}
