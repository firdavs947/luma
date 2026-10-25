import 'package:equatable/equatable.dart';

import '../../domain/media_item.dart';
import '../../domain/video_source.dart';

/// Статус загрузки каталога.
enum CatalogStatus { idle, loading, ready }

/// Этап выполнения поиска.
///
/// Локальные результаты находятся мгновенно, музыка подгружается из
/// внешнего источника, поэтому у поиска есть отдельное состояние.
enum SearchStatus { idle, loading, ready }

/// Состояние каталога: поиск, фильтр по разделам и избранное.
class CatalogState extends Equatable {
  const CatalogState({
    this.status = CatalogStatus.idle,
    this.items = const [],
    this.query = '',
    this.queryError,
    this.activeCategory,
    this.searchStatus = SearchStatus.idle,
    this.searchResults = const [],
    this.searchOffset = 0,
    this.hasMoreSearch = false,
    this.isLoadingMore = false,
    this.videoSort = VideoSort.popular,
    this.loadingCategory,
    this.categoryHasMore = false,
    this.isRefreshing = false,
    this.lastUpdated,
  });

  final CatalogStatus status;

  /// Полный список контента с учётом локальных изменений.
  final List<MediaItem> items;

  /// Текущий поисковый запрос.
  final String query;

  /// Ошибка валидации поискового запроса.
  final String? queryError;

  /// Выбранный раздел; `null` — все разделы.
  final MediaCategory? activeCategory;

  /// Этап выполнения поиска.
  final SearchStatus searchStatus;

  /// Найденные элементы: совпадения по каталогу и музыка из источника.
  final List<MediaItem> searchResults;

  /// Сколько музыкальных результатов уже загружено из источника.
  ///
  /// Передаётся источнику как `offset` при догрузке следующей страницы.
  final int searchOffset;

  /// Есть ли у источника ещё результаты поиска.
  final bool hasMoreSearch;

  /// Идёт догрузка следующей страницы результатов.
  final bool isLoadingMore;

  /// Активная сортировка видеокаталога.
  final VideoSort videoSort;

  /// Раздел, который сейчас перезагружается из источника; `null` — тишина.
  ///
  /// Нужна, чтобы сетка раздела показывала свой индикатор загрузки, не
  /// блокируя остальные ленты домашнего экрана.
  final MediaCategory? loadingCategory;

  /// Есть ли у источника ещё страницы выбранного раздела.
  final bool categoryHasMore;

  /// Идёт фоновое обновление лент (кнопка обновления или автообновление).
  final bool isRefreshing;

  /// Когда каталог последний раз успешно обновился.
  ///
  /// По времени видно, что новинки подтянулись, а также решается, нужно ли
  /// обновлять базу при возврате приложения на экран.
  final DateTime? lastUpdated;

  bool get isSearching => query.trim().isNotEmpty;

  /// Ожидаем ли ещё результаты поиска.
  bool get isSearchPending => searchStatus == SearchStatus.loading;

  /// Можно ли показать кнопку «Показать ещё».
  bool get canLoadMore =>
      isSearchPending == false && hasMoreSearch && !isLoadingMore;

  /// Контент выбранного раздела.
  List<MediaItem> get visibleItems {
    final category = activeCategory;
    if (category == null) return items;
    return items.where((item) => item.category == category).toList();
  }

  /// Продолжить просмотр — элементы с ненулевым прогрессом.
  List<MediaItem> get continueWatching =>
      items.where((item) => item.progress > 0).toList();

  /// Избранное.
  List<MediaItem> get favorites =>
      items.where((item) => item.isFavorite).toList();

  /// Только видео: музыкальные треки живут в своих разделах.
  List<MediaItem> get videoItems =>
      items.where((item) => item.isVideo).toList();

  /// Полные фильмы, доступные для просмотра целиком и бесплатно.
  List<MediaItem> get freeItems {
    final list = items.where((item) => item.isFreeFull).toList();
    list.sort((a, b) => b.displayScore.compareTo(a.displayScore));
    return list;
  }

  /// Новинки: свежие фильмы, сериалы, мультфильмы и аниме.
  ///
  /// Сортируются по точной дате выхода, а при её отсутствии — по году.
  /// Свежие релизы оказываются первыми даже после догрузки разделов.
  List<MediaItem> get newItems {
    final list = [
      for (final item in items)
        if (item.isVideo && !item.isFreeFull) item,
    ];
    list.sort((a, b) => _recency(b).compareTo(_recency(a)));
    return list.take(14).toList();
  }

  /// Элементы для hero-карусели: сначала широкие кадры 16:9.
  ///
  /// Если у источника ещё нет фонов, используется обычная обложка, поэтому
  /// карусель никогда не остаётся пустой при наличии видео.
  List<MediaItem> get heroItems {
    final withBackdrop = [
      for (final item in items)
        if (item.isVideo && (item.backdropUrl?.isNotEmpty ?? false)) item,
    ];
    if (withBackdrop.length >= 4) return withBackdrop.take(7).toList();
    return videoItems.take(6).toList();
  }

  /// Элемент для верхнего баннера: первый видеоэлемент hero-карусели.
  ///
  /// Пока источник не ответил, баннер не показывается — вместо вымышленного
  /// контента интерфейс выводит skeleton.
  MediaItem? get featured {
    final heroes = heroItems;
    if (heroes.isNotEmpty) return heroes.first;
    for (final item in items) {
      if (item.isVideo) return item;
    }
    return null;
  }

  static int _recency(MediaItem item) {
    final date = DateTime.tryParse(item.releaseDate ?? '');
    if (date != null) return date.millisecondsSinceEpoch;
    return item.releaseYear * 10000 + 101;
  }

  /// Элементы раздела (без учёта фильтра поиска).
  List<MediaItem> forCategory(MediaCategory category) =>
      items.where((item) => item.category == category).toList();

  MediaItem? byId(String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  CatalogState copyWith({
    CatalogStatus? status,
    List<MediaItem>? items,
    String? query,
    String? queryError,
    MediaCategory? activeCategory,
    SearchStatus? searchStatus,
    List<MediaItem>? searchResults,
    int? searchOffset,
    bool? hasMoreSearch,
    bool? isLoadingMore,
    VideoSort? videoSort,
    MediaCategory? loadingCategory,
    bool? categoryHasMore,
    bool? isRefreshing,
    DateTime? lastUpdated,
    bool clearQueryError = false,
    bool clearCategory = false,
    bool clearLoadingCategory = false,
  }) {
    return CatalogState(
      status: status ?? this.status,
      items: items ?? this.items,
      query: query ?? this.query,
      queryError: clearQueryError ? null : (queryError ?? this.queryError),
      activeCategory:
          clearCategory ? null : (activeCategory ?? this.activeCategory),
      searchStatus: searchStatus ?? this.searchStatus,
      searchResults: searchResults ?? this.searchResults,
      searchOffset: searchOffset ?? this.searchOffset,
      hasMoreSearch: hasMoreSearch ?? this.hasMoreSearch,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      videoSort: videoSort ?? this.videoSort,
      loadingCategory:
          clearLoadingCategory ? null : (loadingCategory ?? this.loadingCategory),
      categoryHasMore: categoryHasMore ?? this.categoryHasMore,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  @override
  List<Object?> get props => [
        status,
        items,
        query,
        queryError,
        activeCategory,
        searchStatus,
        searchResults,
        searchOffset,
        hasMoreSearch,
        isLoadingMore,
        videoSort,
        loadingCategory,
        categoryHasMore,
        isRefreshing,
        lastUpdated,
      ];
}
