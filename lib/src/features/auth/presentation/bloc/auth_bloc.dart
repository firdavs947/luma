import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/validators.dart';
import '../../domain/auth_failure.dart';
import '../../domain/auth_repository.dart';
import 'auth_event.dart';
import 'auth_state.dart';

/// BLoC авторизации: управляет сессией, входом, регистрацией
/// и восстановлением доступа.
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc(this._repository) : super(const AuthState()) {
    on<AuthStarted>(_onStarted);
    on<AuthSignInSubmitted>(_onSignIn);
    on<AuthSignUpSubmitted>(_onSignUp);
    on<AuthPasswordResetRequested>(_onResetRequested);
    on<AuthPasswordResetSubmitted>(_onResetSubmitted);
    on<AuthProfileUpdated>(_onProfileUpdated);
    on<AuthSignOutRequested>(_onSignOut);
    on<AuthFeedbackDismissed>(_onFeedbackDismissed);
  }

  final AuthRepository _repository;

  Future<void> _onStarted(AuthStarted event, Emitter<AuthState> emit) async {
    emit(state.copyWith(action: AuthAction.login));
    try {
      final user = await _repository.restoreSession();
      emit(
        state.copyWith(
          status: user == null
              ? AuthStatus.unauthenticated
              : AuthStatus.authenticated,
          user: user,
          clearAction: true,
        ),
      );
    } on AuthFailure catch (failure) {
      emit(
        state.copyWith(
          status: AuthStatus.unauthenticated,
          failure: failure,
          clearAction: true,
        ),
      );
    }
  }

  Future<void> _onSignIn(
    AuthSignInSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    // Повторная проверка на стороне BLoC — защита от обхода UI-валидации.
    final emailError = Validators.email(event.email);
    final passwordError = Validators.password(event.password);
    if (emailError != null || passwordError != null) {
      emit(
        state.copyWith(
          failure: AuthFailure(
            AuthErrorCode.invalidCredentials,
            message: emailError ?? passwordError,
          ),
        ),
      );
      return;
    }

    emit(state.copyWith(action: AuthAction.login, clearFailure: true));
    try {
      final user = await _repository.signIn(
        email: event.email,
        password: event.password,
      );
      emit(
        state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          infoMessage: 'С возвращением, ${user.name}!',
          clearAction: true,
        ),
      );
    } on AuthFailure catch (failure) {
      emit(state.copyWith(failure: failure, clearAction: true));
    } catch (_) {
      emit(
        state.copyWith(
          failure: const AuthFailure(AuthErrorCode.unknown),
          clearAction: true,
        ),
      );
    }
  }

  Future<void> _onSignUp(
    AuthSignUpSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    final nameError = Validators.name(event.name);
    final emailError = Validators.email(event.email);
    final passwordError = Validators.password(event.password);
    final firstError = nameError ?? emailError ?? passwordError;
    if (firstError != null) {
      emit(state.copyWith(failure: AuthFailure(
        AuthErrorCode.weakPassword,
        message: firstError,
      )));
      return;
    }

    emit(state.copyWith(action: AuthAction.register, clearFailure: true));
    try {
      final user = await _repository.signUp(
        name: event.name,
        email: event.email,
        password: event.password,
      );
      emit(
        state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          infoMessage: 'Аккаунт создан. Добро пожаловать в LUMA!',
          clearAction: true,
        ),
      );
    } on AuthFailure catch (failure) {
      emit(state.copyWith(failure: failure, clearAction: true));
    } catch (_) {
      emit(
        state.copyWith(
          failure: const AuthFailure(AuthErrorCode.unknown),
          clearAction: true,
        ),
      );
    }
  }

  Future<void> _onResetRequested(
    AuthPasswordResetRequested event,
    Emitter<AuthState> emit,
  ) async {
    final emailError = Validators.email(event.email);
    if (emailError != null) {
      emit(state.copyWith(
        failure: AuthFailure(AuthErrorCode.userNotFound, message: emailError),
      ));
      return;
    }

    emit(state.copyWith(action: AuthAction.resetRequest, clearFailure: true));
    try {
      final challenge = await _repository.requestPasswordReset(
        email: event.email,
      );
      emit(
        state.copyWith(
          resetChallenge: challenge,
          infoMessage: 'Код подтверждения отправлен на ${challenge.maskedEmail}',
          clearAction: true,
        ),
      );
    } on AuthFailure catch (failure) {
      emit(state.copyWith(failure: failure, clearAction: true));
    } catch (_) {
      emit(
        state.copyWith(
          failure: const AuthFailure(AuthErrorCode.network),
          clearAction: true,
        ),
      );
    }
  }

  Future<void> _onResetSubmitted(
    AuthPasswordResetSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    if (event.code.trim().length != 6) {
      emit(state.copyWith(
        failure: const AuthFailure(
          AuthErrorCode.invalidResetCode,
          message: 'Код состоит из 6 цифр',
        ),
      ));
      return;
    }

    final passwordError = Validators.password(event.newPassword);
    if (passwordError != null) {
      emit(state.copyWith(
        failure: AuthFailure(AuthErrorCode.weakPassword, message: passwordError),
      ));
      return;
    }

    emit(state.copyWith(action: AuthAction.resetSubmit, clearFailure: true));
    try {
      await _repository.resetPassword(
        email: event.email,
        code: event.code,
        newPassword: event.newPassword,
      );
      emit(
        state.copyWith(
          resetCompleted: true,
          infoMessage: 'Пароль обновлён. Войдите с новым паролем.',
          clearAction: true,
          clearReset: true,
        ),
      );
    } on AuthFailure catch (failure) {
      emit(state.copyWith(failure: failure, clearAction: true));
    }
  }

  Future<void> _onProfileUpdated(
    AuthProfileUpdated event,
    Emitter<AuthState> emit,
  ) async {
    final nameError = Validators.name(event.name);
    if (nameError != null) {
      emit(state.copyWith(
        failure: AuthFailure(AuthErrorCode.unknown, message: nameError),
      ));
      return;
    }

    emit(state.copyWith(action: AuthAction.profileUpdate, clearFailure: true));
    try {
      final user = await _repository.updateProfile(name: event.name);
      emit(
        state.copyWith(
          user: user,
          infoMessage: 'Профиль обновлён',
          clearAction: true,
        ),
      );
    } on AuthFailure catch (failure) {
      emit(state.copyWith(failure: failure, clearAction: true));
    }
  }

  Future<void> _onSignOut(
    AuthSignOutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(action: AuthAction.signOut, clearFailure: true));
    await _repository.signOut();
    emit(
      const AuthState(
        status: AuthStatus.unauthenticated,
        infoMessage: 'Вы вышли из аккаунта',
      ),
    );
  }

  void _onFeedbackDismissed(
    AuthFeedbackDismissed event,
    Emitter<AuthState> emit,
  ) {
    emit(state.copyWith(clearFailure: true, clearInfo: true));
  }
}
