import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/media_card.dart';
import '../../../../core/widgets/motion.dart';
import '../../../catalog/presentation/bloc/catalog_cubit.dart';
import '../../../catalog/presentation/bloc/catalog_state.dart';
import '../../../details/presentation/details_screen.dart';

/// Раздел поиска по каталогу с валидацией запроса.
class SearchTab extends StatefulWidget {
  const SearchTab({super.key});

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String? _error;

  static const _suggestions = [
    'аниме',
    'космос',
    'мультфильмы',
    'триллер',
    'музыка',
    'сериалы',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit([String? value]) async {
    final query = Validators.normalize(value ?? _controller.text);
    _controller.text = query;
    final error = Validators.searchQuery(query);

    setState(() => _error = error);
    if (error != null) return;

    _focusNode.unfocus();
    // Локальные совпадения появляются сразу, музыка догружается следом.
    await context.read<CatalogCubit>().search(query);
  }

  void _applySuggestion(String value) {
    _controller.text = value;
    _submit(value);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: BlocBuilder<CatalogCubit, CatalogState>(
        builder: (context, state) {
          final results = state.searchResults;

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Reveal(
                        child: Text(
                          'Поиск',
                          style: TextStyle(
                            fontSize: 30.sp,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.9,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      SizedBox(height: 18.h),
                      Reveal(
                        delay: const Duration(milliseconds: 80),
                        child: _SearchBar(
                          controller: _controller,
                          focusNode: _focusNode,
                          errorText: _error,
                          onSubmitted: _submit,
                          onClear: () {
                            _controller.clear();
                            setState(() => _error = null);
                            context.read<CatalogCubit>().clearSearch();
                          },
                        ),
                      ),
                      SizedBox(height: 18.h),
                      Reveal(
                        delay: const Duration(milliseconds: 140),
                        child: Wrap(
                          spacing: 8.w,
                          runSpacing: 8.h,
                          children: [
                            for (final suggestion in _suggestions)
                              GestureDetector(
                                onTap: () => _applySuggestion(suggestion),
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 14.w,
                                    vertical: 9.h,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(14.r),
                                    border: Border.all(color: AppColors.outline),
                                  ),
                                  child: Text(
                                    suggestion,
                                    style: TextStyle(
                                      fontSize: 13.sp,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(height: 22.h),
                      if (state.isSearching)
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 240),
                          child: Row(
                            key: ValueKey((state.isSearchPending, results.length)),
                            children: [
                              if (state.isSearchPending) ...[
                                SizedBox(
                                  width: 14.r,
                                  height: 14.r,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.r,
                                    color: AppColors.secondary,
                                  ),
                                ),
                                SizedBox(width: 10.w),
                              ],
                              Text(
                                _statusText(state.isSearchPending, results.length),
                                style: TextStyle(
                                  fontSize: 13.5.sp,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (!state.isSearching)
                const SliverToBoxAdapter(child: _SearchIdleState())
              else if (results.isEmpty && state.isSearchPending)
                const SliverToBoxAdapter(child: _SearchSkeleton())
              else if (results.isEmpty)
                SliverToBoxAdapter(child: _EmptyResults(query: state.query))
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    20.w,
                    14.h,
                    20.w,
                    state.hasMoreSearch ? 18.h : 140.h,
                  ),
                  // Кладка «masonry»: высота плитки равна высоте самой карточки
                  // (обложка сохраняет свою пропорцию — 1:1 для музыки и 1:1.45
                  // для видео). Обычная сетка с фиксированным отношением ячейки
                  // обрезала бы высокие постеры и оставляла пустоты под низкими.
                  // Число колонок считается по ширине экрана: 2 на телефоне,
                  // 4 на планшете и до 8 на десктопе.
                  sliver: SliverMasonryGrid.count(
                    crossAxisCount: context.gridColumns,
                    mainAxisSpacing: 18.h,
                    crossAxisSpacing: 16.w,
                    childCount: results.length,
                    itemBuilder: (context, index) {
                      final item = results[index];
                      return Reveal(
                        delay: Duration(milliseconds: 45 * (index % 8)),
                        offset: 18,
                        child: PosterCard(
                          item: item,
                          width: double.infinity,
                          onTap: () => openMediaItem(
                            context,
                            item,
                            queue: results,
                          ),
                          onFavoriteToggle: () => context
                              .read<CatalogCubit>()
                              .toggleFavorite(item),
                        ),
                      );
                    },
                  ),
                ),
              if (state.hasMoreSearch)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 140.h),
                    child: Reveal(
                      child: LoadMoreButton(
                        loading: state.isLoadingMore,
                        onPressed: () =>
                            context.read<CatalogCubit>().loadMoreSearch(),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Подпись над результатами: идёт поиск, ничего не найдено или счётчик.
  String _statusText(bool pending, int count) {
    if (pending) return 'Ищем по всему каталогу…';
    if (count == 0) return 'Ничего не найдено';
    return 'Найдено: $count';
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.errorText,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String? errorText;
  final ValueChanged<String> onSubmitted;
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
                  autofocus: false,
                  textInputAction: TextInputAction.search,
                  onSubmitted: onSubmitted,
                  cursorColor: AppColors.secondary,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Что посмотрим сегодня?',
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
              IconButton(
                onPressed: onClear,
                icon: Icon(
                  Icons.close_rounded,
                  size: 18.r,
                  color: AppColors.textMuted,
                ),
                tooltip: 'Очистить',
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

class _SearchSkeleton extends StatelessWidget {
  const _SearchSkeleton();

  @override
  Widget build(BuildContext context) {
    // Колонок столько же, сколько будет в готовой сетке, — переход
    // «скелетон → результаты» не сдвигает карточки.
    final columns = context.gridColumns;

    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 14.h, 20.w, 140.h),
      child: Wrap(
        spacing: 16.w,
        runSpacing: 18.h,
        children: [
          for (var index = 0; index < columns * 2; index++)
            _SkeletonCard(columns: columns),
        ],
      ),
    );
  }
}

/// Карточка-заглушка в сетке результатов.
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.columns});

  /// Число колонок сетки, под которое подгоняется ширина заглушки.
  final int columns;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // Ширина колонки совпадает с ячейкой сетки результатов
      // (паддинг 20.w с каждой стороны и зазор 16.w между колонками).
      width: (MediaQuery.sizeOf(context).width -
              40.w -
              16.w * (columns - 1)) /
          columns,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1 / 1.45,
            child: ShimmerBox(radius: 22.r),
          ),
          SizedBox(height: 10.h),
          ShimmerBox(width: 110.w, height: 14.h, radius: 7.r),
          SizedBox(height: 8.h),
          ShimmerBox(width: 76.w, height: 11.h, radius: 6.r),
        ],
      ),
    );
  }
}

class _SearchIdleState extends StatelessWidget {
  const _SearchIdleState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 40.h, 20.w, 140.h),
      child: Column(
        children: [
          Icon(
            Icons.travel_explore_rounded,
            size: 54.r,
            color: AppColors.outline,
          ),
          SizedBox(height: 16.h),
          Text(
            'Начните вводить название',
            style: TextStyle(
              fontSize: 15.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary.withValues(alpha: 0.8),
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'Поиск работает по названию, описанию и разделу каталога '
            '— от музыки до аниме.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.sp,
              height: 1.5,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 40.h, 20.w, 140.h),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 54.r,
            color: AppColors.outline,
          ),
          SizedBox(height: 16.h),
          Text(
            'По запросу «$query» ничего не найдено',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            'Попробуйте изменить формулировку или выбрать раздел каталога.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.sp, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
