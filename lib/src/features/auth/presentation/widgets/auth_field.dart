import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/validators.dart';

/// Поле ввода для экранов авторизации.
///
/// Включает подпись, встроенную валидацию, анимированное сообщение об
/// ошибке и переключатель видимости пароля.
class AuthField extends StatefulWidget {
  const AuthField({
    super.key,
    required this.label,
    required this.controller,
    required this.validator,
    this.hint,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.textCapitalization = TextCapitalization.none,
    this.obscure = false,
    this.autofillHints,
    this.inputFormatters,
    this.onSubmitted,
    this.onChanged,
  });

  final String label;
  final String? hint;
  final TextEditingController controller;
  final String? Function(String?) validator;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;
  final bool obscure;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  late bool _obscured = widget.obscure;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 220),
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.6,
            color: _focused ? AppColors.secondary : AppColors.textMuted,
          ),
          child: Text(widget.label.toUpperCase()),
        ),
        SizedBox(height: 10.h),
        Focus(
          onFocusChange: (value) => setState(() => _focused = value),
          child: TextFormField(
            controller: widget.controller,
            validator: widget.validator,
            obscureText: _obscured,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            textCapitalization: widget.textCapitalization,
            autofillHints: widget.autofillHints,
            inputFormatters: widget.inputFormatters,
            autocorrect: false,
            enableSuggestions: !widget.obscure,
            cursorColor: AppColors.secondary,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            onFieldSubmitted: widget.onSubmitted,
            onChanged: widget.onChanged,
            decoration: InputDecoration(
              hintText: widget.hint,
              suffixIcon: widget.obscure
                  ? IconButton(
                      onPressed: () => setState(() => _obscured = !_obscured),
                      icon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          _obscured
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          key: ValueKey(_obscured),
                          size: 20.r,
                          color: AppColors.textMuted,
                        ),
                      ),
                      tooltip: _obscured ? 'Показать пароль' : 'Скрыть пароль',
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

/// Индикатор надёжности пароля.
class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final strength = Validators.passwordStrength(password);
    final label = switch (strength) {
      < 0.35 => 'Слабый пароль',
      < 0.7 => 'Средний пароль',
      _ => 'Надёжный пароль',
    };
    final color = switch (strength) {
      < 0.35 => AppColors.error,
      < 0.7 => AppColors.series,
      _ => AppColors.success,
    };

    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: password.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: EdgeInsets.only(top: 12.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4.r),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: strength),
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) => LinearProgressIndicator(
                        value: value,
                        minHeight: 5.h,
                        backgroundColor: AppColors.surfaceHigh,
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
