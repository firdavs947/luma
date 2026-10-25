import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/motion.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_event.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../../../auth/presentation/widgets/auth_feedback.dart';

/// Раздел профиля: данные аккаунта, настройки воспроизведения и выход.
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  bool _notifications = true;
  bool _autoplay = true;
  bool _highQuality = false;

  Future<void> _editName() async {
    final bloc = context.read<AuthBloc>();
    final current = bloc.state.user?.name ?? '';
    final controller = TextEditingController(text: current);
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.r),
        ),
        title: const Text(
          'Имя профиля',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            validator: Validators.name,
            cursorColor: AppColors.secondary,
            decoration: const InputDecoration(
              hintText: 'Ваше имя',
              counterText: '',
            ),
            maxLength: Validators.maxNameLength,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(dialogContext).pop(controller.text.trim());
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (result == null || result.isEmpty) return;
    bloc.add(AuthProfileUpdated(name: result));
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.r),
        ),
        title: const Text(
          'Выйти из аккаунта?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'Сессия будет завершена на этом устройстве. Избранное сохранится '
          'в вашем профиле.',
          style: TextStyle(color: AppColors.textMuted, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Остаться'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              minimumSize: Size(120.w, 46.h),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    context.read<AuthBloc>().add(const AuthSignOutRequested());
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: BlocConsumer<AuthBloc, AuthState>(
        listenWhen: (previous, current) =>
            previous.failure != current.failure ||
            previous.infoMessage != current.infoMessage,
        listener: (context, state) {
          final message = state.failure?.userMessage ?? state.infoMessage;
          if (message != null) {
            AuthFeedback.show(
              context,
              message: message,
              isError: state.failure != null,
            );
          }
          context.read<AuthBloc>().add(const AuthFeedbackDismissed());
        },
        builder: (context, state) {
          final user = state.user;
          if (user == null) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 150.h),
            children: [
              Reveal(
                child: Text(
                  'Профиль',
                  style: TextStyle(
                    fontSize: 30.sp,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.9,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              SizedBox(height: 22.h),
              Reveal(
                delay: const Duration(milliseconds: 90),
                child: _ProfileCard(
                  initials: user.initials,
                  name: user.name,
                  email: user.email,
                  plan: user.plan,
                  since: user.memberSince,
                  onEdit: _editName,
                ),
              ),
              SizedBox(height: 26.h),
              const Reveal(
                delay: Duration(milliseconds: 160),
                child: _SectionLabel('Настройки воспроизведения'),
              ),
              SizedBox(height: 12.h),
              Reveal(
                delay: const Duration(milliseconds: 200),
                child: Column(
                  children: [
                    _SettingSwitch(
                      icon: Icons.notifications_active_outlined,
                      title: 'Уведомления о премьерах',
                      subtitle: 'Пуш-уведомления о новинках каталога',
                      value: _notifications,
                      onChanged: (value) =>
                          setState(() => _notifications = value),
                    ),
                    SizedBox(height: 12.h),
                    _SettingSwitch(
                      icon: Icons.play_circle_outline_rounded,
                      title: 'Автовоспроизведение',
                      subtitle: 'Запускать следующий эпизод автоматически',
                      value: _autoplay,
                      onChanged: (value) => setState(() => _autoplay = value),
                    ),
                    SizedBox(height: 12.h),
                    _SettingSwitch(
                      icon: Icons.hd_outlined,
                      title: 'Высокое качество',
                      subtitle: 'Только Wi-Fi · расход трафика выше',
                      value: _highQuality,
                      onChanged: (value) => setState(() => _highQuality = value),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 26.h),
              const Reveal(
                delay: Duration(milliseconds: 260),
                child: _SectionLabel('Аккаунт и данные'),
              ),
              SizedBox(height: 12.h),
              Reveal(
                delay: const Duration(milliseconds: 300),
                child: Column(
                  children: [
                    const _SettingLink(
                      icon: Icons.shield_outlined,
                      title: 'Безопасность и сессии',
                      subtitle: 'Пароль, устройства, вход по биометрии',
                    ),
                    SizedBox(height: 12.h),
                    const _SettingLink(
                      icon: Icons.download_outlined,
                      title: 'Загрузки и кэш',
                      subtitle: 'Управление офлайн-контентом',
                    ),
                    SizedBox(height: 12.h),
                    const _SettingLink(
                      icon: Icons.privacy_tip_outlined,
                      title: 'Конфиденциальность',
                      subtitle: 'Политика и обработка данных',
                    ),
                  ],
                ),
              ),
              SizedBox(height: 26.h),
              Reveal(
                delay: const Duration(milliseconds: 340),
                child: FilledButton.icon(
                  onPressed: state.isActionInProgress(AuthAction.signOut)
                      ? null
                      : _confirmSignOut,
                  icon: state.isActionInProgress(AuthAction.signOut)
                      ? SizedBox.square(
                          dimension: 18.r,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.r,
                            color: Colors.white,
                          ),
                        )
                      : Icon(Icons.logout_rounded, size: 20.r),
                  label: const Text('Выйти из аккаунта'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.surfaceHigh,
                    foregroundColor: AppColors.error,
                  ),
                ),
              ),
              SizedBox(height: 18.h),
              Center(
                child: Text(
                  'LUMA · версия 0.1.0 (build 1)',
                  style: TextStyle(fontSize: 12.sp, color: AppColors.textMuted),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.initials,
    required this.name,
    required this.email,
    required this.plan,
    required this.since,
    required this.onEdit,
  });

  final String initials;
  final String name;
  final String email;
  final String plan;
  final DateTime since;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.22),
            AppColors.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(26.r),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 62.r,
                height: 62.r,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  gradient: AppColors.brandGradient,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initials,
                  style: TextStyle(
                    fontSize: 22.sp,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              SizedBox(width: 16.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 19.sp,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 3.h),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onEdit,
                icon: Icon(Icons.edit_outlined, size: 20.r),
                color: AppColors.textPrimary,
                tooltip: 'Изменить имя',
              ),
            ],
          ),
          SizedBox(height: 18.h),
          Row(
            children: [
              Expanded(
                child: _StatBlock(
                  label: 'Подписка',
                  value: plan,
                  accent: AppColors.secondary,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: _StatBlock(
                  label: 'С LUMA с',
                  value: '${since.year}',
                  accent: AppColors.series,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5.sp,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: AppColors.textMuted,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14.5.sp,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11.5.sp,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.4,
        color: AppColors.textMuted,
      ),
    );
  }
}

class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 10.w, 12.h),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20.r, color: AppColors.textMuted),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 3.h),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

class _SettingLink extends StatelessWidget {
  const _SettingLink({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return AnimatedTap(
      onTap: () => AuthFeedback.show(
        context,
        message: 'Раздел «$title» появится в следующем обновлении',
      ),
      scale: 0.985,
      child: Container(
        padding: EdgeInsets.all(16.r),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18.r),
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20.r, color: AppColors.textMuted),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 3.h),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20.r,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
