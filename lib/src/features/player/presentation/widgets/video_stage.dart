import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/artwork.dart';
import '../../../../core/widgets/motion.dart';
import '../../../catalog/domain/media_item.dart';

/// Видеосцена плеера: настоящий видеокадр, оверлей управления и вход
/// в полноэкранный режим.
///
/// Виджет не владеет контроллером: он создаётся и уничтожается на экране
/// плеера, поэтому переключение между обычным и полноэкранным режимом не
/// прерывает поток — позиция и громкость сохраняются.
class VideoStage extends StatelessWidget {
  const VideoStage({
    super.key,
    required this.controller,
    required this.item,
    required this.qualityLabel,
    required this.loading,
    required this.failed,
    required this.playing,
    required this.showControls,
    required this.onTogglePlay,
    required this.onToggleControls,
    required this.onRetry,
    required this.onOpenFullscreen,
  });

  /// Контроллер потока; `null` — видео ещё не открыто.
  final VideoPlayerController? controller;

  /// Элемент каталога: из него берётся постер для заглушки.
  final MediaItem item;

  /// Подпись выбранного качества («720p»); `null` — качество неизвестно.
  final String? qualityLabel;

  /// Идёт открытие потока.
  final bool loading;

  /// Поток не удалось открыть.
  final bool failed;

  /// Идёт воспроизведение.
  final bool playing;

  /// Виден ли оверлей управления поверх кадра.
  final bool showControls;

  final VoidCallback onTogglePlay;
  final VoidCallback onToggleControls;
  final VoidCallback onRetry;
  final VoidCallback onOpenFullscreen;

  bool get _ready => controller != null && controller!.value.isInitialized;

  @override
  Widget build(BuildContext context) {
    final video = controller;
    final aspect = _ready && video!.value.aspectRatio > 0
        ? video.value.aspectRatio
        : 16 / 9;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Center(
        child: AspectRatio(
          aspectRatio: aspect,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24.r),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Кадр фильма, а до его готовности — постер: пустого
                // прямоугольника пользователь не видит ни в один момент.
                if (_ready && !failed)
                  VideoPlayer(video!)
                else
                  Artwork(item: item, borderRadius: 0, showMonogram: false),

                // Тап по кадру показывает и прячет оверлей.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onToggleControls,
                ),

                if (!failed)
                  IgnorePointer(
                    ignoring: !showControls,
                    child: AnimatedOpacity(
                      opacity: showControls ? 1 : 0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0xB3000000),
                                  Color(0x1A000000),
                                  Color(0xB3000000),
                                ],
                                stops: [0, 0.45, 1],
                              ),
                            ),
                          ),
                          Center(
                            child: _StagePlayButton(
                              playing: playing,
                              accent: item.category.accent,
                              enabled: _ready && !loading,
                              onTap: onTogglePlay,
                            ),
                          ),
                          Positioned(
                            right: 12.w,
                            bottom: 12.h,
                            child: _GlassIconButton(
                              icon: Icons.fullscreen_rounded,
                              tooltip: 'На весь экран',
                              onTap: _ready ? onOpenFullscreen : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Бейдж качества: видно, под какую скорость соединения
                // подобран битрейт.
                Positioned(
                  left: 12.w,
                  top: 12.h,
                  child: _QualityBadge(label: qualityLabel ?? 'LUMA'),
                ),

                if (loading || (!_ready && !failed))
                  const Center(child: LumaLoader(size: 46)),

                if (failed && !loading)
                  Center(child: _FailureState(onRetry: onRetry)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Кнопка Play/Pause в центре кадра.
class _StagePlayButton extends StatelessWidget {
  const _StagePlayButton({
    required this.playing,
    required this.accent,
    required this.enabled,
    required this.onTap,
  });

  final bool playing;
  final Color accent;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      scale: playing ? 0.94 : 1,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 74.r,
          height: 74.r,
          decoration: BoxDecoration(
            color: AppColors.ink.withValues(alpha: 0.55),
            shape: BoxShape.circle,
            border: Border.all(color: accent.withValues(alpha: 0.6)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.28),
                blurRadius: 26.r,
                spreadRadius: -4.r,
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              key: ValueKey(playing),
              color: Colors.white,
              size: 36.r,
            ),
          ),
        ),
      ),
    );
  }
}

/// Круглая полупрозрачная кнопка поверх кадра.
class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 38.r,
          height: 38.r,
          decoration: BoxDecoration(
            color: AppColors.ink.withValues(alpha: 0.5),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
          child: Icon(
            icon,
            size: 21.r,
            color: onTap == null ? Colors.white38 : Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Бейдж выбранного качества в углу кадра.
class _QualityBadge extends StatelessWidget {
  const _QualityBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5.sp,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Состояние «поток недоступен» с повторной попыткой.
class _FailureState extends StatelessWidget {
  const _FailureState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
      margin: EdgeInsets.symmetric(horizontal: 20.w),
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.45)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 34.r,
            color: AppColors.error,
          ),
          SizedBox(height: 10.h),
          Text(
            'Поток недоступен',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            'Источник не отдал видеофайл. Проверьте соединение и повторите.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.sp,
              height: 1.4,
              color: AppColors.textMuted,
            ),
          ),
          SizedBox(height: 12.h),
          FilledButton.icon(
            onPressed: onRetry,
            icon: Icon(Icons.refresh_rounded, size: 18.r),
            label: const Text('Повторить'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              minimumSize: Size(0, 42.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14.r),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Полноэкранный режим видео.
///
/// Открывается отдельным маршрутом и получает тот же
/// [VideoPlayerController], поэтому переключение режима не прерывает поток:
/// позиция, громкость и состояние воспроизведения сохраняются. Выход возможен
/// и кнопкой на панели, и системной кнопкой «назад» — оба пути возвращают
/// ориентацию и системные панели в исходное состояние.
class FullscreenVideoPage extends StatefulWidget {
  const FullscreenVideoPage({
    super.key,
    required this.controller,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onVolumeChanged,
    required this.onToggleMute,
    required this.onTogglePlay,
  });

  final VideoPlayerController controller;
  final String title;
  final String subtitle;
  final Color accent;

  /// Громкость берётся из контроллера: это единственный источник правды,
  /// иначе ползунок и иконка показывали бы значение на момент открытия
  /// полноэкранного режима, а не текущее.
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleMute;
  final VoidCallback onTogglePlay;

  @override
  State<FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<FullscreenVideoPage> {
  bool _controlsVisible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();

    // Иммерсивный режим на время просмотра: кадр занимает весь экран.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    widget.controller.addListener(_onTick);
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.removeListener(_onTick);

    // Возвращаем интерфейс приложения в исходное состояние: иначе выход
    // из полноэкранного режима оставил бы телефон в ландшафте без панелей.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && widget.controller.value.isPlaying) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _exit() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.value;
    final duration = value.duration;
    final position = value.position;
    final total = duration.inMilliseconds;
    final progress = total <= 0
        ? 0.0
        : (position.inMilliseconds / total).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: value.aspectRatio > 0 ? value.aspectRatio : 16 / 9,
              child: VideoPlayer(widget.controller),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
          ),
          IgnorePointer(
            ignoring: !_controlsVisible,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xCC000000),
                      Color(0x33000000),
                      Color(0xCC000000),
                    ],
                    stops: [0, 0.5, 1],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      _buildTopBar(),
                      const Spacer(),
                      _buildBottomBar(progress, position, duration),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: _exit,
            tooltip: 'Выйти из полноэкранного режима',
            icon: const Icon(
              Icons.fullscreen_exit_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(double progress, Duration position, Duration duration) {
    final playing = widget.controller.value.isPlaying;
    // Громкость читаем из контроллера на каждой перерисовке: он общий с
    // экраном плеера, поэтому ползунок и иконка всегда отражают текущее
    // состояние, а не значение на момент открытия полноэкранного режима.
    final volume = widget.controller.value.volume;
    final muted = volume == 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                _formatTime(position),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    activeTrackColor: widget.accent,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                    overlayColor: widget.accent.withValues(alpha: 0.2),
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 7,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 16,
                    ),
                  ),
                  child: Slider(
                    value: progress,
                    onChanged: (value) {
                      final total = duration.inMilliseconds;
                      if (total <= 0) return;
                      widget.controller.seekTo(
                        Duration(milliseconds: (total * value).round()),
                      );
                    },
                  ),
                ),
              ),
              Text(
                _formatTime(duration),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              IconButton(
                onPressed: () {
                  widget.onTogglePlay();
                  _scheduleHide();
                },
                tooltip: playing ? 'Пауза' : 'Воспроизвести',
                icon: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: () {
                  widget.onToggleMute();
                  _scheduleHide();
                },
                tooltip: muted ? 'Включить звук' : 'Выключить звук',
                icon: Icon(
                  _volumeIcon(muted, volume),
                  color: Colors.white,
                  size: 24,
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(
                    value: volume,
                    onChanged: (value) {
                      widget.onVolumeChanged(value);
                      _scheduleHide();
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Иконка громкости по состоянию звука.
IconData _volumeIcon(bool muted, double volume) {
  if (muted || volume == 0) return Icons.volume_off_rounded;
  if (volume < 0.5) return Icons.volume_down_rounded;
  return Icons.volume_up_rounded;
}

/// Форматирование времени в формате `ч:мм:сс` или `мм:сс`.
String _formatTime(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
