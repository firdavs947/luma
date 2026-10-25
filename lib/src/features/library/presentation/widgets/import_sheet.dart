import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/motion.dart';
import '../../domain/audio_import_exception.dart';
import '../../domain/audio_import_rules.dart';
import '../../domain/imported_audio_repository.dart';
import '../library_cubit.dart';

/// Открывает шторку загрузки аудиофайла.
///
/// Шторка живёт поверх текущего экрана и не меняет саму библиотеку: она
/// только собирает выбор пользователя и передаёт его в [LibraryCubit].
Future<void> showImportSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.ink.withValues(alpha: 0.72),
    builder: (_) => const ImportSheet(),
  );
}

/// Пошаговый импорт трека: выбор файла, проверка, подпись и обложка.
class ImportSheet extends StatefulWidget {
  const ImportSheet({super.key});

  @override
  State<ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<ImportSheet> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _artist = TextEditingController();

  AudioFileCandidate? _audio;
  AudioFileCandidate? _cover;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    super.dispose();
  }

  /// Системный выбор аудиофайла и его проверка.
  Future<void> _pickAudio() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final candidate = await context.read<LibraryCubit>().pickAudio();
      if (!mounted || candidate == null) return; // Отмена выбора.

      setState(() {
        _audio = candidate;
        // Название по умолчанию — имя файла: пользователь может его заменить.
        if (_title.text.trim().isEmpty) _title.text = _nameFromFile(candidate.name);
      });
    } on AudioImportException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Системный выбор обложки.
  Future<void> _pickCover() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final candidate = await context.read<LibraryCubit>().pickCover();
      if (!mounted || candidate == null) return;

      setState(() => _cover = candidate);
    } on AudioImportException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Сохраняет трек в библиотеке и закрывает шторку.
  Future<void> _submit() async {
    final audio = _audio;
    if (audio == null || _busy) return;

    final cubit = context.read<LibraryCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final track = await cubit.addTrack(
        audio: audio,
        title: _title.text,
        artist: _artist.text,
        cover: _cover,
      );
      if (!mounted) return;

      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('«${track.title}» добавлен в библиотеку'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } on AudioImportException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final supported = context.read<LibraryCubit>().isSupported;
    final audio = _audio;

    return Padding(
      // Шторка поднимается над клавиатурой, чтобы поля оставались видны.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30.r)),
          border: Border(top: BorderSide(color: AppColors.outline)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(20.w, 10.h, 20.w, 24.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: _Grabber()),
                SizedBox(height: 16.h),
                const _SheetHeader(),
                SizedBox(height: 18.h),
                if (!supported)
                  const _NoticeCard(
                    icon: Icons.smartphone_rounded,
                    text: 'Загрузка музыки доступна в мобильном приложении '
                        'LUMA для iOS и Android.',
                  )
                else ...[
                  if (audio == null)
                    _PickerCard(
                      busy: _busy,
                      onTap: _pickAudio,
                      icon: Icons.library_music_rounded,
                      title: 'Выбрать аудиофайл',
                      subtitle: '${AudioImportRules.audioFormatsLabel} · '
                          'до ${AudioImportRules.formatBytes(AudioImportRules.maxAudioBytes)}',
                    )
                  else ...[
                    _SelectedFile(track: audio, onReplace: _pickAudio),
                    SizedBox(height: 18.h),
                    _TitleField(
                      controller: _title,
                      label: 'Название трека',
                      hint: 'Например: Midnight City',
                    ),
                    SizedBox(height: 14.h),
                    _TitleField(
                      controller: _artist,
                      label: 'Исполнитель',
                      hint: 'Можно оставить пустым',
                    ),
                    SizedBox(height: 14.h),
                    _CoverPicker(
                      busy: _busy,
                      cover: _cover,
                      onPick: _pickCover,
                      onClear: () => setState(() => _cover = null),
                    ),
                    SizedBox(height: 12.h),
                    _PreviewNotice(fileName: audio.name),
                  ],
                  _ErrorBanner(message: _error),
                  SizedBox(height: 18.h),
                  _SubmitButton(
                    enabled: audio != null && !_busy,
                    busy: _busy,
                    onTap: _submit,
                  ),
                  SizedBox(height: 12.h),
                  const _SecurityNote(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Имя трека по умолчанию: имя файла без расширения.
String _nameFromFile(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final base = dot <= 0 ? fileName : fileName.substring(0, dot);
  return base.trim();
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46.w,
      height: 5.h,
      decoration: BoxDecoration(
        color: AppColors.outline,
        borderRadius: BorderRadius.circular(3.r),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46.r,
          height: 46.r,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(15.r),
          ),
          child: Icon(
            Icons.cloud_upload_rounded,
            color: AppColors.secondary,
            size: 24.r,
          ),
        ),
        SizedBox(width: 14.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Загрузить трек',
                style: TextStyle(
                  fontSize: 19.sp,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 3.h),
              Text(
                'Файл проверится и сохранится в библиотеке приложения.',
                style: TextStyle(fontSize: 12.5.sp, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Кнопка выбора файла, пока он ещё не выбран.
class _PickerCard extends StatelessWidget {
  const _PickerCard({
    required this.busy,
    required this.onTap,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final bool busy;
  final VoidCallback onTap;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return AnimatedTap(
      onTap: busy ? null : onTap,
      scale: 0.98,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 22.h),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(22.r),
          border: Border.all(color: AppColors.outline),
        ),
        child: Column(
          children: [
            busy
                ? SizedBox(
                    width: 26.r,
                    height: 26.r,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4.r,
                      color: AppColors.secondary,
                    ),
                  )
                : Icon(icon, size: 30.r, color: AppColors.secondary),
            SizedBox(height: 12.h),
            Text(
              title,
              style: TextStyle(
                fontSize: 15.sp,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 5.h),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5.sp,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Карточка выбранного файла с метаданными.
class _SelectedFile extends StatelessWidget {
  const _SelectedFile({required this.track, required this.onReplace});

  final AudioFileCandidate track;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) {
    final metadata = track.metadata;

    return Container(
      padding: EdgeInsets.all(14.r),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(22.r),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42.r,
                height: 42.r,
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13.r),
                ),
                child: Icon(
                  Icons.audiotrack_rounded,
                  color: AppColors.secondary,
                  size: 21.r,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 3.h),
                    Text(
                      '${track.extension.toUpperCase()} · ${track.sizeLabel}',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onReplace,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.secondary,
                  padding: EdgeInsets.symmetric(horizontal: 8.w),
                ),
                child: Text(
                  'Заменить',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5.sp),
                ),
              ),
            ],
          ),
          if (metadata != null) ...[
            SizedBox(height: 12.h),
            Wrap(
              spacing: 8.w,
              runSpacing: 8.h,
              children: [
                _MetaChip(icon: Icons.timer_outlined, text: metadata.durationLabel),
                _MetaChip(
                  icon: Icons.graphic_eq_rounded,
                  text: '${metadata.bitrateKbps} kbps',
                ),
                _MetaChip(
                  icon: Icons.straighten_rounded,
                  text: '${(metadata.sampleRate / 1000).toStringAsFixed(1)} кГц',
                ),
                _MetaChip(
                  icon: Icons.surround_sound_rounded,
                  text: metadata.channelLabel,
                ),
              ],
            ),
            SizedBox(height: 10.h),
            Text(
              metadata.codec,
              style: TextStyle(
                fontSize: 11.5.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(11.r),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13.r, color: AppColors.textMuted),
          SizedBox(width: 5.w),
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Поле подписи трека.
class _TitleField extends StatelessWidget {
  const _TitleField({
    required this.controller,
    required this.label,
    required this.hint,
  });

  final TextEditingController controller;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            color: AppColors.textMuted,
          ),
        ),
        SizedBox(height: 8.h),
        TextField(
          controller: controller,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 60,
          cursorColor: AppColors.secondary,
          style: TextStyle(
            fontSize: 15.sp,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(hintText: hint, counterText: ''),
        ),
      ],
    );
  }
}

/// Выбор обложки с предпросмотром.
class _CoverPicker extends StatelessWidget {
  const _CoverPicker({
    required this.busy,
    required this.cover,
    required this.onPick,
    required this.onClear,
  });

  final bool busy;
  final AudioFileCandidate? cover;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final image = cover;

    return Row(
      children: [
        SizedBox(
          width: 58.r,
          height: 58.r,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16.r),
            child: image == null
                ? DecoratedBox(
                    decoration: const BoxDecoration(color: AppColors.surfaceHigh),
                    child: Icon(
                      Icons.image_outlined,
                      color: AppColors.textMuted,
                      size: 22.r,
                    ),
                  )
                : Image.memory(image.bytes, fit: BoxFit.cover),
          ),
        ),
        SizedBox(width: 14.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Обложка',
                style: TextStyle(
                  fontSize: 13.5.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 3.h),
              Text(
                image == null
                    ? '${AudioImportRules.coverExtensions.map((value) => value.toUpperCase()).join(', ')} · необязательно'
                    : '${image.name} · ${image.sizeLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5.sp, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        if (image != null)
          IconButton(
            onPressed: busy ? null : onClear,
            icon: Icon(Icons.close_rounded, size: 20.r),
            color: AppColors.textMuted,
            tooltip: 'Убрать обложку',
          ),
        IconButton(
          onPressed: busy ? null : onPick,
          icon: Icon(Icons.add_photo_alternate_outlined, size: 22.r),
          color: AppColors.secondary,
          tooltip: image == null ? 'Выбрать обложку' : 'Заменить обложку',
        ),
      ],
    );
  }
}

/// Подсказка о быстром фрагменте.
class _PreviewNotice extends StatelessWidget {
  const _PreviewNotice({required this.fileName});

  final String fileName;

  @override
  Widget build(BuildContext context) {
    final isFlac = AudioImportRules.extensionOf(fileName) == 'flac';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.bolt_rounded, size: 15.r, color: AppColors.textMuted),
        SizedBox(width: 7.w),
        Expanded(
          child: Text(
            isFlac
                ? 'FLAC воспроизводится целиком — фрагмент для него не собирается.'
                : 'Для быстрого прослушивания соберётся фрагмент 30 секунд.',
            style: TextStyle(
              fontSize: 11.5.sp,
              height: 1.4,
              color: AppColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

/// Сообщение об ошибке проверки файла.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: message == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: EdgeInsets.only(top: 14.h),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: 14.w,
                  vertical: 12.h,
                ),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 17.r,
                      color: AppColors.error,
                    ),
                    SizedBox(width: 9.w),
                    Expanded(
                      child: Text(
                        message!,
                        style: TextStyle(
                          fontSize: 12.5.sp,
                          height: 1.45,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: enabled ? onTap : null,
        icon: busy
            ? SizedBox(
                width: 18.r,
                height: 18.r,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2.r,
                  color: Colors.white,
                ),
              )
            : Icon(Icons.check_rounded, size: 20.r),
        label: Text(busy ? 'Обрабатываем файл…' : 'Добавить в библиотеку'),
      ),
    );
  }
}

class _SecurityNote extends StatelessWidget {
  const _SecurityNote();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_outline_rounded, size: 14.r, color: AppColors.textMuted),
        SizedBox(width: 7.w),
        Expanded(
          child: Text(
            'Файл сохраняется в приватном каталоге приложения и недоступен '
            'для скачивания извне.',
            style: TextStyle(
              fontSize: 11.sp,
              height: 1.45,
              color: AppColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20.r, color: AppColors.textMuted),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13.sp,
                height: 1.5,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
