import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/motion.dart';
import 'bloc/auth_bloc.dart';
import 'bloc/auth_event.dart';
import 'bloc/auth_state.dart';
import '../domain/auth_repository.dart';
import 'widgets/auth_feedback.dart';
import 'widgets/auth_field.dart';
import 'widgets/auth_scaffold.dart';
import 'widgets/legal_footer.dart';

/// Восстановление доступа за два шага: запрос кода и установка пароля.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.initialEmail});

  final String initialEmail;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _emailFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _codeSent = false;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _requestCode() {
    FocusScope.of(context).unfocus();
    if (!(_emailFormKey.currentState?.validate() ?? false)) return;
    context.read<AuthBloc>().add(
          AuthPasswordResetRequested(
            email: Validators.normalize(_emailController.text),
          ),
        );
  }

  void _submitReset() {
    FocusScope.of(context).unfocus();
    if (!(_resetFormKey.currentState?.validate() ?? false)) return;
    context.read<AuthBloc>().add(
          AuthPasswordResetSubmitted(
            email: Validators.normalize(_emailController.text),
            code: _codeController.text,
            newPassword: _passwordController.text,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listenWhen: (previous, current) =>
          previous.resetChallenge != current.resetChallenge ||
          previous.resetCompleted != current.resetCompleted ||
          previous.failure != current.failure ||
          previous.infoMessage != current.infoMessage,
      listener: (context, state) {
        if (state.resetChallenge != null && !_codeSent) {
          setState(() => _codeSent = true);
        }

        if (state.resetCompleted) {
          Navigator.of(context).pop();
        }

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
        final busyRequest = state.isActionInProgress(AuthAction.resetRequest);
        final busySubmit = state.isActionInProgress(AuthAction.resetSubmit);
        final challenge = state.resetChallenge;

        return AuthScaffold(
          title: _codeSent ? 'Новый пароль' : 'Восстановление',
          subtitle: _codeSent
              ? 'Введите код из письма и задайте новый пароль.'
              : 'Укажите e-mail аккаунта — отправим код подтверждения.',
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 420),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.06, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: _codeSent
                  ? _buildResetStep(challenge)
                  : _buildRequestStep(),
            ),
            SizedBox(height: 24.h),
            if (!_codeSent)
              Reveal(
                delay: const Duration(milliseconds: 460),
                child: FilledButton(
                  onPressed: busyRequest ? null : _requestCode,
                  child: busyRequest
                      ? SizedBox.square(
                          dimension: 22.r,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4.r,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Отправить код'),
                ),
              ),
            if (_codeSent)
              Reveal(
                delay: const Duration(milliseconds: 260),
                child: FilledButton(
                  onPressed: busySubmit ? null : _submitReset,
                  child: busySubmit
                      ? SizedBox.square(
                          dimension: 22.r,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4.r,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Сохранить пароль'),
                ),
              ),
            if (_codeSent)
              Reveal(
                delay: const Duration(milliseconds: 320),
                child: Center(
                  child: TextButton(
                    onPressed: busySubmit
                        ? null
                        : () => setState(() {
                              _codeSent = false;
                              _codeController.clear();
                              _passwordController.clear();
                            }),
                    child: const Text(
                      'Изменить e-mail',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            const LegalFooter(dense: true),
          ],
        );
      },
    );
  }

  Widget _buildRequestStep() {
    return Form(
      key: _emailFormKey,
      child: AuthField(
        key: const ValueKey('email-step'),
        label: 'E-mail',
        hint: 'hello@luma.app',
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.email],
        validator: Validators.email,
        onSubmitted: (_) => _requestCode(),
      ),
    );
  }

  Widget _buildResetStep(PasswordResetChallenge? challenge) {
    return Form(
      key: _resetFormKey,
      child: Column(
        key: const ValueKey('reset-step'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (challenge != null)
            Container(
              width: double.infinity,
              margin: EdgeInsets.only(bottom: 20.h),
              padding: EdgeInsets.all(16.r),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(color: AppColors.outline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.mark_email_read_rounded,
                        size: 18.r,
                        color: AppColors.success,
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Text(
                          'Код отправлен на ${challenge.maskedEmail}',
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (challenge.debugCode != null) ...[
                    SizedBox(height: 8.h),
                    Text(
                      'Демо-код: ${challenge.debugCode}',
                      style: TextStyle(
                        fontSize: 12.5.sp,
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          AuthField(
            label: 'Код подтверждения',
            hint: '6 цифр',
            controller: _codeController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            onChanged: (value) => setState(() {}),
            validator: (value) {
              final input = (value ?? '').trim();
              if (input.isEmpty) return 'Введите код из письма';
              if (!RegExp(r'^\d{6}$').hasMatch(input)) {
                return 'Код состоит из 6 цифр';
              }
              return null;
            },
            onSubmitted: (_) {},
          ),
          SizedBox(height: 22.h),
          AuthField(
            label: 'Новый пароль',
            hint: 'Минимум 8 символов',
            controller: _passwordController,
            obscure: true,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            validator: Validators.password,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submitReset(),
          ),
          PasswordStrengthMeter(password: _passwordController.text),
        ],
      ),
    );
  }
}
