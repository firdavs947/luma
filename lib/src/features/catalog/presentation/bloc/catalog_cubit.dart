import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/validators.dart';
import '../../domain/media_item.dart';
import '../../domain/music_source.dart';
import '../../domain/video_source.dart';
import 'catalog_state.dart';

/// Cubit каталога: загрузка контента, поиск с валидацией, фильтрация по
/// разделам, сортировка видео и работа с избранным.
///
/// Музыка приходит из [MusicSource] (Audius → Genius → локальный фолбэк),
/// видео — из [VideoSource] (Cinemeta, AniList и Internet Archive).
/// Благодаря единому контракту экраны не знают, откуда пришёл контент,
/// а сам кубит не зависит от реализации источника.
class CatalogCubit extends Cubit<CatalogState> {
  CatalogCubit({
    required this._musicSource,
    required this._videoSource,
  }) : super(const CatalogState()) {
    // Базовый каталог обновляется сам: за полчаса в кино и аниме появляются
    // новые релизы, и пользователю не нужно перезапускать приложение,
    // чтобы их увидеть. Дополнительно обновление запускается при возврате
    // приложения на экран (см. `refreshIfStale`).
    _autoRefresh = Timer.periodic(_autoRefreshInterval, (_) {
      if (state.status == CatalogStatus.ready) unawaited(refresh(silent: true));
    });
  }

  final MusicSource _musicSource;
  final VideoSource _videoSource;

  /// Сколько записей запрашивается за одну страницу раздела.
  static const _pageSize = 24;

  /// Сколько записей идёт в ленту домашнего экрана.
  static const _feedSize = 12;

  /// Сколько полных бесплатных фильмов подтягивается в каталог.
  static const _freeLimit = 24;

  /// Период автообновления контентной базы.
  static const _autoRefreshInterval = Duration(minutes: 30);

  /// Разделы, наполняемые видеоисточником.
  static const _videoCategories = [
    MediaCategory.movies,
    MediaCategory.anime,
    MediaCategory.cartoons,
    MediaCategory.series,
  ];

  Timer? _autoRefresh;

  /// Первичная загрузка уже выполняется.
  bool _isLoading = false;

  /// Обновление лент уже выполняется.
  bool _isRefreshing = false;

  /// Номер последнего поискового запроса: ответы на устаревшие запросы
  /// игнорируются, поэтому быстрый ввод не перебивает актуальные результаты.
  int _searchSequence = 0;

  /// Последняя показанная страница видеорезультатов.
  ///
  /// Музыка отдаёт следующий срез по `offset`, а видео — по номеру страницы,
  /// поэтому прогресс поиска приходится считать отдельно для каждой ветки.
  int _searchVideoPage = 1;

  /// Следующая страница каждого раздела — для догрузки сетки.
  final Map<MediaCategory, int> _nextPage = {};

  /// Разделы, у которых у источника больше нет страниц.
  final Set<MediaCategory> _exhausted = {};

  /// Разделы, запрос по которым уже выполняется.
  ///
  /// Защищает от параллельных перезагрузок при быстрых нажатиях на чипы
  /// разделов и сортировок.
  final Set<MediaCategory> _inFlight = {};

  /// Загружает каталог.
  ///
  /// Сначала показываются видео и полные бесплатные фильмы, затем
  /// подключается музыка: если музыкальный источник отвечает медленно,
  /// главный экран всё равно открывается с контентом, а не с пустым экраном.
  Future<void> load() async {
    if (_isLoading) return;
    if (state.status == CatalogStatus.ready) return refresh();

    _isLoading = true;
    emit(state.copyWith(status: CatalogStatus.loading, isRefreshing: false));

    try {
      final video = await _safeList(_videoSource.featured());
      final free = await _safeList(_videoSource.freeFull(limit: _freeLimit));
      if (isClosed) return;

      emit(
        state.copyWith(
          status: CatalogStatus.ready,
          items: _mergeFeed(video: video, free: free, music: const []),
          lastUpdated: DateTime.now(),
        ),
      );

      final music = await _safeList(_musicSource.featured());
      if (isClosed) return;

      emit(
        state.copyWith(
          items: _mergeFeed(video: video, free: free, music: music),
        ),
      );
    } finally {
      _isLoading = false;
    }
  }

  /// Обновляет ленты без перезапуска приложения.
  ///
  /// [silent] — обновление по таймеру или при возврате на экран: индикатор
  /// не показывается, чтобы интерфейс не мигал без действия пользователя.
  /// Уже загруженные разделы и избранное сохраняются.
  Future<void> refresh({bool silent = false}) async {
    if (_isLoading || _isRefreshing) return;
    if (state.items.isEmpty) return load();

    _isRefreshing = true;
    if (!silent) emit(state.copyWith(isRefreshing: true));

    try {
      final video = await _safeList(_videoSource.featured());
      final free = await _safeList(_videoSource.freeFull(limit: _freeLimit));
      final music = await _safeList(_musicSource.featured());
      if (isClosed) return;

      if (video.isEmpty && free.isEmpty && music.isEmpty) {
        emit(state.copyWith(isRefreshing: false));
        return;
      }

      emit(
        state.copyWith(
          status: CatalogStatus.ready,
          items: _mergeFeed(video: video, free: free, music: music),
          isRefreshing: false,
          lastUpdated: DateTime.now(),
        ),
      );
    } finally {
      _isRefreshing = false;
    }
  }

  /// Обновляет каталог, если данные устарели.
  ///
  /// Вызывается при возврате приложения из фона: если с прошлого обновления
  /// прошло больше [maxAge], ленты перезагружаются без индикатора.
  Future<void> refreshIfStale({
    Duration maxAge = const Duration(minutes: 15),
  }) async {
    if (state.status != CatalogStatus.ready) return;
    final last = state.lastUpdated;
    if (last != null && DateTime.now().difference(last) < maxAge) return;
    await refresh(silent: true);
  }

  @override
  Future<void> close() {
    _autoRefresh?.cancel();
    return super.close();
  }

  /// Валидирует и выполняет поиск по видео и музыке.
  ///
  /// Возвращает `true`, если запрос корректен.
  Future<bool> search(String query) async {
    if (query.trim().isEmpty) {
      emit(
        state.copyWith(
          query: '',
          clearQueryError: true,
          searchStatus: SearchStatus.idle,
          searchResults: const [],
          searchOffset: 0,
          hasMoreSearch: false,
          isLoadingMore: false,
        ),
      );
      return true;
    }

    final error = Validators.searchQuery(query);
    if (error != null) {
      emit(state.copyWith(query: query, queryError: error));
      return false;
    }

    final sequence = ++_searchSequence;
    _searchVideoPage = 1;
    emit(
      state.copyWith(
        query: query,
        clearQueryError: true,
        searchStatus: SearchStatus.loading,
        searchResults: _matchesLocally(query),
        searchOffset: 0,
        hasMoreSearch: false,
        isLoadingMore: false,
      ),
    );

    // Видео и музыка ищутся параллельно: раньше последовательные запросы
    // давали задержку в десятки секунд на медленном соединении.
    //
    // Запись фьючеров с `.wait` держит типы обеих веток (в отличие от
    // Future.wait, который стирает их до Object) и дожидается обеих
    // задач, поэтому ошибка одного источника не остаётся «висящей».
    final List<MediaItem> video;
    final MusicSearchPage music;
    try {
      final result = await (
        _videoSource.search(query, limit: _pageSize),
        _musicSource.search(query),
      ).wait;
      video = result.$1;
      music = result.$2;
    } catch (_) {
      // Источник недоступен: локальные совпадения уже показаны, поэтому
      // честно завершаем поиск вместо падения с необработанной ошибкой.
      // Ловим и Exception, и ParallelWaitError (он реализует Error).
      if (isClosed || sequence != _searchSequence) return true;
      emit(state.copyWith(searchStatus: SearchStatus.ready));
      return true;
    }
    if (isClosed || sequence != _searchSequence) return true;

    emit(
      state.copyWith(
        searchStatus: SearchStatus.ready,
        searchResults: _merge(_matchesLocally(query), [...video, ...music.items]),
        searchOffset: music.items.length,
        // Продолжение возможно, если его отдаёт хотя бы одна ветка:
        // музыка — по смещению, видео — пока страница заполнена целиком.
        hasMoreSearch: music.hasMore || video.length >= _pageSize,
      ),
    );
    return true;
  }

  /// Догружает следующую страницу результатов поиска.
  ///
  /// Выдача источника может быть длиннее одной страницы, поэтому
  /// пользователь может продолжить просмотр, а не довольствоваться первой
  /// порцией позиций. Страницы запрашиваются у обоих источников сразу —
  /// видео и музыка в результатах идут вперемешку.
  Future<void> loadMoreSearch() async {
    if (!state.canLoadMore) return;

    final query = state.query;
    final sequence = _searchSequence;
    final nextVideoPage = _searchVideoPage + 1;

    emit(state.copyWith(isLoadingMore: true));

    final List<MediaItem> video;
    final MusicSearchPage music;
    try {
      final result = await (
        _videoSource.search(query, limit: _pageSize, page: nextVideoPage),
        _musicSource.search(query, offset: state.searchOffset),
      ).wait;
      video = result.$1;
      music = result.$2;
    } catch (_) {
      // Догрузка не удалась: честно убираем кнопку, а не «крутим» её вечно.
      if (isClosed || sequence != _searchSequence) return;
      emit(state.copyWith(isLoadingMore: false, hasMoreSearch: false));
      return;
    }
    if (isClosed || sequence != _searchSequence) return;

    if (video.isNotEmpty) _searchVideoPage = nextVideoPage;

    emit(
      state.copyWith(
        searchResults: _merge(state.searchResults, [...video, ...music.items]),
        searchOffset: state.searchOffset + music.items.length,
        hasMoreSearch: music.hasMore || video.length >= _pageSize,
        isLoadingMore: false,
      ),
    );
  }

  void clearSearch() {
    _searchSequence++;
    _searchVideoPage = 1;
    emit(
      state.copyWith(
        query: '',
        clearQueryError: true,
        searchStatus: SearchStatus.idle,
        searchResults: const [],
        searchOffset: 0,
        hasMoreSearch: false,
        isLoadingMore: false,
      ),
    );
  }

  /// Переключает активный раздел и подтягивает его контент из источника.
  void selectCategory(MediaCategory? category) {
    if (category == null) {
      emit(state.copyWith(clearCategory: true, categoryHasMore: false));
      return;
    }

    emit(
      state.copyWith(
        activeCategory: category,
        categoryHasMore: !_exhausted.contains(category),
      ),
    );

    if (category != MediaCategory.music) {
      unawaited(loadCategory(category, reset: true));
    }
  }

  /// Меняет сортировку видеокаталога и перезагружает текущий раздел.
  Future<void> changeSort(VideoSort sort) async {
    if (sort == state.videoSort) return;

    final category = state.activeCategory;
    emit(state.copyWith(videoSort: sort));

    if (category == MediaCategory.music) return;

    // Конкретный раздел — перезагружаем только его.
    if (category != null) {
      _exhausted.remove(category);
      _nextPage.remove(category);
      await loadCategory(category, reset: true);
      return;
    }

    // Раздел не выбран — пересобираем ленты всех видеонаправлений.
    final video = await _overview(sort);
    final free = await _safeList(_videoSource.freeFull(limit: _freeLimit));
    if (isClosed) return;

    final music = state.items.where((item) => !item.isVideo).toList();
    emit(
      state.copyWith(
        items: [
          ..._preserve(_unique([...video, ...free])),
          ...music,
        ],
      ),
    );
  }

  /// Догружает сетку активного раздела.
  Future<void> loadMoreCategory() async {
    final category = state.activeCategory;
    if (category == null || category == MediaCategory.music) return;
    await loadCategory(category);
  }

  /// Загружает страницу раздела.
  ///
  /// При `reset` страница начинается с первой, а прежние записи раздела
  /// заменяются — так работает смена сортировки.
  Future<void> loadCategory(
    MediaCategory category, {
    bool reset = false,
  }) async {
    if (category == MediaCategory.music) return;
    if (!reset && _exhausted.contains(category)) return;
    if (!_inFlight.add(category)) return;

    final page = reset ? 1 : (_nextPage[category] ?? 1);
    emit(state.copyWith(loadingCategory: category));

    try {
      final items = await _videoSource.byCategory(
        category,
        sort: state.videoSort,
        limit: _pageSize,
        page: page,
      );
      if (isClosed) return;

      _nextPage[category] = page + 1;
      if (reset || items.length >= _pageSize) {
        _exhausted.remove(category);
      }
      if (items.length < _pageSize) _exhausted.add(category);

      final fresh = _preserve(items);
      // При смене сортировки старые записи раздела заменяются, но полные
      // бесплатные фильмы остаются: они не зависят от ленты Cinemeta.
      final base = reset
          ? state.items
                .where(
                  (item) => item.category != category || item.isFreeFull,
                )
                .toList()
          : state.items;

      emit(
        state.copyWith(
          // Пустой ответ не должен стирать уже показанную ленту.
          items: fresh.isEmpty
              ? state.items
              : reset
              ? _unique([...fresh, ...base])
              : _unique([...base, ...fresh]),
          clearLoadingCategory: true,
          categoryHasMore: !_exhausted.contains(category),
        ),
      );
    } on Exception {
      // Сеть недоступна: оставляем то, что уже загружено, и честно сообщаем
      // об отсутствии следующих страниц, чтобы кнопка догрузки не «врала».
      if (isClosed) return;
      emit(state.copyWith(clearLoadingCategory: true, categoryHasMore: false));
    } finally {
      _inFlight.remove(category);
    }
  }

  /// Добавляет или убирает элемент из избранного.
  ///
  /// Если элемента ещё нет в каталоге (например, результат поиска), он
  /// добавляется — избранное работает для любого контента и сразу видно
  /// в соответствующем разделе.
  void toggleFavorite(MediaItem item) {
    final current = state.byId(item.id) ?? _searchItem(item.id) ?? item;
    final next = current.copyWith(isFavorite: !current.isFavorite);

    final exists = state.items.any((entry) => entry.id == item.id);
    final items = exists
        ? [
            for (final entry in state.items)
              entry.id == item.id ? next : entry,
          ]
        : [...state.items, next];

    emit(
      state.copyWith(
        items: items,
        searchResults: [
          for (final entry in state.searchResults)
            entry.id == item.id ? next : entry,
        ],
      ),
    );
  }

  /// Обновляет прогресс просмотра или прослушивания.
  ///
  /// Элемент может прийти из поиска и ещё не быть в каталоге — тогда он
  /// добавляется, чтобы «Продолжить просмотр» не терял начатый фильм.
  void updateProgress(String id, double progress) {
    final value = progress.clamp(0.0, 1.0);
    var found = false;

    final items = <MediaItem>[];
    for (final entry in state.items) {
      if (entry.id == id) {
        items.add(entry.copyWith(progress: value));
        found = true;
      } else {
        items.add(entry);
      }
    }

    if (!found) {
      final match = state.byId(id) ?? _searchItem(id);
      if (match != null) items.add(match.copyWith(progress: value));
    }

    emit(
      state.copyWith(
        items: items,
        searchResults: [
          for (final entry in state.searchResults)
            entry.id == id ? entry.copyWith(progress: value) : entry,
        ],
      ),
    );
  }

  MediaItem? _searchItem(String id) {
    for (final item in state.searchResults) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Свежие ленты + уже загруженный каталог без дублей.
  ///
  /// Свежие записи идут первыми, поэтому новинки видны сразу. Загруженные
  /// ранее разделы, избранное и начатые фильмы сохраняются, но общий список
  /// ограничен, чтобы автообновление не росло бесконечно.
  List<MediaItem> _mergeFeed({
    required List<MediaItem> video,
    required List<MediaItem> free,
    required List<MediaItem> music,
  }) {
    final current = {for (final item in state.items) item.id: item};
    final fresh = <MediaItem>[];
    final seenIds = <String>{};
    final seenImdb = <String>{};

    for (final item in [...video, ...free, ...music]) {
      final old = current[item.id];
      final next = old == null
          ? item
          : item.copyWith(
              isFavorite: old.isFavorite,
              progress: old.progress,
            );
      if (!seenIds.add(next.id)) continue;
      final imdb = next.imdbId;
      if (imdb != null && imdb.isNotEmpty && !seenImdb.add(imdb)) continue;
      fresh.add(next);
    }

    if (state.items.isEmpty) return fresh;

    final saved = <MediaItem>[];
    final others = <MediaItem>[];
    for (final old in state.items) {
      if (seenIds.contains(old.id)) continue;
      final imdb = old.imdbId;
      if (imdb != null && imdb.isNotEmpty && seenImdb.contains(imdb)) {
        continue;
      }
      if (old.isFavorite || old.progress > 0) {
        saved.add(old);
      } else {
        others.add(old);
      }
    }

    final merged = [...fresh, ...saved];
    var videos = merged.where((item) => item.isVideo).length;
    var musicCount = merged.where((item) => !item.isVideo).length;

    for (final item in others) {
      if (item.isVideo) {
        if (videos >= 240) continue;
        videos++;
      } else {
        if (musicCount >= 120) continue;
        musicCount++;
      }
      merged.add(item);
    }
    return merged;
  }

  /// Дубликаты по id и IMDb: одна и та же запись из разных источников
  /// не должна появляться в ленте дважды.
  static List<MediaItem> _unique(List<MediaItem> items) {
    final seenIds = <String>{};
    final seenImdb = <String>{};
    final result = <MediaItem>[];
    for (final item in items) {
      if (!seenIds.add(item.id)) continue;
      final imdb = item.imdbId;
      if (imdb != null && imdb.isNotEmpty && !seenImdb.add(imdb)) continue;
      result.add(item);
    }
    return result;
  }

  /// Источник может быть недоступен: пустой список не должен ломать
  /// загрузку остальных лент.
  static Future<List<MediaItem>> _safeList(
    Future<List<MediaItem>> future,
  ) async {
    try {
      return await future;
    } catch (_) {
      return const [];
    }
  }

  /// Ленты всех видеонаправлений, собранные «вперемешку».
  ///
  /// Чередование даёт ровные подборки в каждом разделе вместо блоков
  /// одного источника.
  Future<List<MediaItem>> _overview(VideoSort sort) async {
    final pages = await Future.wait([
      for (final category in _videoCategories)
        _videoSource.byCategory(
          category,
          sort: sort,
          limit: _feedSize,
        ),
    ]);

    final mixed = <MediaItem>[];
    final longest = pages.fold<int>(
      0,
      (max, page) => page.length > max ? page.length : max,
    );
    for (var i = 0; i < longest; i++) {
      for (final page in pages) {
        if (i < page.length) mixed.add(page[i]);
      }
    }
    return mixed;
  }

  /// Переносит избранное и прогресс на свежие данные источника.
  List<MediaItem> _preserve(List<MediaItem> fresh) {
    final current = <String, MediaItem>{
      for (final item in state.items) item.id: item,
    };

    return [
      for (final item in fresh)
        if (current[item.id] case final old?)
          item.copyWith(isFavorite: old.isFavorite, progress: old.progress)
        else
          item,
    ];
  }

  /// Совпадения по уже загруженному каталогу.
  List<MediaItem> _matchesLocally(String query) {
    final normalized = query.trim().toLowerCase();

    return state.items
        .where(
          (item) =>
              item.title.toLowerCase().contains(normalized) ||
              item.subtitle.toLowerCase().contains(normalized) ||
              item.category.label.toLowerCase().contains(normalized),
        )
        .toList();
  }

  /// Объединяет результаты без дублей: локальные совпадения идут первыми.
  ///
  /// Одна и та же запись может прийти из Cinemeta, AniList и архива с
  /// разными id, поэтому дополнительно сверяется IMDb-идентификатор.
  List<MediaItem> _merge(List<MediaItem> local, List<MediaItem> remote) {
    final seenIds = <String>{};
    final seenImdb = <String>{};
    final merged = <MediaItem>[];

    for (final item in [...local, ...remote]) {
      if (!seenIds.add(item.id)) continue;
      final imdb = item.imdbId;
      if (imdb != null && imdb.isNotEmpty && !seenImdb.add(imdb)) continue;
      merged.add(item);
    }
    return merged;
  }
}
