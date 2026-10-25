import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../features/catalog/domain/media_item.dart';
import '../theme/app_colors.dart';
import 'local_image.dart';

/// Обложка контента.
///
/// Если у элемента есть сетевая картинка (например, из Genius), она плавно
/// проявляется поверх фирменной процедурной подложки. Подложка рисуется кодом
/// на основе [`MediaItem.seed`], поэтому обложка видна мгновенно и остаётся
/// на месте, если изображение не загрузилось.
class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.item,
    this.borderRadius = 22,
    this.showMonogram = true,
  });

  final MediaItem item;
  final double borderRadius;
  final bool showMonogram;

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.imageUrl;

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius.r),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _ArtworkPainter(
                accent: item.category.accent,
                seed: item.seed,
                monogram: showMonogram && imageUrl == null
                    ? item.title.substring(0, 1).toUpperCase()
                    : null,
                isMusic: item.category == MediaCategory.music,
              ),
              child: const SizedBox.expand(),
            ),
            if (imageUrl != null) ...[
              _RemoteArtwork(url: imageUrl),
              // Затемнение снизу — улучшает читаемость подписей поверх фото.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0x8C0A0A0F)],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Обложка трека: сетевая картинка или файл из каталога приложения.
///
/// Пока картинка грузится (или если она недоступна), видна процедурная
/// подложка — поэтому обложка никогда не «мигает» пустотой.
class _RemoteArtwork extends StatelessWidget {
  const _RemoteArtwork({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    // Обложка импортированного трека лежит на устройстве, поэтому
    // подгружается как локальный файл — сеть для неё не нужна.
    final local = localImageProvider(url);

    return Image(
      image: local ?? NetworkImage(url),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          child: child,
        );
      },
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    );
  }
}

class _ArtworkPainter extends CustomPainter {
  _ArtworkPainter({
    required this.accent,
    required this.seed,
    required this.monogram,
    required this.isMusic,
  });

  final Color accent;
  final int seed;
  final String? monogram;
  final bool isMusic;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final random = math.Random(seed);

    // Базовый градиент от акцента раздела к глубокому фону.
    final dark = Color.lerp(AppColors.ink, accent, 0.35)!;
    final mid = Color.lerp(accent, Colors.white, 0.12)!;
    final angle = random.nextDouble() * math.pi;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [dark, mid],
          transform: GradientRotation(angle),
        ).createShader(rect),
    );

    _paintPattern(canvas, size, random);
    _paintMonogram(canvas, size);

    // Затемнение снизу — улучшает читаемость подписей поверх обложки.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.center,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            AppColors.ink.withValues(alpha: 0.55),
          ],
        ).createShader(rect),
    );
  }

  void _paintPattern(Canvas canvas, Size size, math.Random random) {
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.012;

    final variant = random.nextInt(3);
    final center = Offset(
      size.width * (0.25 + random.nextDouble() * 0.5),
      size.height * (0.25 + random.nextDouble() * 0.5),
    );

    switch (variant) {
      case 0:
        // Концентрические волны — отсылка к звуку и движению.
        for (var i = 1; i <= 7; i++) {
          canvas.drawCircle(center, size.shortestSide * 0.09 * i, linePaint);
        }
      case 1:
        // Диагональная штриховка.
        final step = size.shortestSide * 0.11;
        for (var x = -size.height; x < size.width; x += step) {
          canvas.drawLine(
            Offset(x, 0),
            Offset(x + size.height, size.height),
            linePaint,
          );
        }
      default:
        // Сетка точек.
        final step = size.shortestSide * 0.14;
        final dot = Paint()..color = Colors.white.withValues(alpha: 0.14);
        for (var x = step / 2; x < size.width; x += step) {
          for (var y = step / 2; y < size.height; y += step) {
            canvas.drawCircle(Offset(x, y), size.shortestSide * 0.016, dot);
          }
        }
    }

    if (isMusic) {
      _paintEqualizer(canvas, size);
    }
  }

  /// Мини-эквалайзер в правом нижнем углу обложек музыки.
  void _paintEqualizer(Canvas canvas, Size size) {
    final barPaint = Paint()..color = Colors.white.withValues(alpha: 0.35);
    final barWidth = size.shortestSide * 0.055;
    final baseY = size.height * 0.86;
    final heights = [0.16, 0.30, 0.22, 0.36, 0.18];

    for (var i = 0; i < heights.length; i++) {
      final x = size.width * 0.12 + i * barWidth * 1.7;
      final h = size.height * heights[i];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, baseY - h, barWidth, h),
          Radius.circular(barWidth / 2),
        ),
        barPaint,
      );
    }
  }

  void _paintMonogram(Canvas canvas, Size size) {
    final text = monogram;
    if (text == null) return;

    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size.height * 0.62,
          fontWeight: FontWeight.w900,
          color: Colors.white.withValues(alpha: 0.16),
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    painter.paint(
      canvas,
      Offset(
        size.width - painter.width * 0.92,
        size.height - painter.height * 0.92,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _ArtworkPainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.accent != accent ||
      oldDelegate.monogram != monogram;
}
