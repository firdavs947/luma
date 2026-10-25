import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/motion.dart';
import 'bloc/auth_bloc.dart';
import 'bloc/auth_event.dart';
import 'bloc/auth_state.dart';
import 'register_screen.dart';
import 'reset_password_screen.dart';
import 'widgets/auth_feedback.dart';
import 'widgets/auth_field.dart';
import 'widgets/auth_scaffold.dart';
import 'widgets/legal_footer.dart';

/// Экран входа в аккаунт LUMA.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    context.read<AuthBloc>().add(
          AuthSignInSubmitted(
            email: Validators.normalize(_emailController.text),
            password: _passwordController.text,
          ),
        );
  }

  Future<void> _openReset() async {
    final email = Validators.normalize(_emailController.text);
    if (Validators.email(email) != null) {
      AuthFeedback.show(
        context,
        message: 'Сначала укажите e-mail аккаунта',
        isError: true,
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ResetPasswordScreen(initialEmail: email),
      ),
    );
  }

  void _fillDemoCredentials() {
    setState(() {
      _emailController.text = 'demo@luma.app';
      _passwordController.text = 'Luma2026';
    });
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
        final busy = state.isActionInProgress(AuthAction.login);

        return Form(
          key: _formKey,
          child: AuthScaffold(
            title: 'С возвращением',
            subtitle: 'Войдите, чтобы продолжить смотреть и слушать '
                'на всех устройствах.',
            children: [
              Reveal(
                delay: const Duration(milliseconds: 300),
                child: AuthField(
                  label: 'E-mail',
                  hint: 'hello@luma.app',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  validator: Validators.email,
                  onSubmitted: (_) => _passwordFocus.requestFocus(),
                ),
              ),
              SizedBox(height: 22.h),
              Reveal(
                delay: const Duration(milliseconds: 370),
                child: AuthField(
                  label: 'Пароль',
                  hint: '••••••••',
                  controller: _passwordController,
                  obscure: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  validator: Validators.password,
                  onSubmitted: (_) => _submit(),
                ),
              ),
              SizedBox(height: 8.h),
              Reveal(
                delay: const Duration(milliseconds: 430),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: busy ? null : _openReset,
                    child: const Text(
                      'Забыли пароль?',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 6.h),
              Reveal(
                delay: const Duration(milliseconds: 480),
                child: _DemoAccessCard(onTap: _fillDemoCredentials),
              ),
              SizedBox(height: 26.h),
              Reveal(
                delay: const Duration(milliseconds: 540),
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
                      : const Text('Войти'),
                ),
              ),
              SizedBox(height: 16.h),
              Reveal(
                delay: const Duration(milliseconds: 600),
                child: Center(
                  child: TextButton(
                    onPressed: busy
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const RegisterScreen(),
                              ),
                            ),
                    child: RichText(
                      text: TextSpan(
                        text: 'Нет аккаунта? ',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 14.5.sp,
                        ),
                        children: const [
                          TextSpan(
                            text: 'Создать',
                            style: TextStyle(
                              color: AppColors.secondary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
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

class _DemoAccessCard extends StatelessWidget {
  const _DemoAccessCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedTap(
      onTap: onTap,
      scale: 0.98,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 13.h),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(
          children: [
            Icon(Icons.bolt_rounded, size: 18.r, color: AppColors.secondary),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Демо-доступ для ревью',
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    'demo@luma.app · Luma2026',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.content_paste_rounded,
              size: 18.r,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
