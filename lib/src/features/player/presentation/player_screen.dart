import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart' as bg;
import 'package:video_player/video_player.dart';

import '../../../core/audio/audio_engine.dart';
import '../../../core/audio/track_stream_resolver.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/artwork.dart';
import '../../catalog/domain/media_item.dart';
import '../../catalog/domain/video_source.dart';
import '../../catalog/presentation/bloc/catalog_cubit.dart';
import 'widgets/video_stage.dart';

/// Экран воспроизведения.
///
/// Музыка играет настоящий звук через [AudioPlayer]. Сначала берётся готовое
/// превью из самого элемента (локальный файл или ссылка источника). Если его
/// нет — Genius отдаёт только метаданные, — запись подбирается у
/// стриминговых провайдеров через [TrackStreamResolver]. И лишь когда не
/// нашлось ничего, включается локальный демо-фрагмент LUMA: звук и счётчик
/// времени работают всегда.
///
/// Видео играет встроенный видеоплеер: поток разрешается через
/// [VideoSource], качество подбирается под скорость соединения, а управление
/// повторяет музыкальную часть — пауза, перемотка по шкале, громкость с
/// отключением звука и полноэкранный режим.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.item, this.queue = const []});

  /// Элемент, который открывается первым.
  final MediaItem item;

  /// Очередь воспроизведения: треклист альбома или подборка.
  final List<MediaItem> queue;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with TickerProviderStateMixin {
  /// Ход имитации: используется только там, где реального звука нет.
  late final AnimationController _progressController;
  late final AnimationController _pulseController;
  late final AnimationController _artworkController;

  /// Используем глобальный плеер из AudioEngine для фонового воспроизведения.
  AudioPlayer get _audio => AudioEngine.player;

  /// Текущая позиция для интерфейса.
  ///
  /// Обновляется потоком плеера, поэтому счётчик времени идёт в реальном
  /// времени сразу после нажатия Play, а не только после паузы.
  final ValueNotifier<Duration> _elapsed = ValueNotifier(Duration.zero);

  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;

  late List<MediaItem> _queue;
  int _index = 0;

  bool _playing = false;
  bool _shuffle = false;
  bool _repeat = false;
  double _volume = 0.7;

  /// Звук выключен кнопкой mute (а не нулевой громкостью шкалы).
  bool _muted = false;

  /// Контроллер видеопотока. Создаётся только для видеоэлементов и
  /// уничтожается при переходе к аудио или при закрытии экрана.
  VideoPlayerController? _video;

  /// Разрешённый поток текущего видео: из него берутся варианты качества.
  VideoStream? _videoStream;

  /// Вариант качества, который играет сейчас.
  VideoVariant? _selectedVariant;

  /// Поток не удалось открыть.
  bool _videoFailed = false;

  /// Виден ли оверлей управления поверх видеокадра.
  bool _controlsVisible = true;

  /// Таймер автоскрытия оверлея во время воспроизведения.
  Timer? _controlsTimer;

  /// Длительность текущего источника.
  Duration? _duration;

  /// Плеер не смог открыть ни превью, ни демо-фрагмент.
  bool _audioFailed = false;

  /// Играет локальный демо-фрагмент вместо превью из источника.
  bool _usingDemo = false;

  /// Играет короткий ознакомительный фрагмент вместо полной записи.
  bool _usingFragment = false;

  /// Идёт ли сейчас поиск или загрузка аудиопотока.
  bool _isLoading = false;

  MediaItem get _item => _queue[_index];

  /// Идёт ли воспроизведение через аудиоплеер (а не имитация).
  bool get _usesPlayer => !_item.isVideo && !_audioFailed;

  /// Идёт ли воспроизведение через видеоплеер.
  bool get _usesVideo => _video != null && !_videoFailed;

  /// Подпись выбранного качества для бейджа на кадре.
  String? get _qualityLabel => _selectedVariant?.label;

  @override
  void initState() {
    super.initState();

    _queue = _buildQueue();

    _progressController = AnimationController(
      vsync: this,
      duration: _parseDuration(_item.durationLabel),
    )..addListener(_syncImitationTime);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _artworkController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    );

    _playerStateSub = _audio.playerStateStream.listen(_onPlayerState);
    _positionSub = _audio.positionStream.listen((position) {
      if (mounted) _elapsed.value = position;
    });
    _durationSub = _audio.durationStream.listen((duration) {
      if (duration != null && mounted) setState(() => _duration = duration);
    });

    _loadCurrent();
  }

  /// Собирает очередь: текущий элемент сохраняет своё место в треклисте.
  ///
  /// Если очередь не передана явно — плеер открыт из мини-плеера поверх
  /// модальной шторки, — она собирается из каталога: подборка того же
  /// раздела, где нашёлся текущий элемент. Без этого очередь состояла бы из
  /// одной позиции, и кнопки «Следующий»/«Предыдущий» молча ничего не делали.
  List<MediaItem> _buildQueue() {
    final explicit = widget.queue;
    if (explicit.isNotEmpty) {
      final index = explicit.indexWhere((item) => item.id == widget.item.id);
      // Открытый элемент обязан быть первым в очереди, даже если переданная
      // подборка его не содержит: иначе плеер играл бы чужую запись.
      if (index == -1) return [widget.item, ...explicit];
      _index = index;
      return [...explicit];
    }

    final catalog = context
        .read<CatalogCubit>()
        .state
        .items
        .where(
          (item) =>
              item.category == widget.item.category && !item.opensCollection,
        )
        .toList();

    // Текущий элемент остаётся в очереди первым, даже если каталог ещё не
    // успел его загрузить: плеер в любом случае должен играть то, что открыли.
    final index = catalog.indexWhere((item) => item.id == widget.item.id);
    if (index == -1) return [widget.item, ...catalog];

    _index = index;
    return catalog;
  }

  /// Загружает и запускает текущий элемент очереди.
  ///
  /// Порядок попыток: готовое превью → запись у стриминговых провайдеров →
  /// локальный демо-фрагмент → имитация. Так звук есть всегда, даже если
  /// источник отдал только метаданные.
  Future<void> _loadCurrent() async {
    final item = _item;

    setState(() => _isLoading = true);

    if (item.isVideo) {
      await _openVideo(item);
      if (!mounted) return;
      setState(() => _isLoading = false);
      _refresh();
      return;
    }

    // Перешли с видео на музыку — кадр и звуковая дорожка больше не нужны.
    _disposeVideo();

    // Если этот же трек уже играет (например, мы вернулись с домашнего экрана),
    // не прерываем его и просто подхватываем состояние.
    final source = _audio.audioSource;
    final currentTag = source is IndexedAudioSource ? source.tag : null;
    if (currentTag is bg.MediaItem && currentTag.id == item.id) {
      _duration = _audio.duration;
      _elapsed.value = _audio.position;
      _playing = _audio.playing;
      if (_playing) {
        _artworkController.repeat();
      }
      setState(() => _isLoading = false);
      _refresh();
      return;
    }

    // Локальная библиотека и каталог со ссылкой на превью играют сразу.
    final previewUrl = item.previewUrl;
    if (previewUrl != null && previewUrl.isNotEmpty) {
      if (await _open(
        AudioEngine.sourceFor(previewUrl, tag: _notificationItem(item)),
      )) {
        _usingDemo = false;
        _usingFragment = false;
        setState(() => _isLoading = false);
        _refresh();
        return;
      }
    }

    // Genius отдаёт только метаданные, поэтому запись ищется у провайдеров,
    // которые действительно транслируют звук.
    if (await _openResolved(item)) {
      setState(() => _isLoading = false);
      _refresh();
      return;
    }

    // Согласно требованию: если трек не найден или он короче 30 секунд,
    // мы исключаем его воспроизведение полностью (не играем даже демо).
    _audioFailed = true;
    _playing = false;
    setState(() => _isLoading = false);
    _refresh();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Трек "${item.title}" не найден или слишком короткий'),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 2),
        ),
      );

      // Если есть очередь, пробуем следующий трек через 2 секунды.
      if (_index + 1 < _queue.length) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _switchTo(_index + 1);
        });
      }
    }
  }

  // ─────────────────────────── Видеоплеер ───────────────────────────

  /// Разрешает поток видео и запускает воспроизведение.
  ///
  /// Качество выбирает сам источник: перед выдачей он замеряет пропускную
  /// способность канала и берёт подходящий по битрейту файл. Если поток
  /// недоступен, сцена показывает кнопку повторной попытки, а не пустой кадр.
  Future<void> _openVideo(MediaItem item) async {
    _disposeVideo();
    _videoStream = null;
    _selectedVariant = null;
    _videoFailed = false;
    _duration = null;
    _elapsed.value = Duration.zero;

    try {
      final stream = await context.read<VideoSource>().resolveStream(item);
      if (!mounted) return;

      if (stream == null || stream.url.isEmpty) {
        _failVideo(item);
        return;
      }

      _videoStream = stream;
      _selectedVariant = _variantFor(stream);
      await _startController();
    } catch (_) {
      // Сбой платформы, отсутствие декодера и сетевые ошибки приводят к
      // разным типам исключений, поэтому ловим их все одинаково.
      if (!mounted) return;
      _failVideo(item);
    }
  }

  /// Вариант качества, соответствующий ссылке по умолчанию.
  VideoVariant? _variantFor(VideoStream stream) {
    for (final variant in stream.variants) {
      if (variant.url == stream.url) return variant;
    }
    return stream.variants.isEmpty ? null : stream.variants.first;
  }

  /// Создаёт контроллер для выбранного варианта и запускает его.
  Future<void> _startController({
    Duration startAt = Duration.zero,
    bool autoplay = true,
  }) async {
    final url = _selectedVariant?.url ?? _videoStream?.url;
    if (url == null || url.isEmpty) {
      _failVideo(_item);
      return;
    }

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _video = controller;
    controller.addListener(_onVideoTick);

    try {
      await controller.initialize();
    } catch (_) {
      if (identical(_video, controller)) _disposeVideo();
      if (mounted) _failVideo(_item);
      return;
    }

    if (!mounted) {
      await controller.dispose();
      return;
    }

    await controller.setVolume(_muted ? 0 : _volume);
    if (startAt > Duration.zero) await controller.seekTo(startAt);

    _duration = controller.value.duration;
    _elapsed.value = controller.value.position;
    _playing = autoplay;
    setState(() {});

    if (autoplay) {
      await controller.play();
      _startControlsTimer();
    }
  }

  /// Переключает качество, сохраняя позицию и состояние воспроизведения.
  Future<void> _switchVariant(VideoVariant variant) async {
    if (variant.url == _selectedVariant?.url) return;

    final controller = _video;
    if (controller == null || !controller.value.isInitialized) return;

    final position = controller.value.position;
    final wasPlaying = controller.value.isPlaying;

    setState(() {
      _isLoading = true;
      _selectedVariant = variant;
    });

    await _startController(startAt: position, autoplay: wasPlaying);
    if (mounted) setState(() => _isLoading = false);
  }

  /// Сообщает, что поток открыть не удалось.
  void _failVideo(MediaItem item) {
    if (!mounted) return;

    setState(() {
      _videoFailed = true;
      _playing = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Не удалось открыть «${item.title}»: поток недоступен'),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Освобождает видеоконтроллер и таймер скрытия оверлея.
  void _disposeVideo() {
    _controlsTimer?.cancel();
    _controlsTimer = null;

    final controller = _video;
    _video = null;
    if (controller == null) return;

    controller.removeListener(_onVideoTick);
    unawaited(controller.dispose());
  }

  /// Синхронизирует интерфейс с состоянием видеоплеера.
  void _onVideoTick() {
    final controller = _video;
    if (controller == null || !mounted) return;

    final value = controller.value;

    if (value.hasError) {
      if (!_videoFailed) {
        setState(() {
          _videoFailed = true;
          _playing = false;
        });
      }
      return;
    }

    _elapsed.value = value.position;
    if (value.duration > Duration.zero) _duration = value.duration;

    if (value.isCompleted) {
      _controlsTimer?.cancel();
      if (_repeat) {
        unawaited(controller.seekTo(Duration.zero));
        unawaited(controller.play());
        return;
      }
      // Кадр закончился — идём дальше по очереди, как в обычном плеере.
      if (_index + 1 < _queue.length) {
        unawaited(_switchTo(_index + 1));
        return;
      }
      if (_playing) setState(() => _playing = false);
      return;
    }

    if (value.isPlaying != _playing) {
      setState(() => _playing = value.isPlaying);
    }
  }

  /// Показывает оверлей и перезапускает таймер его автоскрытия.
  void _showControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _startControlsTimer();
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _startControlsTimer();
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _playing) setState(() => _controlsVisible = false);
    });
  }

  /// Открывает полноэкранный режим поверх плеера.
  ///
  /// Тот же контроллер передаётся новому маршруту, поэтому кадр продолжает
  /// играть без перезагрузки, а выход возвращает телефон в портрет.
  void _openFullscreen() {
    final controller = _video;
    if (controller == null || !controller.value.isInitialized) return;

    _controlsTimer?.cancel();
    if (_controlsVisible) setState(() => _controlsVisible = false);

    final item = _item;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (context, animation, secondaryAnimation) =>
            FullscreenVideoPage(
              controller: controller,
              title: item.title,
              subtitle: item.subtitle,
              accent: item.category.accent,
              onVolumeChanged: _setVolume,
              onToggleMute: _toggleMute,
              onTogglePlay: _togglePlay,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  /// Применяет текущую громкость и состояние mute к активному плееру.
  void _applyVolume() {
    final effective = _muted ? 0.0 : _volume;
    if (_usesVideo) unawaited(_video!.setVolume(effective));
    if (_usesPlayer) unawaited(_audio.setVolume(effective));
  }

  /// Выключает и включает звук, сохраняя уровень громкости.
  void _toggleMute() {
    setState(() {
      _muted = !_muted;
      // Если шкала стояла на нуле, включаем звук на комфортном уровне:
      // иначе «включение» не дало бы слышимого результата.
      if (!_muted && _volume == 0) _volume = 0.7;
    });
    _applyVolume();
  }

  /// Ищет запись у внешних провайдеров и открывает её.
  ///
  /// Возвращает `false`, если подходящей записи нет или она не открылась —
  /// тогда вызывающий код переходит к следующему шагу.
  Future<bool> _openResolved(MediaItem item) async {
    final stream = await context.read<TrackStreamResolver>().resolve(
      title: item.title,
      artist: item.subtitle,
    );
    if (stream == null || !mounted) return false;

    if (!await _open(
      AudioEngine.sourceFor(stream.url, tag: _notificationItem(item)),
    )) {
      return false;
    }

    _usingDemo = false;
    _usingFragment = !stream.isFullLength;
    return true;
  }

  /// Метаданные карточки в системном плеере телефона.
  ///
  /// Их видит пользователь в области уведомлений и на экране блокировки,
  /// поэтому обложка, название и исполнитель совпадают с экраном плеера.
  bg.MediaItem _notificationItem(MediaItem item) => bg.MediaItem(
    id: item.id,
    title: item.title,
    artist: item.subtitle,
    album: item.category.label,
    artUri: _artUri(item.imageUrl),
  );

  /// Обложка как адрес для системного плеера: сеть или файл на устройстве.
  static Uri? _artUri(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return null;
    final uri = Uri.tryParse(imageUrl);
    if (uri == null) return null;
    return const {'http', 'https', 'file'}.contains(uri.scheme) ? uri : null;
  }

  /// Перерисовывает экран, если он ещё в дереве.
  void _refresh() {
    if (mounted) setState(() {});
  }

  /// Открывает источник и запускает воспроизведение.
  ///
  /// Возвращает `false`, если источник недоступен.
  Future<bool> _open(AudioSource source) async {
    try {
      final duration = await _audio.setAudioSource(source);
      if (!mounted) return true;

      _duration = duration;
      _elapsed.value = Duration.zero;
      await _audio.setVolume(_muted ? 0 : _volume);
      // play() завершается только по окончании трека, поэтому не ждём его.
      unawaited(_audio.play());
      return true;
    } on Exception {
      return false;
    }
  }

  /// Переносит ход анимации в счётчик времени (режим имитации).
  void _syncImitationTime() {
    final total = _progressController.duration;
    if (total == null) return;
    _elapsed.value = Duration(
      milliseconds: (total.inMilliseconds * _progressController.value).round(),
    );
  }

  void _onPlayerState(PlayerState state) {
    if (!mounted || _item.isVideo) return;

    if (state.processingState == ProcessingState.completed) {
      _artworkController.stop();

      if (_repeat) {
        unawaited(_audio.seek(Duration.zero));
        unawaited(_audio.play());
        return;
      }

      // Трек закончился — идём дальше по очереди, как в обычном плеере.
      if (_index + 1 < _queue.length) {
        unawaited(_switchTo(_index + 1));
        return;
      }

      _elapsed.value = _duration ?? Duration.zero;
      if (_playing) setState(() => _playing = false);
      return;
    }

    if (!_usesPlayer) return;

    final playing = state.playing;
    if (playing) {
      if (!_artworkController.isAnimating) _artworkController.repeat();
    } else {
      _artworkController.stop();
    }
    if (playing != _playing) setState(() => _playing = playing);
  }

  /// Переключает трек внутри очереди.
  Future<void> _switchTo(int index) async {
    if (index < 0 || index >= _queue.length) return;

    await _audio.stop();
    _disposeVideo();
    _progressController.stop();
    _artworkController.stop();

    setState(() {
      _index = index;
      _duration = null;
      _elapsed.value = Duration.zero;
      _audioFailed = false;
      _usingDemo = false;
      _usingFragment = false;
      _playing = false;
    });

    await _loadCurrent();
  }

  /// Переход к соседней позиции очереди с закольцовыванием.
  ///
  /// Кнопки «Следующий» и «Предыдущий» продолжают работать на границах
  /// списка и не «залипают» на последнем треке: из конца очередь переходит
  /// в начало и наоборот.
  void _skip(int step) {
    if (_queue.length < 2) return;
    _switchTo((_index + step) % _queue.length);
  }

  /// Название следующего трека очереди — подсказка под обложкой.
  String? get _nextTitle {
    if (_queue.length < 2) return null;
    return _queue[(_index + 1) % _queue.length].title;
  }

  Future<void> _togglePlay() async {
    _showControls();

    // Видео управляется собственным контроллером.
    if (_usesVideo) {
      final controller = _video!;
      if (controller.value.isPlaying) {
        await controller.pause();
        _controlsTimer?.cancel();
        if (mounted) setState(() => _controlsVisible = true);
        return;
      }

      // После окончания кадра позиция стоит в конце — начинаем сначала.
      if (controller.value.isCompleted) {
        await controller.seekTo(Duration.zero);
      }
      await controller.play();
      _startControlsTimer();
      return;
    }

    // Недоступный трек не воспроизводим вовсе — не запускаем немую имитацию.
    if (_audioFailed) return;

    if (_usesPlayer) {
      // После окончания трека just_audio оставляет `playing == true`, поэтому
      // проверяем завершение первым: иначе кнопка Play вызывала бы pause()
      // и воспроизведение нельзя было запустить повторно.
      if (_audio.processingState == ProcessingState.completed) {
        await _audio.seek(Duration.zero);
        _elapsed.value = Duration.zero;
        unawaited(_audio.play());
        return;
      }

      if (_audio.playing) {
        await _audio.pause();
      } else {
        unawaited(_audio.play());
      }
      return;
    }

    setState(() {
      _playing = !_playing;
      if (_playing) {
        _progressController.forward();
        _artworkController.repeat();
      } else {
        _progressController.stop();
        _artworkController.stop();
      }
    });
  }

  void _seekTo(double value) {
    final clamped = value.clamp(0.0, 1.0);
    final total = _duration;
    if (total == null || total.inMilliseconds <= 0) return;

    final target = total * clamped;
    _elapsed.value = target;

    // Видео перематывается собственным контроллером; archive.org отдаёт
    // файлы с поддержкой Range-запросов, поэтому перемотка точная.
    if (_usesVideo) {
      unawaited(_video!.seekTo(target));
      _showControls();
      return;
    }

    if (_usesPlayer) {
      unawaited(_audio.seek(target));
      return;
    }
    _progressController.value = clamped;
  }

  void _shuffleQueue() {
    setState(() {
      _shuffle = !_shuffle;
      if (_shuffle) {
        // Текущий трек остаётся первым, остальные перемешиваются.
        final current = _queue[_index];
        final rest = [..._queue]
          ..removeAt(_index)
          ..shuffle(math.Random());
        _queue = [current, ...rest];
        _index = 0;
      }
    });
  }

  void _toggleRepeat() {
    setState(() => _repeat = !_repeat);
    _audio.setLoopMode(_repeat ? LoopMode.one : LoopMode.off);
  }

  void _setVolume(double value) {
    setState(() {
      _volume = value;
      // Шкала на нуле означает тишину — кнопка mute показывает это состояние.
      _muted = value == 0;
    });
    _applyVolume();
  }

  /// Сохраняем прогресс просмотра в каталоге при выходе с экрана.
  void _persistProgress() {
    context.read<CatalogCubit>().updateProgress(widget.item.id, _progressValue);
  }

  /// Длительность текущего элемента.
  Duration get _total =>
      _duration ?? _progressController.duration ?? const Duration(minutes: 3);

  /// Доля проигранного (0..1) для полосы прогресса.
  double get _progressValue {
    final total = _duration?.inMilliseconds ?? 0;
    if (total <= 0) return 0;
    return (_elapsed.value.inMilliseconds / total).clamp(0.0, 1.0);
  }

  /// Подсказка о том, что за звук играет сейчас.
  String? get _previewNotice {
    if (_item.category != MediaCategory.music) return null;
    if (_audioFailed) {
      return 'Запись недоступна: источник не отдал этот трек. '
          'Переключитесь на другой.';
    }
    if (_usingDemo) {
      return 'Источник не отдал превью — играет демо-фрагмент LUMA.';
    }
    if (_usingFragment) {
      return 'Играет 30-секундный фрагмент: полная запись недоступна.';
    }
    return null;
  }

  /// Подсказка сообщает об ошибке, а не просто информирует.
  bool get _noticeIsError => _audioFailed;

  @override
  void dispose() {
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _elapsed.dispose();
    // Глобальный плеер НЕ удаляется: он должен продолжать играть в фоне.
    // Видеоконтроллер, напротив, освобождается — кадр не нужен вне экрана.
    _disposeVideo();
    _progressController.dispose();
    _pulseController.dispose();
    _artworkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _persistProgress();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(32.r),
                  ),
                  gradient: RadialGradient(
                    center: Alignment(0, -0.75),
                    radius: 1.25,
                    colors: [
                      item.category.accent.withValues(alpha: 0.28),
                      AppColors.ink,
                    ],
                    stops: const [0, 0.62],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  SizedBox(
                    height: 32.h,
                  ), // Значительно подняли элементы для премиального вида
                  Container(
                    width: 48.w, // Еще немного увеличили ручку
                    height: 5.h,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2.5.r),
                    ),
                  ),
                  SizedBox(height: 8.h),
                  _PlayerHeader(
                    item: item,
                    position: _index + 1,
                    total: _queue.length,
                  ),
                  Expanded(
                    child: GestureDetector(
                      // Свайп по обложке — привычный жест музыкальных
                      // сервисов: влево следующий трек, вправо предыдущий.
                      // Для видео жест отключён: случайный свайп по кадру
                      // не должен уводить с фильма.
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragEnd: item.isVideo
                          ? null
                          : (details) {
                              final velocity = details.primaryVelocity ?? 0;
                              if (velocity < -160) _skip(1);
                              if (velocity > 160) _skip(-1);
                            },
                      child: item.isVideo
                          ? VideoStage(
                              controller: _video,
                              item: item,
                              qualityLabel: _qualityLabel,
                              loading: _isLoading,
                              failed: _videoFailed,
                              playing: _playing,
                              showControls: _controlsVisible,
                              onTogglePlay: _togglePlay,
                              onToggleControls: _toggleControls,
                              onRetry: _loadCurrent,
                              onOpenFullscreen: _openFullscreen,
                            )
                          : _AudioStage(
                              item: item,
                              rotation: _artworkController,
                              pulse: _pulseController,
                              playing: _playing,
                              nextTitle: _nextTitle,
                              onNext: () => _skip(1),
                            ),
                    ),
                  ),
                  _buildControls(item),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(MediaItem item) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 18.h),
        child: Column(
          children: [
            // Полоса прогресса и счётчик времени слушают позицию плеера
            // напрямую, поэтому секунды идут сразу после нажатия Play.
            ValueListenableBuilder<Duration>(
              valueListenable: _elapsed,
              builder: (context, elapsed, _) => Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 5.r,
                      activeTrackColor: item.category.accent,
                      inactiveTrackColor: AppColors.surfaceHigh,
                      thumbColor: Colors.white,
                      overlayColor: item.category.accent.withValues(
                        alpha: 0.18,
                      ),
                      thumbShape: RoundSliderThumbShape(
                        enabledThumbRadius: 7.r,
                      ),
                      overlayShape: RoundSliderOverlayShape(
                        overlayRadius: 18.r,
                      ),
                    ),
                    child: Slider(value: _progressValue, onChanged: _seekTo),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatTime(elapsed),
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                      Text(
                        _formatTime(_total),
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: 18.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ToggleButton(
                  icon: Icons.shuffle_rounded,
                  active: _shuffle,
                  onTap: _shuffleQueue,
                  tooltip: 'Перемешать',
                ),
                _ToggleButton(
                  icon: Icons.skip_previous_rounded,
                  size: 34,
                  enabled: _queue.length > 1,
                  onTap: () => _skip(-1),
                  tooltip: 'Предыдущий',
                ),
                _PlayButton(
                  playing: _playing,
                  isLoading: _isLoading,
                  enabled: !_audioFailed,
                  accent: item.category.accent,
                  pulse: _pulseController,
                  onTap: _togglePlay,
                ),
                _ToggleButton(
                  icon: Icons.skip_next_rounded,
                  size: 34,
                  enabled: _queue.length > 1,
                  onTap: () => _skip(1),
                  tooltip: 'Следующий',
                ),
                _ToggleButton(
                  icon: Icons.repeat_rounded,
                  active: _repeat,
                  onTap: _toggleRepeat,
                  tooltip: 'Повтор',
                ),
              ],
            ),
            SizedBox(height: 20.h),
            Row(
              children: [
                // Кнопка mute: выключает звук целиком, не теряя уровень
                // громкости — повторное нажатие возвращает его.
                _MuteButton(muted: _muted, volume: _volume, onTap: _toggleMute),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3.r,
                      activeTrackColor: AppColors.textMuted,
                      inactiveTrackColor: AppColors.surfaceHigh,
                      thumbColor: AppColors.textPrimary,
                      thumbShape: RoundSliderThumbShape(
                        enabledThumbRadius: 5.r,
                      ),
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      value: _muted ? 0 : _volume,
                      onChanged: _setVolume,
                    ),
                  ),
                ),
                Icon(
                  Icons.volume_up_rounded,
                  size: 20.r,
                  color: AppColors.textMuted,
                ),
              ],
            ),
            if (item.isVideo && (_videoStream?.variants.length ?? 0) > 1)
              _QualitySelector(
                variants: _videoStream!.variants,
                selected: _selectedVariant,
                onSelect: _switchVariant,
              ),
            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: _previewNotice == null
                  ? const SizedBox(width: double.infinity)
                  : _StatusPill(
                      message: _previewNotice!,
                      isError: _noticeIsError,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerHeader extends StatelessWidget {
  const _PlayerHeader({
    required this.item,
    required this.position,
    required this.total,
  });

  final MediaItem item;

  /// Номер текущего трека в очереди (нумерация с единицы).
  final int position;

  /// Размер очереди.
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 4.h, 12.w, 4.h),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.keyboard_arrow_down_rounded, size: 30.r),
            color: AppColors.textPrimary,
            tooltip: 'Свернуть',
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  item.category == MediaCategory.music
                      ? 'СЕЙЧАС ИГРАЕТ'
                      : 'СЕЙЧАС СМОТРИМ',
                  style: TextStyle(
                    fontSize: 10.5.sp,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: AppColors.textMuted,
                  ),
                ),
                SizedBox(height: 4.h),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  child: Text(
                    item.title,
                    key: ValueKey(item.id),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (total > 1) _QueueCounter(position: position, total: total),
        ],
      ),
    );
  }
}

/// Счётчик позиции в очереди: «3 / 24».
///
/// Заменяет бесполезную кнопку «Ещё»: по нему видно, что переключать треки
/// есть куда, и на каком месте очереди находится текущий.
class _QueueCounter extends StatelessWidget {
  const _QueueCounter({required this.position, required this.total});

  final int position;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 7.h),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: AppColors.outline),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        child: Text(
          '$position / $total',
          key: ValueKey(position),
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// Кликабельная подсказка о следующем треке очереди.
///
/// Оформлена мягким «пилюльным» чипом в стиле счётчика очереди: видно и что
/// зазвучит дальше, и то, что по нажатию можно перейти вперёд, не трогая
/// нижний ряд кнопок.
class _NextTrackHint extends StatelessWidget {
  const _NextTrackHint({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      child: GestureDetector(
        key: ValueKey('next-$title'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: EdgeInsets.only(top: 14.h),
          padding: EdgeInsets.fromLTRB(14.w, 8.h, 12.w, 8.h),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(color: AppColors.outline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.skip_next_rounded,
                size: 16.r,
                color: AppColors.textMuted,
              ),
              SizedBox(width: 8.w),
              Text(
                'Далее',
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  color: AppColors.textPrimary.withValues(alpha: 0.72),
                ),
              ),
              SizedBox(width: 6.w),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Пилюля-статус под блоком управления.
///
/// Сообщает, что за звук играет сейчас (демо-фрагмент, короткое превью) или
/// почему запись недоступна. Ошибка выделяется цветом, чтобы её было видно
/// сразу, а не только в исчезающем снекбаре.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final tone = isError ? AppColors.error : AppColors.textMuted;

    return Container(
      margin: EdgeInsets.only(top: 12.h),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: (isError ? AppColors.error : AppColors.surfaceHigh).withValues(
          alpha: isError ? 0.12 : 0.5,
        ),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: isError
              ? AppColors.error.withValues(alpha: 0.4)
              : AppColors.outline,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            size: 15.r,
            color: tone,
          ),
          SizedBox(width: 8.w),
          Flexible(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.sp,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: tone,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Сцена аудиоплеера: вращающаяся обложка и эквалайзер.
class _AudioStage extends StatelessWidget {
  const _AudioStage({
    required this.item,
    required this.rotation,
    required this.pulse,
    required this.playing,
    required this.onNext,
    this.nextTitle,
  });

  final MediaItem item;
  final Animation<double> rotation;
  final Animation<double> pulse;

  /// Играет ли трек: от этого зависит «дыхание» обложки и эквалайзер.
  final bool playing;

  /// Название следующего трека очереди; `null`, если очередь пуста.
  final String? nextTitle;

  /// Переход к следующему треку — по нажатию на подсказку «Далее».
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Обложка мягко «дышит» в такт воспроизведению и замирает на паузе —
        // так состояние плеера читается даже без звука.
        AnimatedBuilder(
          animation: pulse,
          builder: (context, child) {
            final breath = playing
                ? 1 + 0.014 * math.sin(pulse.value * 2 * math.pi)
                : 1.0;
            return Transform.scale(scale: breath, child: child);
          },
          child: AnimatedBuilder(
            animation: rotation,
            builder: (context, child) => Transform.rotate(
              angle: rotation.value * 2 * math.pi,
              child: child,
            ),
            child: _ArtworkDisc(item: item),
          ),
        ),
        SizedBox(height: 38.h),
        EqualizerBars(
          animation: pulse,
          color: item.category.accent,
          playing: playing,
          barCount: 22,
          height: 34.h,
        ),
        SizedBox(height: 30.h),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 32.w),
          child: Column(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                child: Text(
                  item.title,
                  key: ValueKey('title-${item.id}'),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 23.sp,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              SizedBox(height: 6.h),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                child: Text(
                  item.subtitle,
                  key: ValueKey('subtitle-${item.id}'),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              // Подсказка о том, что зазвучит следующим: она же — быстрый
              // переход вперёд, поэтому свайп, кнопка «Следующий» и этот
              // чип ведут к одному и тому же треку.
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: nextTitle == null
                    ? const SizedBox(width: double.infinity)
                    : _NextTrackHint(title: nextTitle!, onTap: onNext),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Круглая обложка со свечением и центральной «пластинкой».
class _ArtworkDisc extends StatelessWidget {
  const _ArtworkDisc({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 268.r,
      height: 268.r,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: item.category.accent.withValues(alpha: 0.35),
            blurRadius: 60.r,
            spreadRadius: 6.r,
          ),
        ],
      ),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 420),
              child: Artwork(
                key: ValueKey(item.id),
                item: item,
                borderRadius: 0,
                showMonogram: false,
              ),
            ),
            Center(
              child: Container(
                width: 62.r,
                height: 62.r,
                decoration: const BoxDecoration(
                  color: AppColors.ink,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    Icons.graphic_eq_rounded,
                    color: Colors.white,
                    size: 26.r,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Кнопка отключения звука.
///
/// Иконка отражает реальное состояние: при выключенном звуке — перечёркнутый
/// динамик, при низкой громкости — тихий, при высокой — громкий.
class _MuteButton extends StatelessWidget {
  const _MuteButton({
    required this.muted,
    required this.volume,
    required this.onTap,
  });

  final bool muted;
  final double volume;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = muted || volume == 0
        ? Icons.volume_off_rounded
        : volume < 0.5
        ? Icons.volume_down_rounded
        : Icons.volume_up_rounded;

    return Tooltip(
      message: muted ? 'Включить звук' : 'Выключить звук',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          padding: EdgeInsets.all(8.r),
          decoration: BoxDecoration(
            color: muted
                ? AppColors.error.withValues(alpha: 0.16)
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: Icon(
              icon,
              key: ValueKey(icon),
              size: 20.r,
              color: muted ? AppColors.error : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Переключатель качества видеопотока.
///
/// Источник отдаёт несколько кодировок одной записи; плеер сам выбирает
/// вариант под скорость соединения, но пользователь может зафиксировать
/// качество вручную — переключение сохраняет позицию кадра.
class _QualitySelector extends StatelessWidget {
  const _QualitySelector({
    required this.variants,
    required this.selected,
    required this.onSelect,
  });

  final List<VideoVariant> variants;
  final VideoVariant? selected;
  final ValueChanged<VideoVariant> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 14.h),
      child: SizedBox(
        height: 36.h,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: variants.length,
          separatorBuilder: (_, _) => SizedBox(width: 8.w),
          itemBuilder: (context, index) {
            final variant = variants[index];
            final isSelected = variant.url == selected?.url;

            return GestureDetector(
              onTap: () => onSelect(variant),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment.center,
                padding: EdgeInsets.symmetric(horizontal: 14.w),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.secondary.withValues(alpha: 0.18)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(
                    color: isSelected ? AppColors.secondary : AppColors.outline,
                  ),
                ),
                child: Text(
                  variant.label,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? AppColors.secondary
                        : AppColors.textMuted,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.playing,
    required this.isLoading,
    required this.accent,
    required this.pulse,
    required this.onTap,
    this.enabled = true,
  });

  final bool playing;
  final bool isLoading;
  final Color accent;
  final Animation<double> pulse;
  final VoidCallback onTap;

  /// Кнопка активна. Для недоступного трека она приглушается и не нажимается.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        final glow = playing ? 22 + 10 * pulse.value : 18.0;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          width: 78.r,
          height: 78.r,
          decoration: BoxDecoration(
            gradient: enabled
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [accent, Color.lerp(accent, Colors.white, 0.35)!],
                  )
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.surfaceHigh,
                      Color.lerp(AppColors.surfaceHigh, Colors.white, 0.08)!,
                    ],
                  ),
            shape: BoxShape.circle,
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.45),
                      blurRadius: glow,
                      spreadRadius: 2.r,
                    ),
                  ]
                : null,
          ),
          child: child,
        );
      },
      child: GestureDetector(
        onTap: (!enabled || isLoading) ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: isLoading
                ? SizedBox(
                    width: 32.r,
                    height: 32.r,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3.r,
                    ),
                  )
                : Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    key: ValueKey(playing),
                    color: enabled ? Colors.white : AppColors.textMuted,
                    size: 38.r,
                  ),
          ),
        ),
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.size = 24,
    this.tooltip,
    this.enabled = true,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final double size;
  final String? tooltip;

  /// Кнопка активна. Стрелки переключения гаснут, когда очередь пуста.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          padding: EdgeInsets.all(10.r),
          decoration: BoxDecoration(
            color: active
                ? AppColors.primary.withValues(alpha: 0.18)
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            child: Icon(
              icon,
              key: ValueKey(active),
              size: size.r,
              color: !enabled
                  ? AppColors.textMuted.withValues(alpha: 0.35)
                  : active
                  ? AppColors.secondary
                  : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Анимированный эквалайзер.
///
/// Полосы «пляшут» по двум синусоидам, а общая амплитуда плавно уходит в
/// минимум на паузе: по одному взгляду на индикатор видно, играет трек или
/// стоит — как в настольных музыкальных клиентах.
class EqualizerBars extends StatefulWidget {
  const EqualizerBars({
    super.key,
    required this.animation,
    required this.color,
    this.playing = true,
    this.barCount = 18,
    this.height = 30,
  });

  final Animation<double> animation;
  final Color color;

  /// Идёт ли воспроизведение. На паузе полосы опускаются вниз.
  final bool playing;
  final int barCount;
  final double height;

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars>
    with SingleTickerProviderStateMixin {
  /// Амплитуда полос: 1 — играет, 0 — пауза.
  late final AnimationController _amplitude = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: widget.playing ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant EqualizerBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing == oldWidget.playing) return;
    if (widget.playing) {
      _amplitude.forward();
    } else {
      _amplitude.reverse();
    }
  }

  @override
  void dispose() {
    _amplitude.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: Listenable.merge([widget.animation, _amplitude]),
        builder: (context, _) {
          final amplitude = Curves.easeOutCubic.transform(_amplitude.value);
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.barCount; i++)
                _Bar(
                  height: _barHeight(i, widget.animation.value, amplitude),
                  color: widget.color,
                  maxHeight: widget.height,
                ),
            ],
          );
        },
      ),
    );
  }

  double _barHeight(int index, double t, double amplitude) {
    final wave = math.sin((t * 2 * math.pi) + index * 0.55);
    final secondary = math.sin((t * 4 * math.pi) + index * 0.31);
    final normalized = (wave * 0.6 + secondary * 0.4 + 1) / 2;
    const idle = 0.1;
    return idle + (0.18 + normalized * 0.82 - idle) * amplitude;
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.height,
    required this.maxHeight,
    required this.color,
  });

  /// Относительная высота полосы (0..1).
  final double height;
  final double maxHeight;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4.r,
      height: (maxHeight * height).clamp(4, maxHeight),
      margin: EdgeInsets.symmetric(horizontal: 2.5.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [color, Color.lerp(color, Colors.white, 0.5)!],
        ),
        borderRadius: BorderRadius.circular(3.r),
      ),
    );
  }
}

/// Разбор строки длительности вида `3:42` или `2ч 12м`.
Duration _parseDuration(String label) {
  final hoursMatch = RegExp(r'(\d+)\s*ч').firstMatch(label);
  final minutesMatch = RegExp(r'(\d+)\s*м').firstMatch(label);
  final clockMatch = RegExp(r'^(\d+):(\d+)$').firstMatch(label.trim());

  if (clockMatch != null) {
    final minutes = int.parse(clockMatch.group(1)!);
    final seconds = int.parse(clockMatch.group(2)!);
    return Duration(minutes: minutes, seconds: seconds);
  }

  final hours = hoursMatch == null ? 0 : int.parse(hoursMatch.group(1)!);
  final minutes = minutesMatch == null ? 0 : int.parse(minutesMatch.group(1)!);
  final duration = Duration(hours: hours, minutes: minutes);
  return duration == Duration.zero ? const Duration(minutes: 3) : duration;
}

/// Форматирование длительности для отображения рядом с полосой прогресса.
String _formatTime(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
