import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/artwork.dart';
import '../../../core/widgets/motion.dart';
import '../../catalog/data/genius_mapper.dart';
import '../../catalog/domain/media_item.dart';
import '../../genius/domain/genius_models.dart';
import '../../genius/domain/genius_repository.dart';
import '../../player/presentation/player_screen.dart';
import 'bloc/album_cubit.dart';
import 'bloc/album_state.dart';

/// Экран подборки: обложка, описание и треклист альбома или плейлиста.
///
/// Шапка рисуется сразу по данным каталога, а строки треклиста появляются
/// каскадом, когда источник вернёт данные — переход из ленты выглядит
/// мгновенным и не «прыгает».
class AlbumScreen extends StatelessWidget {
  const AlbumScreen({super.key, required this.album});

  /// Элемент каталога, у которого заполнен [`MediaItem.albumId`]
  /// или [`MediaItem.playlistId`].
  final MediaItem album;

  @override
  Widget build(BuildContext context) {
    final playlistId = album.playlistId;

    return BlocProvider(
      create: (context) => AlbumCubit(
        repository: context.read<GeniusRepository>(),
        albumId: album.albumId,
      )..load(),
      child: _AlbumView(preview: album, isPlaylist: playlistId != null),
    );
  }
}

class _AlbumView extends StatelessWidget {
  const _AlbumView({required this.preview, required this.isPlaylist});

  /// Данные, доступные до ответа источника: название, исполнитель, обложка.
  final MediaItem preview;

  /// Открыта подборка плейлиста, а не альбом.
  final bool isPlaylist;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AlbumCubit, AlbumState>(
      builder: (context, state) {
        final collection = state.collection;
        final year = int.tryParse(collection?.releaseYear ?? '');
        final tracks = collection == null
            ? const <MediaItem>[]
            : collection.tracks
                .map(
                  (track) => mediaItemFromTrack(
                    track,
                    collectionTitle: collection.title,
                    collectionImage: collection.imageUrl,
                    year: year,
                  ),
                )
                .toList();

        return Scaffold(
          backgroundColor: AppColors.ink,
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _AlbumHeader(
                item: preview,
                collection: collection,
                isPlaylist: isPlaylist,
              ),
              if (state.status == AlbumStatus.error)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _AlbumError(
                    message: state.error ?? 'Не удалось загрузить альбом',
                    onRetry: () => context.read<AlbumCubit>().load(),
                  ),
                )
              else if (tracks.isEmpty)
                const SliverToBoxAdapter(child: _TracksSkeleton())
              else ...[
                SliverToBoxAdapter(child: _AlbumActions(tracks: tracks)),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 0),
                  sliver: SliverList.separated(
                    itemCount: tracks.length,
                    separatorBuilder: (_, _) => SizedBox(height: 8.h),
                    itemBuilder: (context, index) => Reveal(
                      delay: Duration(milliseconds: 35 * index),
                      offset: 18,
                      child: _TrackRow(
                        position: index + 1,
                        track: tracks[index],
                        onTap: () => _openPlayer(context, tracks, index),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: SizedBox(height: 60.h)),
              ],
            ],
          ),
        );
      },
    );
  }

  void _openPlayer(BuildContext context, List<MediaItem> tracks, int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(item: tracks[index], queue: tracks),
      ),
    );
  }
}

/// Шапка подборки: полноэкранная обложка с плавным затемнением вниз.
class _AlbumHeader extends StatelessWidget {
  const _AlbumHeader({
    required this.item,
    required this.collection,
    required this.isPlaylist,
  });

  final MediaItem item;
  final MusicCollection? collection;
  final bool isPlaylist;

  @override
  Widget build(BuildContext context) {
    final loaded = collection;
    final meta = loaded == null
        ? 'Загружаем треклист…'
        : [loaded.releaseYear, item.durationLabel]
            .whereType<String>()
            .join(' · ');
    final typeLabel = loaded?.typeLabel ?? (isPlaylist ? 'Плейлист' : 'Альбом');

    return SliverAppBar(
      expandedHeight: 372.h,
      pinned: true,
      stretch: true,
      backgroundColor: AppColors.ink,
      leading: Padding(
        padding: EdgeInsets.all(8.r),
        child: _RoundIconButton(
          icon: Icons.arrow_back_rounded,
          tooltip: 'Назад',
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        background: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: 'artwork-${item.id}',
              child: Artwork(item: item, borderRadius: 0, showMonogram: false),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x660A0A0F), Color(0xE60A0A0F), AppColors.ink],
                  stops: [0, 0.6, 1],
                ),
              ),
            ),
            Positioned(
              left: 20.w,
              right: 20.w,
              bottom: 14.h,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Reveal(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10.w,
                        vertical: 5.h,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.music.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Text(
                        typeLabel.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10.5.sp,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                          color: AppColors.music,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  Reveal(
                    delay: const Duration(milliseconds: 70),
                    child: Text(
                      item.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 30.sp,
                        height: 1.08,
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
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  SizedBox(height: 6.h),
                  Reveal(
                    delay: const Duration(milliseconds: 160),
                    child: Text(
                      meta,
                      style: TextStyle(
                        fontSize: 12.5.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Кнопки действий над альбомом.
class _AlbumActions extends StatelessWidget {
  const _AlbumActions({required this.tracks});

  final List<MediaItem> tracks;

  @override
  Widget build(BuildContext context) {
    return Reveal(
      delay: const Duration(milliseconds: 180),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 10.h),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _open(context, tracks, 0),
                icon: Icon(Icons.play_arrow_rounded, size: 24.r),
                label: const Text('Слушать'),
                style: FilledButton.styleFrom(
                  minimumSize: Size.fromHeight(52.r),
                  backgroundColor: AppColors.music,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18.r),
                  ),
                ),
              ),
            ),
            SizedBox(width: 12.w),
            _RoundIconButton(
              icon: Icons.shuffle_rounded,
              size: 52,
              tooltip: 'Перемешать',
              onTap: () {
                final shuffled = [...tracks]..shuffle();
                _open(context, shuffled, 0);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, List<MediaItem> queue, int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(item: queue[index], queue: queue),
      ),
    );
  }
}

/// Строка треклиста.
class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.position,
    required this.track,
    required this.onTap,
  });

  final int position;
  final MediaItem track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedTap(
      onTap: onTap,
      scale: 0.98,
      child: HoverLift(
        scale: 1.015,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18.r),
            border: Border.all(color: AppColors.outline),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 30.w,
                child: Text(
                  '$position',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5.sp,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              SizedBox(width: 4.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      track.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5.sp,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 10.w),
              Text(
                track.durationLabel,
                style: TextStyle(
                  fontSize: 12.5.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
              SizedBox(width: 10.w),
              Icon(
                track.hasPreview
                    ? Icons.play_circle_fill_rounded
                    : Icons.music_note_rounded,
                color: track.hasPreview ? AppColors.music : AppColors.textMuted,
                size: 26.r,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Плейсхолдер треклиста на время загрузки.
class _TracksSkeleton extends StatelessWidget {
  const _TracksSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 26.h, 20.w, 60.h),
      child: Column(
        children: [
          ShimmerBox(height: 52.h, radius: 18.r),
          SizedBox(height: 16.h),
          for (var i = 0; i < 6; i++) ...[
            ShimmerBox(height: 62.h, radius: 18.r),
            SizedBox(height: 8.h),
          ],
        ],
      ),
    );
  }
}

/// Состояние ошибки загрузки альбома.
class _AlbumError extends StatelessWidget {
  const _AlbumError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24.w, 40.h, 24.w, 60.h),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 54.r,
            color: AppColors.outline,
          ),
          SizedBox(height: 16.h),
          Text(
            'Треклист недоступен',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.sp,
              height: 1.5,
              color: AppColors.textMuted,
            ),
          ),
          SizedBox(height: 20.h),
          FilledButton.icon(
            onPressed: onRetry,
            icon: Icon(Icons.refresh_rounded, size: 20.r),
            label: const Text('Повторить'),
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
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final double size;

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
          child: Icon(icon, size: (size * 0.45).r, color: Colors.white),
        ),
      ),
    );
  }
}
