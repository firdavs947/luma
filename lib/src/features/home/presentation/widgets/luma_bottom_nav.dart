import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';

/// Пункт нижней навигации.
class LumaNavItem {
  const LumaNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Нижняя навигация LUMA с плавным «пилюльным» индикатором.
class LumaBottomNav extends StatelessWidget {
  const LumaBottomNav({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  static const items = <LumaNavItem>[
    LumaNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Главная',
    ),
    LumaNavItem(
      icon: Icons.search_rounded,
      activeIcon: Icons.search_rounded,
      label: 'Поиск',
    ),
    LumaNavItem(
      icon: Icons.bookmark_border_rounded,
      activeIcon: Icons.bookmark_rounded,
      label: 'Библиотека',
    ),
    LumaNavItem(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Профиль',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // На узком экране (например, 320 dp) подписи физически не помещаются в
    // четыре пункта: тогда навигация работает в иконочном режиме, и элементы
    // не наезжают друг на друга и не обрезаются.
    final showLabels = !context.isCompactWidth;

    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 0, 16.w, 14.h),
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(26.r),
        border: Border.all(color: AppColors.outline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24.r,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          for (var index = 0; index < items.length; index++)
            Expanded(
              child: _NavButton(
                item: items[index],
                selected: index == currentIndex,
                showLabel: showLabels,
                onTap: () => onSelect(index),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.showLabel,
    required this.onTap,
  });

  final LumaNavItem item;
  final bool selected;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(vertical: 11.h, horizontal: 6.w),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  selected ? item.activeIcon : item.icon,
                  key: ValueKey(selected),
                  size: 24.r,
                  color: selected ? AppColors.primary : AppColors.textMuted,
                ),
              ),
              Flexible(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  child: selected && showLabel
                      ? Padding(
                          padding: EdgeInsets.only(left: 8.w),
                          // Подпись занимает не больше оставшегося места:
                          // если его мало, текст мягко уменьшается — без
                          // обрезки, многоточия и выхода за границы пункта.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              item.label,
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
