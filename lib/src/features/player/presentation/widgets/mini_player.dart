import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart' as bg;

import '../../../../core/audio/audio_engine.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/artwork.dart';
import '../../../catalog/domain/media_item.dart';
import '../player_screen.dart';

/// Мини-плеер, который отображается над нижней навигацией.
///
/// Он позволяет управлять воспроизведением, не прерывая просмотр каталога,
/// и открывает полноэкранный плеер при нажатии.
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer>
    with SingleTickerProviderStateMixin {
  AudioPlayer get _player => AudioEngine.player;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SequenceState?>(
      stream: _player.sequenceStateStream,
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state == null) return const SizedBox.shrink();

        final tag = state.currentSource?.tag;
        if (tag is! bg.MediaItem) return const SizedBox.shrink();

        final item = MediaItem(
          id: tag.id,
          title: tag.title,
          subtitle: tag.artist ?? '',
          imageUrl: tag.artUri?.toString() ?? '',
          category: MediaCategory.music,
          year: 0,
          rating: 0,
          durationLabel: '',
        );

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          child: GestureDetector(
            onTap: () => _showFullPlayer(context, item),
            child: Container(
              height: 68.h, // Чуть увеличили для солидности
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(22.r),
                border: Border.all(
                  color: AppColors.outline.withValues(alpha: 0.5),
                  width: 1.5.r,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 25.r,
                    spreadRadius: -2.r,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20.r),
                child: Stack(
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12.w),
                      child: Row(
                        children: [
                          _buildAnimatedArtwork(item),
                          SizedBox(width: 14.w),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 14.sp,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.2,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                    _buildEqualizerIcon(),
                                  ],
                                ),
                                SizedBox(height: 1.h),
                                Text(
                                  item.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildPlaybackControls(),
                        ],
                      ),
                    ),
                    _buildProgressBar(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnimatedArtwork(MediaItem item) {
    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ?? false;
        return AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final scale = playing ? 1.0 + (_pulseController.value * 0.05) : 1.0;
            return Transform.scale(
              scale: scale,
              child: Hero(
                tag: 'artwork-${item.id}',
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10.r),
                    boxShadow: [
                      if (playing)
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 12.r,
                          spreadRadius: 1.r,
                        ),
                    ],
                  ),
                  child: SizedBox(
                    width: 44.r,
                    height: 44.r,
                    child: Artwork(item: item, borderRadius: 10.r),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEqualizerIcon() {
    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ?? false;
        if (!playing) return const SizedBox.shrink();

        return Padding(
          padding: EdgeInsets.only(left: 8.w),
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final h =
                      6 +
                      8 *
                          math.sin(
                            (_pulseController.value * 2 * math.pi) + (i * 1.5),
                          );
                  return Container(
                    width: 2.r,
                    height: h.abs().clamp(4, 14),
                    margin: EdgeInsets.symmetric(horizontal: 1.w),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(1.r),
                    ),
                  );
                }),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildPlaybackControls() {
    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ?? false;
        final processing = snapshot.data?.processingState;

        if (processing == ProcessingState.buffering ||
            processing == ProcessingState.loading) {
          return SizedBox(
            width: 44.r,
            height: 44.r,
            child: Center(
              child: SizedBox(
                width: 24.r,
                height: 24.r,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5.r,
                  color: AppColors.primary,
                ),
              ),
            ),
          );
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 32.r,
                color: AppColors.textPrimary,
              ),
              onPressed: () => playing ? _player.pause() : _player.play(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProgressBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: StreamBuilder<Duration>(
        stream: _player.positionStream,
        builder: (context, snapshot) {
          final position = snapshot.data ?? Duration.zero;
          final duration = _player.duration ?? Duration.zero;
          final progress = duration.inMilliseconds > 0
              ? position.inMilliseconds / duration.inMilliseconds
              : 0.0;

          return Container(
            height: 3.h,
            color: AppColors.primary.withValues(alpha: 0.12),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.5),
                      blurRadius: 4.r,
                      spreadRadius: 1.r,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showFullPlayer(BuildContext context, MediaItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      enableDrag: true,
      useSafeArea: true,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32.r)),
      ),
      builder: (context) => ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32.r)),
        child: PlayerScreen(item: item),
      ),
    );
  }
}
