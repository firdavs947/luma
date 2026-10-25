import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Уникальный векторный логотип бренда LUMA.
///
/// Знак объединяет два смысловых слоя сервиса — видео (треугольник
/// воспроизведения) и звук (расходящиеся волны) — в единую монограмму,
/// вписанную в градиентный «сквиркл». Логотип полностью оригинален,
/// не использует чужие торговые знаки и масштабируется без потери качества.
class LumaLogo extends StatefulWidget {
  const LumaLogo({
    super.key,
    this.size = 96,
    this.showBackground = true,
    this.pulse = false,
    this.glow = false,
  });

  /// Сторона квадрата, в который вписан знак.
  final double size;

  /// Рисовать ли градиентную подложку-сквиркл.
  final bool showBackground;

  /// Включает мягкую «пульсацию» звуковых волн.
  final bool pulse;

  /// Добавляет фирменное свечение вокруг знака.
  final bool glow;

  @override
  State<LumaLogo> createState() => _LumaLogoState();
}

class _LumaLogoState extends State<LumaLogo>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.pulse) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2600),
      )..repeat();
    }
  }

  @override
  void didUpdateWidget(covariant LumaLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && _controller == null) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2600),
      )..repeat();
    } else if (!widget.pulse && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final painter = LumaLogoPainter(
      showBackground: widget.showBackground,
      pulse: _controller,
    );

    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: DecoratedBox(
          decoration: widget.glow
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.glow,
                      // Размер знака уже адаптивный — свечение считаем от него.
                      blurRadius: widget.size * 0.45,
                      spreadRadius: widget.size * 0.02,
                    ),
                  ],
                )
              : const BoxDecoration(),
          child: CustomPaint(painter: painter),
        ),
      ),
    );
  }
}

/// Отрисовка знака LUMA на `Canvas`.
class LumaLogoPainter extends CustomPainter {
  LumaLogoPainter({
    this.showBackground = true,
    this.pulse,
    this.highlight = 0.5,
  }) : super(repaint: pulse);

  final bool showBackground;
  final Animation<double>? pulse;

  /// Смещение градиента (0..1), позволяющее «переливать» подложку.
  final double highlight;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    // Нулевой размер встречается в скрытых вкладках и тестах: градиент
    // с пустым прямоугольником на CanvasKit роняет кадр.
    if (s <= 0) return;

    if (showBackground) {
      _paintBackdrop(canvas, s);
    }

    final glyphPaint = Paint()
      ..color = showBackground ? Colors.white : AppColors.primary
      ..isAntiAlias = true;

    _paintPlayTriangle(canvas, s, glyphPaint);
    _paintWaves(canvas, s, glyphPaint);
  }

  void _paintBackdrop(Canvas canvas, double s) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, s, s),
      Radius.circular(s * 0.28),
    );

    final shift = (highlight - 0.5) * s * 0.5;
    final paint = Paint()
      ..isAntiAlias = true
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: const [AppColors.primary, AppColors.secondary],
        transform: GradientRotation(shift / s),
      ).createShader(Rect.fromLTWH(0, 0, s, s));

    canvas.drawRRect(rect, paint);

    // Мягкий блик в верхней части подложки — придаёт объём.
    final sheen = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.22),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, s, s * 0.6));
    canvas.drawRRect(rect, sheen);
  }

  void _paintPlayTriangle(Canvas canvas, double s, Paint paint) {
    final path = Path()
      ..moveTo(s * 0.26, s * 0.29)
      ..lineTo(s * 0.26, s * 0.71)
      ..lineTo(s * 0.545, s * 0.5)
      ..close();

    canvas.drawPath(
      path,
      paint
        ..style = PaintingStyle.fill
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _paintWaves(Canvas canvas, double s, Paint paint) {
    final center = Offset(s * 0.5, s * 0.5);
    const start = -math.pi * 0.36;
    const sweep = math.pi * 0.72;

    final t = pulse?.value ?? 0.0;
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    for (var i = 0; i < 2; i++) {
      final phase = (t + i * 0.5) % 1.0;
      final breathe = pulse == null ? 1.0 : 0.75 + 0.25 * phase;
      final radius = s * (0.17 + i * 0.115) * breathe;
      final opacity = pulse == null ? 1.0 : (1.0 - phase).clamp(0.25, 1.0);

      wavePaint
        ..color = paint.color.withValues(alpha: opacity)
        ..strokeWidth = s * 0.062;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        false,
        wavePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant LumaLogoPainter oldDelegate) {
    return oldDelegate.showBackground != showBackground ||
        oldDelegate.pulse != pulse ||
        oldDelegate.highlight != highlight;
  }
}

/// Текстовая часть логотипа (вордмарк) с фирменным градиентом.
class LumaWordmark extends StatelessWidget {
  const LumaWordmark({super.key, this.fontSize = 28, this.color});

  final double fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      letterSpacing: fontSize * 0.18,
      color: color ?? AppColors.textPrimary,
      height: 1.0,
    );

    if (color != null) {
      return Text('LUMA', style: style);
    }

    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) =>
          AppColors.brandGradient.createShader(bounds),
      child: Text('LUMA', style: style),
    );
  }
}
