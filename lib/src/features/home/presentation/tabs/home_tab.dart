import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/media_card.dart';
import '../../../../core/widgets/motion.dart';
import '../../../../core/widgets/artwork.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../catalog/domain/media_item.dart';
import '../../../catalog/domain/video_source.dart';
import '../../../catalog/presentation/bloc/catalog_cubit.dart';
import '../../../catalog/presentation/bloc/catalog_state.dart';
import '../../../details/presentation/details_screen.dart';
import '../../../player/presentation/player_screen.dart';

/// Домашний раздел: приветствие, поиск, премьера и ленты каталога.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key, required this.onSearchSubmitted});

  final ValueChanged<String> onSearchSubmitted;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  String? _searchError;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _submitSearch() {
    final query = Validators.normalize(_searchController.text);
    final error = Validators.searchQuery(query);

    setState(() => _searchError = error);
    if (error != null) return;

    _searchFocus.unfocus();
    widget.onSearchSubmitted(query);
  }

  /// Открывает описание, передавая подборку раздела в очередь плеера.
  void _openDetails(MediaItem item) {
    final state = context.read<CatalogCubit>().state;
    openMediaItem(context, item, queue: state.forCategory(item.category));
  }

  /// Открывает плеер вместе с очередью своего раздела.
  ///
  /// Очередь передаётся явно: без неё кнопки «Следующий»/«Предыдущий» в
  /// модальном плеере блокировались, потому что плеер считал себя одиночным.
  void _openPlayer(MediaItem item) {
    final state = context.read<CatalogCubit>().state;
    final queue = state.forCategory(item.category);

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          item: item,
          queue: queue.isEmpty ? [item] : queue,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userName = context.select<AuthBloc, String>(
      (bloc) => bloc.state.user?.name.split(' ').first ?? 'гость',
    );

    return BlocBuilder<CatalogCubit, CatalogState>(
      builder: (context, state) {
        // Переход «скелетон → лента» проходит плавно, поэтому догрузка
        // музыки из сети воспринимается как обновление данных, а не рывок.
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 460),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: state.status == CatalogStatus.loading
              ? const _HomeSkeleton()
              : _buildFeed(context, state, userName),
        );
      },
    );
  }

  Widget _buildFeed(BuildContext context, CatalogState state, String userName) {
    final continueWatching = state.continueWatching;

    return CustomScrollView(
      key: const ValueKey('home-feed'),
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Reveal(
                    child: _GreetingHeader(userName: userName),
                  ),
                  SizedBox(height: 22.h),
                  Reveal(
                    delay: const Duration(milliseconds: 90),
                    child: _SearchField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      errorText: _searchError,
                      onSubmit: _submitSearch,
                      onClear: () {
                        _searchController.clear();
                        setState(() => _searchError = null);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20.w, 24.h, 20.w, 0),
            child: Reveal(
              delay: const Duration(milliseconds: 160),
              child: _FeaturedBanner(
                // Баннер берёт первую премьеру источника; плейсхолдер
                // остаётся только на время загрузки каталога.
                item: state.featured ?? MockFeatured.item,
                onPlay: _openPlayer,
                onDetails: _openDetails,
              ),
            ),
          ),
        ),
        if (continueWatching.isNotEmpty) ...[
          SliverToBoxAdapter(child: SizedBox(height: 28.h)),
          const SliverToBoxAdapter(
            child: SectionHeader(
              title: 'Продолжить',
              icon: Icons.play_circle_outline_rounded,
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 128.h,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                itemCount: continueWatching.length,
                separatorBuilder: (_, _) => SizedBox(width: 12.w),
                itemBuilder: (context, index) {
                  final item = continueWatching[index];
                  return Reveal(
                    delay: Duration(milliseconds: 60 * index),
                    // В горизонтальной ленте ширина не ограничена, а строка
                    // растягивает серединную колонку — задаём ширину явно.
                    child: SizedBox(
                      width: 300.w,
                      child: MediaRowTile(
                        item: item,
                        onTap: () => _openDetails(item),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
        SliverToBoxAdapter(child: SizedBox(height: 28.h)),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: _CategoryFilter(
              selected: state.activeCategory,
              onSelect: (category) =>
                  context.read<CatalogCubit>().selectCategory(category),
            ),
          ),
        ),
        // Сортировка касается только видеоразделов: у музыки порядок
        // задаёт источник трендов.
        if (state.activeCategory != MediaCategory.music) ...[
          SliverToBoxAdapter(child: SizedBox(height: 14.h)),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: _SortFilter(
                selected: state.videoSort,
                onSelect: (sort) =>
                    context.read<CatalogCubit>().changeSort(sort),
              ),
            ),
          ),
        ],
        SliverToBoxAdapter(child: SizedBox(height: 8.h)),
        ..._buildCategorySlivers(state),
      ],
    );
  }

  /// Сетка выбранного видеораздела с сортировкой и догрузкой страниц.
  List<Widget> _buildCategoryGrid(CatalogState state, MediaCategory category) {
    final items = state.forCategory(category);
    final columns = context.gridColumns;
    final isLoading = state.loadingCategory == category;
    final showSkeletons = isLoading && items.isEmpty;

    return [
      SliverToBoxAdapter(
        child: SectionHeader(title: category.label, icon: category.icon),
      ),
      if (showSkeletons)
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 0),
          sliver: SliverMasonryGrid.count(
            crossAxisCount: columns,
            mainAxisSpacing: 18.h,
            crossAxisSpacing: 14.w,
            childCount: columns * 2,
            itemBuilder: (_, _) => ShimmerBox(height: 200.h, radius: 22.r),
          ),
        )
      else if (items.isEmpty)
        SliverToBoxAdapter(
          child: _EmptyCategory(
            category: category,
            onRetry: () => context
                .read<CatalogCubit>()
                .loadCategory(category, reset: true),
          ),
        )
      else
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 0),
          sliver: SliverMasonryGrid.count(
            crossAxisCount: columns,
            mainAxisSpacing: 18.h,
            crossAxisSpacing: 14.w,
            // Пока грузится следующая страница, в конце сетки видны
            // заглушки — понятно, что список ещё растёт.
            childCount: items.length + (isLoading ? columns : 0),
            itemBuilder: (context, index) {
              if (index >= items.length) {
                return ShimmerBox(height: 200.h, radius: 22.r);
              }

              final item = items[index];
              return Reveal(
                delay: Duration(milliseconds: 40 * (index % 8)),
                offset: 18,
                child: PosterCard(
                  item: item,
                  width: double.infinity,
                  onTap: () => _openDetails(item),
                  onFavoriteToggle: () =>
                      context.read<CatalogCubit>().toggleFavorite(item),
                ),
              );
            },
          ),
        ),
      if (state.categoryHasMore)
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 0),
            child: LoadMoreButton(
              loading: isLoading,
              onPressed: () => context.read<CatalogCubit>().loadMoreCategory(),
            ),
          ),
        ),
      SliverToBoxAdapter(child: SizedBox(height: 130.h)),
    ];
  }

  List<Widget> _buildCategorySlivers(CatalogState state) {
    // Выбран конкретный видеораздел — показываем его сеткой: так видно
    // весь раздел, а не только первую горизонтальную ленту.
    final active = state.activeCategory;
    if (active != null && active != MediaCategory.music) {
      return _buildCategoryGrid(state, active);
    }

    final categories = state.activeCategory == null
        ? MediaCategory.values
        : [state.activeCategory!];

    final slivers = <Widget>[];
    var delayIndex = 0;

    for (final category in categories) {
      final items = state.forCategory(category);
      if (items.isEmpty) continue;

      slivers
        ..add(
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 26.h),
              child: Reveal(
                delay: Duration(milliseconds: 60 * (delayIndex++ % 5)),
                child: SectionHeader(
                  title: category.label,
                  icon: category.icon,
                  onSeeAll: () => context
                      .read<CatalogCubit>()
                      .selectCategory(category),
                ),
              ),
            ),
          ),
        )
        ..add(
          SliverToBoxAdapter(
            child: SizedBox(
              height: category == MediaCategory.music ? 232.h : 292.h,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                itemCount: items.length,
                separatorBuilder: (_, _) => SizedBox(width: 14.w),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Reveal(
                    delay: Duration(milliseconds: 50 * index),
                    child: PosterCard(
                      item: item,
                      onTap: () => _openDetails(item),
                      onFavoriteToggle: () =>
                          context.read<CatalogCubit>().toggleFavorite(item),
                    ),
                  );
                },
              ),
            ),
          ),
        );
    }

    slivers.add(SliverToBoxAdapter(child: SizedBox(height: 130.h)));
    return slivers;
  }
}

class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({required this.userName});

  final String userName;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting(),
                style: TextStyle(
                  fontSize: 13.5.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                userName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 27.sp,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: 12.w),
        AnimatedTap(
          onTap: () {},
          borderRadius: BorderRadius.circular(18.r),
          child: Container(
            padding: EdgeInsets.all(11.r),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18.r),
              border: Border.all(color: AppColors.outline),
            ),
            child: Icon(
              Icons.notifications_none_rounded,
              color: AppColors.textPrimary,
              size: 22.r,
            ),
          ),
        ),
      ],
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 6) return 'Доброй ночи';
    if (hour < 12) return 'Доброе утро';
    if (hour < 18) return 'Добрый день';
    return 'Добрый вечер';
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.errorText,
    required this.onSubmit,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String? errorText;
  final VoidCallback onSubmit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(
              color: errorText != null ? AppColors.error : AppColors.outline,
            ),
          ),
          child: Row(
            children: [
              Padding(
                padding: EdgeInsets.only(left: 16.w),
                child: Icon(
                  Icons.search_rounded,
                  color: AppColors.textMuted,
                  size: 21.r,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => onSubmit(),
                  cursorColor: AppColors.secondary,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Фильмы, аниме, музыка…',
                    hintStyle: const TextStyle(color: AppColors.textMuted),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12.w,
                      vertical: 16.h,
                    ),
                  ),
                ),
              ),
              if (errorText == null)
                IconButton(
                  onPressed: onClear,
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18.r,
                    color: AppColors.textMuted,
                  ),
                  tooltip: 'Очистить',
                )
              else
                Padding(
                  padding: EdgeInsets.only(right: 12.w),
                  child: Icon(
                    Icons.error_outline_rounded,
                    size: 20.r,
                    color: AppColors.error,
                  ),
                ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: errorText == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: EdgeInsets.only(top: 8.h, left: 6.w),
                  child: Text(
                    errorText!,
                    style: TextStyle(
                      fontSize: 12.5.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.error,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _CategoryFilter extends StatelessWidget {
  const _CategoryFilter({required this.selected, required this.onSelect});

  final MediaCategory? selected;
  final ValueChanged<MediaCategory?> onSelect;

  @override
  Widget build(BuildContext context) {
    final entries = <(MediaCategory?, String)>[
      (null, 'Все'),
      for (final category in MediaCategory.values) (category, category.label),
    ];

    return SizedBox(
      height: 42.h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: entries.length,
        separatorBuilder: (_, _) => SizedBox(width: 10.w),
        itemBuilder: (context, index) {
          final (category, label) = entries[index];
          final isSelected = category == selected;
          final accent = category?.accent ?? AppColors.primary;

          return GestureDetector(
            onTap: () => onSelect(category),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(horizontal: 18.w),
              decoration: BoxDecoration(
                color: isSelected
                    ? accent.withValues(alpha: 0.18)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(
                  color: isSelected ? accent : AppColors.outline,
                ),
              ),
              child: Row(
                children: [
                  if (category != null) ...[
                    Icon(
                      category.icon,
                      size: 15.r,
                      color: isSelected ? accent : AppColors.textMuted,
                    ),
                    SizedBox(width: 7.w),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5.sp,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? accent : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Чипы сортировки видеокаталога.
///
/// Порядок задаёт источник: он переводит подпись в параметр запроса, поэтому
/// список сортировок берётся прямо из [VideoSort].
class _SortFilter extends StatelessWidget {
  const _SortFilter({required this.selected, required this.onSelect});

  final VideoSort selected;
  final ValueChanged<VideoSort> onSelect;

  static const _icons = {
    VideoSort.popular: Icons.local_fire_department_rounded,
    VideoSort.newest: Icons.auto_awesome_rounded,
    VideoSort.oldest: Icons.history_rounded,
    VideoSort.title: Icons.sort_by_alpha_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44.h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: VideoSort.values.length,
        separatorBuilder: (_, _) => SizedBox(width: 8.w),
        itemBuilder: (context, index) {
          final sort = VideoSort.values[index];
          final isSelected = sort == selected;

          return GestureDetector(
            onTap: () => onSelect(sort),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(horizontal: 14.w),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.secondary.withValues(alpha: 0.16)
                    : AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(14.r),
                border: Border.all(
                  color: isSelected ? AppColors.secondary : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _icons[sort],
                    size: 15.r,
                    color: isSelected
                        ? AppColors.secondary
                        : AppColors.textMuted,
                  ),
                  SizedBox(width: 7.w),
                  Text(
                    sort.label,
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? AppColors.secondary
                          : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Сообщение о пустом разделе с возможностью повторить запрос.
class _EmptyCategory extends StatelessWidget {
  const _EmptyCategory({required this.category, required this.onRetry});

  final MediaCategory category;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 24.h, 20.w, 0),
      child: Container(
        padding: EdgeInsets.all(22.r),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22.r),
          border: Border.all(color: AppColors.outline),
        ),
        child: Column(
          children: [
            Icon(
              category.icon,
              size: 40.r,
              color: category.accent.withValues(alpha: 0.7),
            ),
            SizedBox(height: 14.h),
            Text(
              'Раздел «${category.label}» пуст',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15.sp,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'Источник не ответил. Проверьте соединение и попробуйте снова.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.sp,
                height: 1.5,
                color: AppColors.textMuted,
              ),
            ),
            SizedBox(height: 16.h),
            FilledButton.icon(
              onPressed: onRetry,
              icon: Icon(Icons.refresh_rounded, size: 19.r),
              label: const Text('Повторить'),
              style: FilledButton.styleFrom(
                minimumSize: Size(160.w, 46.h),
                backgroundColor: category.accent,
                foregroundColor: AppColors.ink,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15.r),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeaturedBanner extends StatelessWidget {
  const _FeaturedBanner({
    required this.item,
    required this.onPlay,
    required this.onDetails,
  });

  final MediaItem item;
  final ValueChanged<MediaItem> onPlay;
  final ValueChanged<MediaItem> onDetails;

  @override
  Widget build(BuildContext context) {
    return AnimatedTap(
      onTap: () => onDetails(item),
      scale: 0.985,
      child: Container(
        height: 232.h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28.r),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.22),
              blurRadius: 38.r,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28.r),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Artwork(item: item, borderRadius: 0, showMonogram: false),
              Positioned(
                left: 20.w,
                right: 20.w,
                bottom: 20.h,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10.w,
                        vertical: 5.h,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Text(
                        'ПРЕМЬЕРА',
                        style: TextStyle(
                          fontSize: 10.5.sp,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                          color: AppColors.secondary,
                        ),
                      ),
                    ),
                    SizedBox(height: 10.h),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 24.sp,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.6,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      '${item.durationLabel} · ${item.category.label} · '
                      '★ ${item.rating.toStringAsFixed(1)}',
                      style: TextStyle(
                        fontSize: 12.5.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                    SizedBox(height: 16.h),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => onPlay(item),
                            icon: Icon(Icons.play_arrow_rounded, size: 22.r),
                            label: const Text('Смотреть'),
                            style: FilledButton.styleFrom(
                              minimumSize: Size.fromHeight(48.h),
                              backgroundColor: Colors.white,
                              foregroundColor: AppColors.ink,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16.r),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 10.w),
                        _CircleAction(
                          icon: Icons.add_rounded,
                          tooltip: 'В библиотеку',
                          onTap: () =>
                              context.read<CatalogCubit>().toggleFavorite(item),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 48.r,
          height: 48.r,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: Colors.white24),
          ),
          child: Icon(icon, color: Colors.white, size: 22.r),
        ),
      ),
    );
  }
}

/// Плейсхолдер домашнего экрана на время загрузки каталога.
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 120.h),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          ShimmerBox(width: 140.w, height: 16.h),
          SizedBox(height: 12.h),
          ShimmerBox(width: 200.w, height: 28.h),
          SizedBox(height: 24.h),
          ShimmerBox(height: 52.h, radius: 20.r),
          SizedBox(height: 24.h),
          ShimmerBox(height: 232.h, radius: 28.r),
          SizedBox(height: 28.h),
          ShimmerBox(width: 160.w, height: 20.h),
          SizedBox(height: 16.h),
          Row(
            children: [
              Expanded(child: ShimmerBox(height: 200.h, radius: 22.r)),
              SizedBox(width: 14.w),
              Expanded(child: ShimmerBox(height: 200.h, radius: 22.r)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Значение по умолчанию для баннера, если каталог ещё не наполнен.
abstract final class MockFeatured {
  static const item = MediaItem(
    id: 'f1',
    title: 'Орбита Молчания',
    subtitle: 'Премьера LUMA',
    category: MediaCategory.movies,
    year: 2026,
    durationLabel: '2ч 12м',
    rating: 4.7,
    description: 'Эксклюзивная премьера в 4K с пространственным звуком.',
  );
}
