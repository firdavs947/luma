import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/media_card.dart';
import '../../../../core/widgets/motion.dart';
import '../../../catalog/presentation/bloc/catalog_cubit.dart';
import '../../../catalog/presentation/bloc/catalog_state.dart';
import '../../../details/presentation/details_screen.dart';
import '../../../library/domain/audio_import_rules.dart';
import '../../../library/domain/imported_audio.dart';
import '../../../library/presentation/library_cubit.dart';
import '../../../library/presentation/library_state.dart';
import '../../../library/presentation/widgets/import_sheet.dart';
import '../../../player/presentation/player_screen.dart';

/// Раздел «Библиотека»: избранное, продолжение просмотра, офлайн-загрузки
/// и музыка, загруженная пользователем с устройства.
class LibraryTab extends StatefulWidget {
  const LibraryTab({super.key});

  @override
  State<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<LibraryTab> {
  /// Индекс раздела с загруженной пользователем музыкой.
  static const int _uploadsIndex = 3;

  int _section = 0;

  static const _labels = ['Избранное', 'Продолжить', 'Бесплатно', 'Загрузки'];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: _section == _uploadsIndex
          ? BlocBuilder<LibraryCubit, LibraryState>(
              builder: (context, state) => _buildScroll(
                context,
                [
                  ..._headerSlivers(),
                  ..._uploadsSlivers(context, state),
                ],
              ),
            )
          : BlocBuilder<CatalogCubit, CatalogState>(
              builder: (context, state) => _buildScroll(
                context,
                [..._headerSlivers(), ..._collectionSlivers(context, state)],
              ),
            ),
    );
  }

  CustomScrollView _buildScroll(BuildContext context, List<Widget> slivers) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: slivers,
    );
  }

  /// Шапка раздела: заголовок, описание и переключатель.
  List<Widget> _headerSlivers() {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Reveal(
                child: Text(
                  'Библиотека',
                  style: TextStyle(
                    fontSize: 30.sp,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.9,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              SizedBox(height: 6.h),
              Reveal(
                delay: Duration(milliseconds: 80),
                child: Text(
                  'Избранное, продолжение просмотра и полные фильмы '
                  'без подписки — в одном месте.',
                  style: TextStyle(
                    fontSize: 13.5.sp,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              SizedBox(height: 20.h),
              Reveal(
                delay: const Duration(milliseconds: 140),
                child: _SegmentedControl(
                  labels: _labels,
                  selected: _section,
                  onSelect: (value) => setState(() => _section = value),
                ),
              ),
              SizedBox(height: 20.h),
            ],
          ),
        ),
      ),
    ];
  }

  /// Содержимое разделов каталога.
  List<Widget> _collectionSlivers(BuildContext context, CatalogState state) {
    final items = switch (_section) {
      0 => state.favorites,
      1 => state.continueWatching,
      // Публичные фильмы из Internet Archive: их можно смотреть целиком,
      // бесплатно и без подписки.
      _ => state.freeItems,
    };

    if (items.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: switch (_section) {
            0 => const _EmptyLibrary(
              section: 'Избранное',
              icon: Icons.bookmark_add_outlined,
              message: 'Добавляйте фильмы и музыку в избранное — '
                  'они появятся здесь.',
            ),
            1 => const _EmptyLibrary(
              section: 'Продолжить',
              icon: Icons.play_circle_outline_rounded,
              message: 'Начните смотреть фильм — прогресс сохранится '
                  'и появится здесь.',
            ),
            _ => const _EmptyLibrary(
              section: 'Бесплатно',
              icon: Icons.movie_filter_outlined,
              message: 'Полные фильмы без подписки появятся здесь, '
                  'как только каталог загрузит их из Internet Archive.',
            ),
          },
        ),
      ];
    }

    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 140.h),
        sliver: SliverList.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => SizedBox(height: 12.h),
          itemBuilder: (context, index) {
            final item = items[index];
            return Reveal(
              delay: Duration(milliseconds: 45 * index),
              child: MediaRowTile(
                item: item,
                onTap: () => openMediaItem(context, item),
                trailing: IconButton(
                  onPressed: () =>
                      context.read<CatalogCubit>().toggleFavorite(item),
                  icon: Icon(
                    item.isFavorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: item.isFavorite
                        ? AppColors.music
                        : AppColors.textMuted,
                    size: 22.r,
                  ),
                  tooltip: 'В избранное',
                ),
              ),
            );
          },
        ),
      ),
    ];
  }

  /// Содержимое раздела «Загрузки».
  List<Widget> _uploadsSlivers(BuildContext context, LibraryState state) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 18.h),
          child: Reveal(
            delay: const Duration(milliseconds: 180),
            child: _UploadButton(
              enabled: state.isSupported && !state.isImporting,
              onTap: () => showImportSheet(context),
            ),
          ),
        ),
      ),
      if (!state.isSupported)
        const SliverToBoxAdapter(
          child: _EmptyLibrary(
            section: 'Загрузки',
            icon: Icons.smartphone_rounded,
            message: 'Загрузка музыки доступна в мобильном приложении LUMA '
                'для iOS и Android.',
          ),
        )
      else if (state.isLoading)
        const SliverToBoxAdapter(child: _UploadsSkeleton())
      else if (state.tracks.isEmpty)
        const SliverToBoxAdapter(
          child: _EmptyLibrary(
            section: 'Загрузки',
            icon: Icons.cloud_upload_outlined,
            message: 'Добавьте аудиофайл с устройства — он появится здесь и '
                'будет воспроизводиться без интернета.',
          ),
        )
      else
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 140.h),
          sliver: SliverList.separated(
            itemCount: state.tracks.length,
            separatorBuilder: (_, _) => SizedBox(height: 12.h),
            itemBuilder: (context, index) {
              final track = state.tracks[index];
              final queue = [
                for (final entry in state.tracks) entry.toMediaItem(),
              ];

              return Reveal(
                delay: Duration(milliseconds: 45 * index),
                child: MediaRowTile(
                  item: track.toMediaItem(),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlayerScreen(
                        item: track.toMediaItem(),
                        queue: queue,
                      ),
                    ),
                  ),
                  trailing: _UploadTileActions(
                    track: track,
                    onDelete: () => _confirmDelete(context, track),
                  ),
                ),
              );
            },
          ),
        ),
    ];
  }

  /// Спрашивает подтверждение перед удалением файлов трека.
  Future<void> _confirmDelete(BuildContext context, ImportedAudio track) async {
    final cubit = context.read<LibraryCubit>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Удалить трек?'),
        content: Text(
          '«${track.title}» и его файлы будут удалены с устройства.',
          style: TextStyle(fontSize: 14.sp, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await cubit.remove(track.id);
  }
}

/// Кнопка загрузки аудиофайла.
class _UploadButton extends StatelessWidget {
  const _UploadButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: enabled ? onTap : null,
            icon: Icon(Icons.add_rounded, size: 20.r),
            label: const Text('Загрузить трек'),
          ),
        ),
        SizedBox(height: 10.h),
        Text(
          '${AudioImportRules.audioFormatsLabel} · до '
          '${AudioImportRules.formatBytes(AudioImportRules.maxAudioBytes)}',
          style: TextStyle(fontSize: 11.5.sp, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

/// Действия в строке загруженного трека.
class _UploadTileActions extends StatelessWidget {
  const _UploadTileActions({required this.track, required this.onDelete});

  final ImportedAudio track;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (track.hasPreview)
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9.r),
            ),
            child: Text(
              '30 с',
              style: TextStyle(
                fontSize: 10.5.sp,
                fontWeight: FontWeight.w800,
                color: AppColors.secondary,
              ),
            ),
          ),
        IconButton(
          onPressed: onDelete,
          icon: Icon(Icons.delete_outline_rounded, size: 21.r),
          color: AppColors.textMuted,
          tooltip: 'Удалить',
        ),
      ],
    );
  }
}

/// Скелетон списка загруженных треков во время чтения библиотеки.
class _UploadsSkeleton extends StatelessWidget {
  const _UploadsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 140.h),
      child: Column(
        children: [
          ShimmerBox(height: 82.h, radius: 20.r),
          SizedBox(height: 12.h),
          ShimmerBox(height: 82.h, radius: 20.r),
          SizedBox(height: 12.h),
          ShimmerBox(height: 82.h, radius: 20.r),
        ],
      ),
    );
  }
}

class _SegmentedControl extends StatelessWidget {
  const _SegmentedControl({
    required this.labels,
    required this.selected,
    required this.onSelect,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(5.r),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++)
            Expanded(
              child: GestureDetector(
                onTap: () => onSelect(index),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.center,
                  padding: EdgeInsets.symmetric(
                    vertical: 11.h,
                    horizontal: 2.w,
                  ),
                  decoration: BoxDecoration(
                    color: index == selected
                        ? AppColors.primary.withValues(alpha: 0.9)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      labels[index],
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12.5.sp,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: index == selected
                            ? Colors.white
                            : AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({
    required this.section,
    required this.message,
    this.icon = Icons.bookmark_add_outlined,
  });

  final String section;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 48.h, 20.w, 140.h),
      child: Column(
        children: [
          Icon(icon, size: 54.r, color: AppColors.outline),
          SizedBox(height: 16.h),
          Text(
            'Раздел «$section» пока пуст',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            message,
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
