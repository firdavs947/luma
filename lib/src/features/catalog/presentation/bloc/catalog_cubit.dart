import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/validators.dart';
import '../../data/mock_catalog.dart';
import '../../domain/media_item.dart';
import '../../domain/music_source.dart';
import '../../domain/video_source.dart';
import 'catalog_state.dart';

/// Cubit каталога: загрузка контента, поиск с валидацией, фильтрация по
/// разделам, сортировка видео и работа с избранным.
///
/// Музыка приходит из [MusicSource] (Audius → Genius → локальный фолбэк),
/// видео — из [VideoSource] (Internet Archive). Благодаря единому контракту
/// экраны не знают, откуда пришёл контент, а сам кубит не зависит от
/// реализации источника.
class CatalogCubit extends Cubit<CatalogState> {
  CatalogCubit({
    required this._musicSource,
    required this._videoSource,
  }) : super(const CatalogState());

  final MusicSource _musicSource;
  final VideoSource _videoSource;

  /// Сколько записей запрашивается за одну страницу раздела.
  static const _pageSize = 24;

  /// Сколько записей идёт в ленту домашнего экрана.
  static const _feedSize = 12;

  /// Разделы, наполняемые видеоисточником.
  static const _videoCategories = [
    MediaCategory.movies,
    MediaCategory.anime,
    MediaCategory.cartoons,
    MediaCategory.series,
  ];

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
  /// Сначала показывается локальный каталог, затем приходят реальные видео
  /// и музыка — интерфейс не ждёт сеть целиком.
  Future<void> load() async {
    if (state.status == CatalogStatus.loading) return;
    emit(state.copyWith(status: CatalogStatus.loading));

    // Короткая пауза под анимацию входа, затем базовый контент.
    await Future<void>.delayed(const Duration(milliseconds: 360));
    if (isClosed) return;
    emit(state.copyWith(status: CatalogStatus.ready, items: MockCatalog.video));

    final results = await Future.wait([
      _videoSource.featured(),
      _musicSource.featured(),
    ]);
    if (isClosed) return;

    final video = _preserve(results[0]);
    final music = results[1];

    emit(
      state.copyWith(
        items: [
          // Если источник видео не ответил, локальный каталог остаётся
          // каркасом: экран не должен опустеть из-за сетевой ошибки.
          if (video.isEmpty) ...MockCatalog.video else ...video,
          ...music,
        ],
      ),
    );
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
    if (isClosed) return;

    emit(
      state.copyWith(
        items: [
          ..._preserve(video),
          ...state.items.where((item) => item.category == MediaCategory.music),
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
      if (items.length < _pageSize) _exhausted.add(category);

      final fresh = _preserve(items);
      final rest = state.items.where((item) => item.category != category);
      final existingIds = {for (final item in rest) item.id};

      emit(
        state.copyWith(
          // Пустой ответ не должен стирать уже показанную ленту.
          items: fresh.isEmpty
              ? state.items
              : [
                  ...rest,
                  ...fresh.where((item) => !existingIds.contains(item.id)),
                ],
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
  /// Если элемента ещё нет в каталоге (например, трек Genius), он
  /// добавляется — избранное работает для любого контента.
  void toggleFavorite(MediaItem item) {
    final index = state.items.indexWhere((entry) => entry.id == item.id);

    if (index == -1) {
      emit(
        state.copyWith(
          items: [...state.items, item.copyWith(isFavorite: true)],
        ),
      );
      return;
    }

    final updated = [...state.items];
    final entry = updated[index];
    updated[index] = entry.copyWith(isFavorite: !entry.isFavorite);
    emit(state.copyWith(items: updated));
  }

  /// Обновляет прогресс просмотра или прослушивания.
  void updateProgress(String id, double progress) {
    final updated = [
      for (final item in state.items)
        if (item.id == id)
          item.copyWith(progress: progress.clamp(0.0, 1.0))
        else
          item,
    ];
    emit(state.copyWith(items: updated));
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
  List<MediaItem> _merge(List<MediaItem> local, List<MediaItem> remote) {
    final seen = <String>{};
    final merged = <MediaItem>[];

    for (final item in [...local, ...remote]) {
      if (seen.add(item.id)) merged.add(item);
    }
    return merged;
  }
}
