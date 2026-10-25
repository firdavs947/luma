import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart' as bg;

/// Настройка аудиодвижка приложения.
///
/// Без явной конфигурации аудиосессии звука может не быть вовсе: на iOS
/// плеер попадает в категорию, которую глушит системный переключатель
/// «без звука», а на Android приложение не запрашивает аудиофокус и звук
/// уходит в тишину при активном другом плеере.
abstract final class AudioEngine {
  /// Единственный экземпляр плеера для всего приложения.
  ///
  /// Он вынесен из виджетов, чтобы музыка продолжала играть в фоне при
  /// навигации, сворачивании и выходе на домашний экран. just_audio_background
  /// автоматически связывается с этим экземпляром.
  static final player = AudioPlayer();

  /// Локальный фрагмент, который играет, когда источник не отдал превью.
  ///
  /// Гарантирует, что воспроизведение и счётчик времени всегда работают,
  /// даже если внешний API вернул `preview_url: null`.
  static const demoAsset = 'assets/audio/luma_demo.wav';

  /// Готовит аудиосессию: категория «музыка», медиа-фокус, уважение к
  /// системным настройкам. Вызывается один раз при старте приложения.
  static Future<void> configure() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  /// Источник для элемента: превью из внешнего источника, а если его нет —
  /// локальный демо-фрагмент.
  ///
  /// [tag] — метаданные для системного плеера телефона: из них строится
  /// карточка с обложкой, названием и кнопками управления в области
  /// уведомлений и на экране блокировки. Фоновое воспроизведение требует
  /// метку у каждого источника, иначе плеер не подключится к сервису.
  static AudioSource sourceFor(
    String? previewUrl, {
    required bg.MediaItem tag,
  }) {
    final url = previewUrl;
    if (url == null || url.isEmpty) {
      return AudioSource.asset(demoAsset, tag: tag);
    }
    return AudioSource.uri(Uri.parse(url), tag: tag);
  }
}
