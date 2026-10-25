import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Опорные размеры, по которым свёрстан интерфейс LUMA.
///
/// Все пропорциональные размеры в коде задаются через `.w`, `.h`, `.r`, `.sp`
/// относительно этих значений, поэтому интерфейс одинаково выглядит на телефоне
/// с диагональю 5" и на крупном экране.
abstract final class DesignSpec {
  static const Size base = Size(390, 844);
}

/// Точки перехода адаптивной вёрстки.
abstract final class Breakpoints {
  /// Уже этой ширины интерфейс считается «узким»: подписи и отступы
  /// приходится экономить, а второстепенные надписи — скрывать.
  static const double compact = 360;

  /// С этой ширины устройство считается планшетом: пропорциональное
  /// масштабирование отключается, а колонка контента ограничивается.
  static const double tablet = 600;

  /// Предельная ширина колонки контента на широких экранах.
  static const double contentMaxWidth = 560;

  /// Минимальная ширина плитки в сетках контента.
  ///
  /// По ней считается число колонок: на телефоне 360 dp их две, на планшете
  /// 768 dp — четыре, на десктопе 2560 dp — восемь. Так сетка сама
  /// подстраивается под любой экран, от компактных телефонов до 4K.
  static const double minTileWidth = 168;

  /// Сколько колонок максимум бывает в сетке контента.
  static const int maxColumns = 8;
}

extension ResponsiveContext on BuildContext {
  Size get screenSize => MediaQuery.sizeOf(this);

  /// Ориентация: от неё зависят пропорции сцен и высота шапок.
  bool get isLandscape =>
      MediaQuery.orientationOf(this) == Orientation.landscape;

  /// Узкий экран (например, 320 dp по ширине).
  bool get isCompactWidth => screenSize.width < Breakpoints.compact;

  /// Планшет или десктоп: экран шире, чем у телефона.
  bool get isWideScreen => screenSize.width >= Breakpoints.tablet;

  /// Число колонок сетки контента под текущую ширину экрана.
  ///
  /// Считается по фактической ширине, поэтому одна и та же сетка работает
  /// и на телефоне 360×640 (2 колонки), и на планшете 768×1024 (4), и на
  /// 4K-мониторе (до 8 колонок).
  int get gridColumns => gridColumnsFor(this);
}

/// Число колонок сетки для ширины экрана [context].
///
/// [minTileWidth] задаёт желаемую ширину плитки: чем крупнее карточки, тем
/// больше это значение и тем меньше колонок.
int gridColumnsFor(BuildContext context, {double minTileWidth = Breakpoints.minTileWidth}) {
  final width = context.screenSize.width;
  final columns = (width / minTileWidth).floor();
  return columns.clamp(2, Breakpoints.maxColumns);
}

/// Пропорционально ли масштабируется интерфейс на этом экране.
///
/// Доступно до появления [MediaQuery] в дереве, поэтому берёт размеры прямо
/// из [ScreenUtil]: на планшетах масштаб отключаем — крупный экран выигрывает
/// не от гигантских элементов, а от того, что в него влезает больше контента.
bool get isProportionalScalingEnabled {
  final screen = ScreenUtil();
  final shortest = screen.screenWidth < screen.screenHeight
      ? screen.screenWidth
      : screen.screenHeight;
  return shortest < Breakpoints.tablet;
}

/// Ограничивает ширину содержимого «читаемой» колонкой и центрирует её.
///
/// На телефоне это прозрачный контейнер, на планшете и в ландшафте — способ
/// не растягивать строки текста и списки на всю ширину экрана.
class ResponsiveContent extends StatelessWidget {
  const ResponsiveContent({
    super.key,
    required this.child,
    this.maxWidth = Breakpoints.contentMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
