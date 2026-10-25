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

  /// Элемент для верхнего баннера: первый видеоматериал каталога.
  ///
  /// Пока источник не ответил, баннер показывает локальный плейсхолдер,
  /// поэтому `null` — нормальная ситуация, а не ошибка.
  MediaItem? get featured {
    for (final item in items) {
      if (item.isVideo) return item;
    }
    return null;
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
      ];
}
