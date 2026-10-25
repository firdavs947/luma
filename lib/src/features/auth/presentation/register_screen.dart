import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/motion.dart';
import 'bloc/auth_bloc.dart';
import 'bloc/auth_event.dart';
import 'bloc/auth_state.dart';
import 'widgets/auth_feedback.dart';
import 'widgets/auth_field.dart';
import 'widgets/auth_scaffold.dart';
import 'widgets/legal_footer.dart';

/// Экран создания аккаунта.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  bool _termsAccepted = false;
  bool _showTermsError = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    final formValid = _formKey.currentState?.validate() ?? false;
    setState(() => _showTermsError = !_termsAccepted);
    if (!formValid || !_termsAccepted) return;

    context.read<AuthBloc>().add(
          AuthSignUpSubmitted(
            name: Validators.normalize(_nameController.text),
            email: Validators.normalize(_emailController.text),
            password: _passwordController.text,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
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
        final busy = state.isActionInProgress(AuthAction.register);

        return Form(
          key: _formKey,
          child: AuthScaffold(
            title: 'Создать аккаунт',
            subtitle: 'Один профиль — музыка, фильмы, аниме и сериалы '
                'без ограничений.',
            children: [
              Reveal(
                delay: const Duration(milliseconds: 280),
                child: AuthField(
                  label: 'Имя',
                  hint: 'Как к вам обращаться',
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  validator: Validators.name,
                  onSubmitted: (_) => _emailFocus.requestFocus(),
                ),
              ),
              SizedBox(height: 22.h),
              Reveal(
                delay: const Duration(milliseconds: 340),
                child: AuthField(
                  label: 'E-mail',
                  hint: 'hello@luma.app',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.newUsername],
                  validator: Validators.email,
                  onSubmitted: (_) => _passwordFocus.requestFocus(),
                ),
              ),
              SizedBox(height: 22.h),
              Reveal(
                delay: const Duration(milliseconds: 400),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AuthField(
                      label: 'Пароль',
                      hint: 'Минимум 8 символов',
                      controller: _passwordController,
                      obscure: true,
                      autofillHints: const [AutofillHints.newPassword],
                      validator: Validators.password,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _confirmFocus.requestFocus(),
                    ),
                    PasswordStrengthMeter(
                      password: _passwordController.text,
                    ),
                  ],
                ),
              ),
              SizedBox(height: 22.h),
              Reveal(
                delay: const Duration(milliseconds: 460),
                child: AuthField(
                  label: 'Повторите пароль',
                  hint: '••••••••',
                  controller: _confirmController,
                  obscure: true,
                  textInputAction: TextInputAction.done,
                  validator: (value) => Validators.confirmPassword(
                    value,
                    _passwordController.text,
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              SizedBox(height: 20.h),
              Reveal(
                delay: const Duration(milliseconds: 510),
                child: _TermsCheckbox(
                  value: _termsAccepted,
                  hasError: _showTermsError && !_termsAccepted,
                  onChanged: (value) => setState(() {
                    _termsAccepted = value;
                    if (value) _showTermsError = false;
                  }),
                ),
              ),
              SizedBox(height: 22.h),
              Reveal(
                delay: const Duration(milliseconds: 560),
                child: FilledButton(
                  onPressed: busy ? null : _submit,
                  child: busy
                      ? SizedBox.square(
                          dimension: 22.r,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4.r,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Создать аккаунт'),
                ),
              ),
              SizedBox(height: 12.h),
              Reveal(
                delay: const Duration(milliseconds: 610),
                child: Center(
                  child: TextButton(
                    onPressed:
                        busy ? null : () => Navigator.of(context).maybePop(),
                    child: const Text(
                      'У меня уже есть аккаунт',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
              const LegalFooter(),
            ],
          ),
        );
      },
    );
  }
}

class _TermsCheckbox extends StatelessWidget {
  const _TermsCheckbox({
    required this.value,
    required this.hasError,
    required this.onChanged,
  });

  final bool value;
  final bool hasError;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: hasError ? AppColors.error : AppColors.outline,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Checkbox(
            value: value,
            onChanged: (next) => onChanged(next ?? false),
            activeColor: AppColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6.r),
            ),
          ),
          Expanded(
            child: Text(
              hasError
                  ? 'Подтвердите согласие с условиями сервиса'
                  : 'Согласен с условиями и обработкой данных',
              style: TextStyle(
                fontSize: 13.sp,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: hasError ? AppColors.error : AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
