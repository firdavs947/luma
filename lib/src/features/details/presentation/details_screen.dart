import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/artwork.dart';
import '../../../core/widgets/media_card.dart';
import '../../../core/widgets/motion.dart';
import '../../album/presentation/album_screen.dart';
import '../../catalog/data/mock_catalog.dart';
import '../../catalog/domain/media_item.dart';
import '../../catalog/presentation/bloc/catalog_cubit.dart';
import '../../catalog/presentation/bloc/catalog_state.dart';
import '../../player/presentation/player_screen.dart';

/// Экран описания контента с рекомендациями.
///
/// Элемент передаётся целиком: он может прийти не только из каталога, но и
/// из результатов поиска, поэтому данные берутся из состояния по `id`, а
/// переданное значение используется как запасное.
class DetailsScreen extends StatelessWidget {
  const DetailsScreen({super.key, required this.item, this.queue = const []});

  final MediaItem item;

  /// Подборка, из которой открыт элемент: результаты поиска или лента
  /// раздела. Становится очередью плеера; пустая — плеер соберёт её сам из
  /// каталога того же раздела.
  final List<MediaItem> queue;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CatalogCubit, CatalogState>(
      builder: (context, state) {
        final current = state.byId(item.id) ?? item;
        final recommendations = _recommendationsFor(state, current);
        final heroTag = 'artwork-${current.id}';

        return Scaffold(
          backgroundColor: AppColors.ink,
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: 380.h,
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
                      icon: current.isFavorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color:
                          current.isFavorite ? AppColors.music : Colors.white,
                      onTap: () =>
                          context.read<CatalogCubit>().toggleFavorite(current),
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
                          item: current,
                          borderRadius: 0,
                          showMonogram: false,
                        ),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.center,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, AppColors.ink],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Reveal(
                        child: Row(
                          children: [
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10.w,
                                vertical: 5.h,
                              ),
                              decoration: BoxDecoration(
                                color: current.category.accent
                                    .withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(10.r),
                              ),
                              child: Text(
                                current.category.label.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10.5.sp,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                  color: current.category.accent,
                                ),
                              ),
                            ),
                            if (current.hasRating) ...[
                              SizedBox(width: 10.w),
                              Icon(
                                Icons.star_rounded,
                                size: 16.r,
                                color: AppColors.series,
                              ),
                              SizedBox(width: 4.w),
                              Text(
                                current.rating.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 13.sp,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(height: 14.h),
                      Reveal(
                        delay: const Duration(milliseconds: 70),
                        child: Text(
                          current.title,
                          style: TextStyle(
                            fontSize: 30.sp,
                            height: 1.1,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      SizedBox(height: 10.h),
                      Reveal(
                        delay: const Duration(milliseconds: 120),
                        child: Text(
                          '${current.subtitle} · ${current.year} · '
                          '${current.durationLabel}',
                          style: TextStyle(
                            fontSize: 13.5.sp,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                      SizedBox(height: 18.h),
                      if (current.progress > 0)
                        Reveal(
                          delay: const Duration(milliseconds: 160),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6.r),
                            child: LinearProgressIndicator(
                              value: current.progress,
                              minHeight: 5.h,
                              backgroundColor: AppColors.surfaceHigh,
                              valueColor: AlwaysStoppedAnimation(
                                current.category.accent,
                              ),
                            ),
                          ),
                        ),
                      if (current.progress > 0) SizedBox(height: 20.h),
                      Reveal(
                        delay: const Duration(milliseconds: 200),
                        child: Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _openPlayer(context, current),
                                icon: Icon(
                                  current.isVideo
                                      ? Icons.play_arrow_rounded
                                      : Icons.play_circle_fill_rounded,
                                  size: 22.r,
                                ),
                                label: const Text('Воспроизвести'),
                              ),
                            ),
                            SizedBox(width: 12.w),
                            _RoundIconButton(
                              icon: Icons.download_outlined,
                              size: 52,
                              onTap: () {},
                              tooltip: 'Скачать',
                            ),
                            SizedBox(width: 10.w),
                            _RoundIconButton(
                              icon: Icons.ios_share_rounded,
                              size: 52,
                              onTap: () {},
                              tooltip: 'Поделиться',
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 26.h),
                      Reveal(
                        delay: const Duration(milliseconds: 240),
                        child: Text(
                          current.description.isEmpty
                              ? 'Описание скоро появится.'
                              : current.description,
                          style: TextStyle(
                            fontSize: 14.5.sp,
                            height: 1.6,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                      SizedBox(height: 26.h),
                      _MetaGrid(item: current),
                      SizedBox(height: 30.h),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Похожее',
                  icon: Icons.auto_awesome_rounded,
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height:
                      current.category == MediaCategory.music ? 232.h : 292.h,
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
              SliverToBoxAdapter(child: SizedBox(height: 60.h)),
            ],
          ),
        );
      },
    );
  }

  /// Рекомендации для блока «Похожее».
  ///
  /// Берём настоящие элементы того же раздела из каталога: их можно включить
  /// сразу, тогда как локальный набор — это метаданные без звука. Локальные
  /// рекомендации остаются запасным вариантом, пока раздел ещё не наполнился.
  List<MediaItem> _recommendationsFor(CatalogState state, MediaItem current) {
    final related = state.items
        .where(
          (item) => item.category == current.category && item.id != current.id,
        )
        .toList();

    if (related.isEmpty) return MockCatalog.recommendationsFor(current);
    return related.take(10).toList();
  }

  /// Альбом сначала открывает треклист, трек и видео — плеер.
  ///
  /// Очередь собирается из самого элемента и блока «Похожее»: с ней работают
  /// кнопки «Следующий»/«Предыдущий» и автопереход после окончания записи.
  void _openPlayer(BuildContext context, MediaItem item) {
    if (item.hasAlbum && !item.isTrack) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => AlbumScreen(album: item)),
      );
      return;
    }

    // Очередь — либо переданная подборка (поиск, раздел), либо соседи по
    // разделу. Локальные рекомендации в неё не попадают: это метаданные
    // без звуковой дорожки.
    final queue = this.queue.isNotEmpty
        ? this.queue
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

class _MetaGrid extends StatelessWidget {
  const _MetaGrid({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final entries = <(String, String)>[
      ('Раздел', item.category.label),
      ('Год', '${item.year}'),
      ('Длительность', item.durationLabel),
      if (item.hasRating) ('Рейтинг', item.rating.toStringAsFixed(1)),
    ];

    return Reveal(
      delay: const Duration(milliseconds: 280),
      child: Wrap(
        spacing: 12.w,
        runSpacing: 12.h,
        children: [
          for (final (label, value) in entries)
            Container(
              width: 150.w,
              padding: EdgeInsets.symmetric(
                horizontal: 16.w,
                vertical: 13.h,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18.r),
                border: Border.all(color: AppColors.outline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10.5.sp,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: AppColors.textMuted,
                    ),
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 14.5.sp,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
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
