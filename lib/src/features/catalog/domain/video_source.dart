import 'media_item.dart';

/// Один вариант качества видеопотока.
///
/// Источник отдаёт одну и ту же запись в нескольких кодировках: от лёгкой
/// (для медленного соединения) до тяжёлой (для Wi-Fi). Плеер выбирает
/// подходящий вариант сам, а пользователь может переключить его вручную.
class VideoVariant {
  const VideoVariant({
    required this.url,
    required this.label,
    this.height,
    this.bandwidth,
    this.mimeType,
  });

  /// Прямая ссылка на файл.
  final String url;

  /// Подпись для интерфейса: «1080p», «720p», «480p».
  final String label;

  /// Высота кадра в пикселях; `null`, если источник её не сообщил.
  final int? height;

  /// Оценка битрейта в битах в секунду; `null` — неизвестно.
  final int? bandwidth;

  /// MIME-тип файла.
  final String? mimeType;

  /// Насколько вариант тяжёлый: чем больше, тем выше качество.
  ///
  /// Считается по высоте кадра, а при её отсутствии — по битрейту, поэтому
  /// варианты всегда можно выстроить от лучшего к худшему.
  int get weight => height ?? (bandwidth ?? 0) ~/ 1000;
}

/// Готовый к воспроизведению видеопоток.
class VideoStream {
  const VideoStream({
    required this.url,
    this.variants = const [],
    this.isAdaptive = false,
    this.mimeType,
  });

  /// Ссылка по умолчанию.
  final String url;

  /// Альтернативные качества для ручного переключения.
  final List<VideoVariant> variants;

  /// Поток адаптивный сам по себе (HLS/DASH): плеер подстраивает битрейт
  /// на лету средствами платформы.
  final bool isAdaptive;

  /// MIME-тип выбранного файла.
  final String? mimeType;
}

/// Источник видеоконтента.
///
/// Интерфейс намеренно повторяет музыкальный: каталог не знает, откуда
/// приходит видео, поэтому источник можно заменить, не трогая экраны.
abstract interface class VideoSource {
  /// Курируемая лента видео по всем разделам для главного экрана.
  Future<List<MediaItem>> featured();

  /// Видео выбранного раздела с учётом сортировки.
  Future<List<MediaItem>> byCategory(
    MediaCategory category, {
    VideoSort sort = VideoSort.popular,
    int limit = 24,
    int page = 1,
  });

  /// Поиск видео по запросу пользователя.
  Future<List<MediaItem>> search(
    String query, {
    int limit = 24,
    int page = 1,
  });

  /// Разрешает воспроизводимый поток для элемента.
  ///
  /// Возвращает `null`, если у записи нет ни одного поддерживаемого файла.
  Future<VideoStream?> resolveStream(MediaItem item);
}

/// Порядок сортировки видеокаталога.
enum VideoSort {
  /// По популярности: чаще скачиваемое — выше.
  popular('По популярности'),

  /// Сначала новые.
  newest('Сначала новые'),

  /// Сначала старые.
  oldest('Сначала старые'),

  /// По алфавиту.
  title('По алфавиту');

  const VideoSort(this.label);

  /// Подпись для интерфейса.
  final String label;
}
