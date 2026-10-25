import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/luma_logo.dart';
import '../auth/presentation/login_screen.dart';

/// Стартовый экран бренда LUMA.
///
/// Сохраняет исходную анимацию: вращение знака (3 оборота), его подъём на
/// скруглённую панель и «портальное» расширение кнопки перехода.
/// Переход на экран входа инициируется только пользователем.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const _turns = 3;

  double get _logoSize => 104.r;
  double get _panelEndHeight => 268.h;
  double get _panelRadius => 60.r;
  double get _buttonSize => 84.r;
  double get _buttonBottomPadding => 80.h;

  late final AnimationController _mainController;
  late final AnimationController _expandController;

  late final Animation<double> _rotation;
  late final Animation<double> _rise;
  late final Animation<double> _buttonScale;
  late final Animation<double> _wordmarkOpacity;

  bool _isExpanding = false;

  @override
  void initState() {
    super.initState();

    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _rotation = Tween<double>(begin: 0, end: _turns * 2 * math.pi).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0, 0.4, curve: Curves.easeOutCubic),
      ),
    );

    _rise = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.45, 0.8, curve: Curves.easeInOutCubic),
    );

    _buttonScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.8, 1.0, curve: Curves.elasticOut),
      ),
    );

    _wordmarkOpacity = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.62, 0.86, curve: Curves.easeOut),
    );

    _mainController.forward();
  }

  @override
  void dispose() {
    _mainController.dispose();
    _expandController.dispose();
    super.dispose();
  }

  /// Перезапуск анимации по нажатию на знак — с полным сбросом состояния.
  void _restartAnimation() {
    if (_isExpanding) return;
    _expandController.reset();
    _mainController
      ..reset()
      ..forward();
  }

  Future<void> _onEnterPressed() async {
    if (_isExpanding) return;
    setState(() => _isExpanding = true);

    // Плавная кривая для эффекта «портала».
    await _expandController.animateTo(1.0, curve: Curves.easeInOutExpo);

    if (!mounted) return;

    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const LoginScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 320),
      ),
    );

    // Возвращаемся в исходное состояние при возврате на сплэш.
    if (!mounted) return;
    setState(() => _isExpanding = false);
    _expandController.reset();
    _mainController
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: AnimatedBuilder(
        animation: Listenable.merge([_mainController, _expandController]),
        child: LumaLogo(size: _logoSize, glow: true),
        builder: (context, child) {
          final t = _rise.value;
          final expandT = _expandController.value;

          // Скруглённая панель, которая поднимается из нижней части экрана.
          final panelHeight = size.height + (_panelEndHeight - size.height) * t;
          final radius = _panelRadius * t;

          // Траектория знака: центр экрана → центр панели.
          final logoStart = (size.height - _logoSize) / 2;
          final logoEnd =
              topInset + (_panelEndHeight - topInset - _logoSize) / 2;
          final logoTop = logoStart + (logoEnd - logoStart) * t;

          // Круглая кнопка перехода.
          final maxExpandSize =
              math.sqrt(size.width * size.width + size.height * size.height) *
              2;
          final currentSize =
              _buttonSize + (maxExpandSize - _buttonSize) * expandT;
          final buttonBottom = _buttonBottomPadding * (1 - expandT);
          final buttonOpacity = _isExpanding ? 1.0 : _buttonScale.value;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: panelHeight,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.elliptical(radius * 1.5, radius),
                      bottomRight: Radius.elliptical(radius * 1.5, radius),
                    ),
                  ),
                ),
              ),

              // Знак бренда: вращение сменяется подъёмом на панель.
              Positioned(
                top: logoTop,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: _restartAnimation,
                    behavior: HitTestBehavior.opaque,
                    child: Transform.rotate(
                      angle: _rotation.value,
                      child: child,
                    ),
                  ),
                ),
              ),

              // Вордмарк появляется после стабилизации знака.
              Positioned(
                top: logoTop + _logoSize + 14.h,
                left: 0,
                right: 0,
                child: Opacity(
                  opacity: (_wordmarkOpacity.value * t).clamp(0.0, 1.0),
                  child: Center(
                    child: LumaWordmark(fontSize: 22.sp, color: AppColors.ink),
                  ),
                ),
              ),

              // Кнопка перехода — расширяется в «портал».
              Positioned(
                bottom: buttonBottom - (currentSize - _buttonSize) / 2,
                left: (size.width - currentSize) / 2,
                child: Transform.scale(
                  scale: _isExpanding ? 1.0 : _buttonScale.value,
                  child: Opacity(
                    opacity: buttonOpacity.clamp(0.0, 1.0),
                    child: GestureDetector(
                      onTap: _isExpanding ? null : _onEnterPressed,
                      child: Container(
                        width: currentSize,
                        height: currentSize,
                        decoration: BoxDecoration(
                          color: AppColors.ink,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.45),
                              blurRadius: 30.r,
                              spreadRadius: 3.r,
                            ),
                          ],
                        ),
                        child: _isExpanding
                            ? const SizedBox.shrink()
                            : Center(
                                child: Icon(
                                  Icons.arrow_forward_rounded,
                                  color: Colors.white,
                                  size: 34.r,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
