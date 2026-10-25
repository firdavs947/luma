import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Обёртка, добавляющая тактильный «отклик» нажатия.
///
/// Используется для карточек и кнопок: элемент мягко сжимается и
/// возвращается в исходное состояние. Анимация выполняется на GPU-слое
/// и не вызывает перестройку дерева.
class AnimatedTap extends StatefulWidget {
  const AnimatedTap({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.96,
    this.duration = const Duration(milliseconds: 140),
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final Duration duration;
  final BorderRadius? borderRadius;

  @override
  State<AnimatedTap> createState() => _AnimatedTapState();
}

class _AnimatedTapState extends State<AnimatedTap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    reverseDuration: const Duration(milliseconds: 220),
  );

  late final Animation<double> _scale = Tween<double>(
    begin: 1,
    end: widget.scale,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setPressed(bool pressed) {
    if (widget.onTap == null && widget.onLongPress == null) return;
    if (pressed) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: ScaleTransition(
          scale: _scale,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Каскадное появление элемента: прозрачность + сдвиг по вертикали.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 620),
    this.offset = 26,
    this.curve = Curves.easeOutExpo,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;
  final Curve curve;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  late final Animation<double> _animation =
      CurvedAnimation(parent: _controller, curve: widget.curve);

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final value = _animation.value;
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - value)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Лёгкий «подъём» элемента при наведении указателя.
///
/// Обратная связь как в настольных музыкальных клиентах: карточка мягко
/// увеличивается, приподнимается и получает мягкую тень. На тач-устройствах
/// наведения не бывает, поэтому эффект просто не срабатывает и не мешает
/// жестам.
class HoverLift extends StatefulWidget {
  const HoverLift({
    super.key,
    required this.child,
    this.scale = 1.035,
    this.lift = 4,
    this.duration = const Duration(milliseconds: 190),
    this.borderRadius = 22,
    this.shadow = false,
  });

  final Widget child;

  /// Во сколько раз увеличивается элемент под курсором.
  final double scale;

  /// На сколько логических пикселей карточка приподнимается под курсором.
  final double lift;
  final Duration duration;

  /// Радиус скругления для тени: форма тени повторяет форму карточки.
  final double borderRadius;

  /// Показывать ли тень под курсором.
  final bool shadow;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: AnimatedScale(
        scale: _hovered ? widget.scale : 1,
        duration: widget.duration,
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: widget.duration,
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(
            0,
            _hovered ? -widget.lift : 0,
            0,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            boxShadow: widget.shadow && _hovered
                ? const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 26,
                      spreadRadius: -4,
                      offset: Offset(0, 12),
                    ),
                  ]
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Фирменный индикатор загрузки LUMA.
///
/// Две вращающиеся в противоположные стороны дуги читаются как «живой»
/// процесс загрузки, в отличие от стандартного кружка Material: индикатор
/// появляется в блоках с подгружаемым контентом и в видеоплеере.
class LumaLoader extends StatefulWidget {
  const LumaLoader({
    super.key,
    this.size = 36,
    this.color = AppColors.secondary,
    this.label,
  });

  /// Диаметр индикатора.
  final double size;
  final Color color;

  /// Подпись под индикатором; `null` — индикатор без текста.
  final String? label;

  @override
  State<LumaLoader> createState() => _LumaLoaderState();
}

class _LumaLoaderState extends State<LumaLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loader = CustomPaint(
      size: Size.square(widget.size),
      painter: _LumaLoaderPainter(
        progress: _controller,
        color: widget.color,
        stroke: widget.size * 0.1,
      ),
    );

    final label = widget.label;
    if (label == null) return loader;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        loader,
        const SizedBox(height: 12),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

class _LumaLoaderPainter extends CustomPainter {
  _LumaLoaderPainter({
    required this.progress,
    required this.color,
    required this.stroke,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = (size.shortestSide - stroke) / 2;
    final inner = outer - stroke * 2.1;

    final spin = progress.value * 2 * math.pi;

    canvas.save();
    canvas.translate(center.dx, center.dy);

    // Внешняя дуга: две трети оборота, вращается по часовой стрелке.
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: outer),
      spin,
      math.pi * 1.35,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: [color.withValues(alpha: 0.05), color],
          transform: GradientRotation(spin),
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: outer)),
    );

    // Внутренняя дуга: короче и в противоположную сторону — движение
    // получается «живым», а не механическим.
    if (inner > 2) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: inner),
        -spin * 1.6,
        math.pi * 0.8,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 0.8
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: 0.35),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LumaLoaderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.stroke != stroke;
}

/// Плейсхолдер загрузки с эффектом «шиммера».
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({
    super.key,
    this.width,
    this.height = 16,
    this.radius = 12,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final shift = _controller.value * 2 - 1;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 - shift, 0),
              end: Alignment(1 - shift, 0),
              colors: const [
                AppColors.surfaceHigh,
                AppColors.outline,
                AppColors.surfaceHigh,
              ],
            ),
          ),
        );
      },
    );
  }
}
