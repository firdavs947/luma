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

/// Что именно открывает плеер.
enum PlaybackKind {
  /// Полная запись: фильм или другой файл целиком.
  fullFilm,

  /// Официальный трейлер: полная версия в приложении недоступна.
  trailer,
}

/// Готовый к воспроизведению видеопоток.
class VideoStream {
  const VideoStream({
    required this.url,
    this.variants = const [],
    this.isAdaptive = false,
    this.mimeType,
    this.kind = PlaybackKind.fullFilm,
    this.youtubeId,
    this.providerLabel,
    this.pageUrl,
  });

  /// Ссылка по умолчанию.
  ///
  /// Для трейлера это страница ролика на YouTube — она нужна кнопке
  /// «Открыть на YouTube»; сам кадр в приложении строит iframe-плеер.
  final String url;

  /// Альтернативные качества для ручного переключения.
  final List<VideoVariant> variants;

  /// Поток адаптивный сам по себе (HLS/DASH): плеер подстраивает битрейт
  /// на лету средствами платформы.
  final bool isAdaptive;

  /// MIME-тип выбранного файла.
  final String? mimeType;

  /// Полная запись или трейлер.
  final PlaybackKind kind;

  /// Идентификатор ролика YouTube для встроенного плеера.
  final String? youtubeId;

  /// Подпись источника для интерфейса: «Internet Archive · полный фильм»,
  /// «Официальный трейлер».
  final String? providerLabel;

  /// Страница источника, которую можно открыть в браузере.
  final String? pageUrl;

  bool get isTrailer => kind == PlaybackKind.trailer;

  bool get isYoutube => youtubeId != null && youtubeId!.isNotEmpty;
}

/// Источник видеоконтента.
///
/// Интерфейс намеренно повторяет музыкальный: каталог не знает, откуда
/// приходит видео, поэтому источник можно заменить, не трогая экраны.
abstract class VideoSource {
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

  /// Дополняет карточку подробностями, которые не нужны в лентах:
  /// описанием, актёрами, режиссёрами и точной длительностью.
  ///
  /// Источники, которые уже отдают полные данные, возвращают элемент как есть.
  Future<MediaItem> enrich(MediaItem item) async => item;

  /// Ищет полную бесплатную версию фильма или сериала в Internet Archive.
  ///
  /// Для свежих релизов возвращает `null`: они защищены авторским правом,
  /// поэтому в приложении доступен только официальный трейлер.
  Future<MediaItem?> fullVersionOf(MediaItem item) async => null;

  /// Полные фильмы, доступные для просмотра целиком и бесплатно.
  ///
  /// Источники, у которых нет таких записей, возвращают пустой список.
  Future<List<MediaItem>> freeFull({int limit = 24}) async => const [];
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
