import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../features/catalog/domain/media_item.dart';
import '../theme/app_colors.dart';
import 'artwork.dart';
import 'motion.dart';

/// Постер-карточка для горизонтальных лент каталога.
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onFavoriteToggle,
    this.width = 148,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback? onFavoriteToggle;
  final double width;

  @override
  Widget build(BuildContext context) {
    final aspect = item.category == MediaCategory.music ? 1.0 : 1.45;
    // Ширина задаётся в dp дизайна и масштабируется по меньшему из коэффициентов
    // (ширина/высота): высота обложки = width × aspect и должна укладываться
    // в `.h`-скейл высоты ленты. Если карточка растягивается родителем
    // (Grid/Expanded), ширина бесконечна и масштабировать её не нужно.
    final cardWidth = width.isFinite ? width.r : width;

    return AnimatedTap(
      onTap: onTap,
      child: HoverLift(
        child: SizedBox(
          width: cardWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1 / aspect,
                child: Stack(
                  children: [
                    // Без Hero: одна и та же запись встречается в «Новинках»,
                    // «Бесплатно целиком» и ленте раздела, а дубли тегов
                    // ломают переход на экран описания.
                    Positioned.fill(child: Artwork(item: item)),
                    if (item.hasScore || item.hasRating)
                      Positioned(
                        top: 10.h,
                        left: 10.w,
                        child: _RatingChip(item: item),
                      ),
                    if (item.isVideo)
                      Positioned(
                        left: 10.w,
                        bottom: item.progress > 0 ? 24.h : 10.h,
                        child: _ContentBadge(item: item),
                      ),
                    if (onFavoriteToggle != null)
                      Positioned(
                        top: 6.h,
                        right: 6.w,
                        child: _FavoriteButton(
                          active: item.isFavorite,
                          onTap: onFavoriteToggle!,
                        ),
                      ),
                    if (item.progress > 0)
                      Positioned(
                        left: 12.w,
                        right: 12.w,
                        bottom: 12.h,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4.r),
                          child: LinearProgressIndicator(
                            value: item.progress,
                            minHeight: 3.5.h,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.25),
                            valueColor: const AlwaysStoppedAnimation(
                              AppColors.secondary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: 10.h),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14.5.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 3.h),
              Text(
                item.isVideo ? item.shortMeta : item.subtitle,
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
      ),
    );
  }
}

/// Горизонтальная строка списка: обложка + описание.
class MediaRowTile extends StatelessWidget {
  const MediaRowTile({
    super.key,
    required this.item,
    required this.onTap,
    this.trailing,
    this.showProgress = true,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    return AnimatedTap(
      onTap: onTap,
      scale: 0.98,
      child: HoverLift(
        scale: 1.02,
        child: Container(
          padding: EdgeInsets.all(10.r),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(color: AppColors.outline),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 62.r,
                height: 62.r,
                child: Artwork(item: item, borderRadius: 14),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      '${item.subtitle} · ${item.durationLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5.sp,
                        color: AppColors.textMuted,
                      ),
                    ),
                    if (showProgress && item.progress > 0) ...[
                      SizedBox(height: 8.h),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4.r),
                        child: LinearProgressIndicator(
                          value: item.progress,
                          minHeight: 3.h,
                          backgroundColor: AppColors.surfaceHigh,
                          valueColor:
                              AlwaysStoppedAnimation(item.category.accent),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              trailing ??
                  Icon(
                    item.isVideo
                        ? Icons.play_circle_fill_rounded
                        : Icons.headphones_rounded,
                    color: item.category.accent,
                    size: 30.r,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Кнопка догрузки следующей страницы каталога.
///
/// Пока идёт запрос, показывает индикатор вместо подписи — так виден факт
/// загрузки, а повторные нажатия ничего не ломают.
class LoadMoreButton extends StatelessWidget {
  const LoadMoreButton({
    super.key,
    required this.onPressed,
    this.loading = false,
    this.label = 'Показать ещё',
  });

  final VoidCallback onPressed;
  final bool loading;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AnimatedTap(
      onTap: loading ? null : onPressed,
      scale: 0.97,
      child: Container(
        height: 54.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18.r),
          border: Border.all(color: AppColors.outline),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: loading
              ? SizedBox(
                  key: const ValueKey('loading'),
                  width: 20.r,
                  height: 20.r,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2.r,
                    color: AppColors.secondary,
                  ),
                )
              : Row(
                  key: const ValueKey('idle'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.expand_more_rounded,
                      size: 20.r,
                      color: AppColors.textPrimary,
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14.5.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Заголовок секции с опциональным действием «Все».
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.onSeeAll,
    this.icon,
  });

  final String title;
  final VoidCallback? onSeeAll;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 0, 12.w, 12.h),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18.r, color: AppColors.textMuted),
            SizedBox(width: 8.w),
          ],
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 19.sp,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              child: const Text(
                'Все',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}

class _RatingChip extends StatelessWidget {
  const _RatingChip({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final label = item.isVideo && item.hasScore
        ? item.scoreLabel
        : item.rating.toStringAsFixed(1);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 13.r, color: AppColors.series),
          SizedBox(width: 3.w),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5.sp,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Метка формата записи: полный фильм или только трейлер.
///
/// Пользователь сразу видит, что можно посмотреть целиком, а где доступен
/// лишь официальный ролик — без этого карточки вводили бы в заблуждение.
class _ContentBadge extends StatelessWidget {
  const _ContentBadge({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final full = item.isFreeFull;
    final tone = full ? AppColors.success : AppColors.textPrimary;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(9.r),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            full
                ? Icons.play_circle_fill_rounded
                : Icons.smart_display_rounded,
            size: 12.r,
            color: tone,
          ),
          SizedBox(width: 4.w),
          Text(
            full ? 'ПОЛНЫЙ ФИЛЬМ' : 'ТРЕЙЛЕР',
            style: TextStyle(
              fontSize: 9.sp,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.all(7.r),
        decoration: BoxDecoration(
          color: AppColors.ink.withValues(alpha: 0.62),
          shape: BoxShape.circle,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: animation,
            child: child,
          ),
          child: Icon(
            active ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            key: ValueKey(active),
            size: 16.r,
            color: active ? AppColors.music : Colors.white,
          ),
        ),
      ),
    );
  }
}
