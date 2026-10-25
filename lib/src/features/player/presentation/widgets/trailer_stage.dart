import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart' as yt;

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/artwork.dart';
import '../../../../core/widgets/motion.dart';
import '../../../catalog/domain/media_item.dart';

/// Сцена официального трейлера.
///
/// Кадр строит встроенный YouTube-плеер: у него собственные controls,
/// качество и полноэкранный режим. Если ролик не открылся, поверх постера
/// показывается предложение повторить или перейти на YouTube.
class TrailerStage extends StatelessWidget {
  const TrailerStage({
    super.key,
    required this.controller,
    required this.item,
    required this.loading,
    required this.failed,
    required this.onRetry,
    required this.onOpenExternal,
  });

  /// Контроллер встроенного плеера; `null` — ролик ещё не создан.
  final yt.YoutubePlayerController? controller;

  /// Элемент каталога: постер и акцент раздела.
  final MediaItem item;

  /// Идёт разрешение потока.
  final bool loading;

  /// Встроенный плеер не открылся или ролик недоступен.
  final bool failed;

  final VoidCallback onRetry;
  final VoidCallback onOpenExternal;

  @override
  Widget build(BuildContext context) {
    final player = controller;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24.r),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (player != null && !failed)
                  yt.YoutubePlayer(
                    controller: player,
                    aspectRatio: 16 / 9,
                    backgroundColor: Colors.black,
                    enableFullScreenOnVerticalDrag: true,
                  )
                else
                  Artwork(item: item, borderRadius: 0, showMonogram: false),

                // Метка источника в углу кадра.
                Positioned(
                  left: 12.w,
                  top: 12.h,
                  child: IgnorePointer(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10.w,
                        vertical: 5.h,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.ink.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.play_circle_fill_rounded,
                            size: 13.r,
                            color: Colors.white,
                          ),
                          SizedBox(width: 5.w),
                          Text(
                            'ТРЕЙЛЕР',
                            style: TextStyle(
                              fontSize: 10.sp,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                if (player != null && !failed)
                  Positioned(
                    right: 12.w,
                    top: 12.h,
                    child: _ExternalButton(onTap: onOpenExternal),
                  ),

                if (loading)
                  const Center(child: LumaLoader(size: 46)),

                if (failed && !loading)
                  Center(
                    child: _TrailerFailure(
                      onRetry: onRetry,
                      onOpenExternal: onOpenExternal,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Кнопка перехода на YouTube поверх кадра.
class _ExternalButton extends StatelessWidget {
  const _ExternalButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Открыть на YouTube',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 38.r,
          height: 38.r,
          decoration: BoxDecoration(
            color: AppColors.ink.withValues(alpha: 0.55),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
          child: Icon(
            Icons.open_in_new_rounded,
            size: 19.r,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Состояние «трейлер недоступен» с двумя выходами.
class _TrailerFailure extends StatelessWidget {
  const _TrailerFailure({
    required this.onRetry,
    required this.onOpenExternal,
  });

  final VoidCallback onRetry;
  final VoidCallback onOpenExternal;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
      margin: EdgeInsets.symmetric(horizontal: 20.w),
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.45)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.videocam_off_rounded,
            size: 34.r,
            color: AppColors.error,
          ),
          SizedBox(height: 10.h),
          Text(
            'Трейлер недоступен',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            'Встроенный плеер не открылся. Повторите попытку или посмотрите '
            'ролик на YouTube.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.sp,
              height: 1.4,
              color: AppColors.textMuted,
            ),
          ),
          SizedBox(height: 12.h),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: onRetry,
                child: const Text('Повторить'),
              ),
              SizedBox(width: 8.w),
              FilledButton.icon(
                onPressed: onOpenExternal,
                icon: Icon(Icons.open_in_new_rounded, size: 17.r),
                label: const Text('На YouTube'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
