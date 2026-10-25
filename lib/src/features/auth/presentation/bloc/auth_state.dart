import 'package:equatable/equatable.dart';

import '../../domain/app_user.dart';
import '../../domain/auth_failure.dart';
import '../../domain/auth_repository.dart';

/// Статус авторизации приложения.
enum AuthStatus {
  /// Сессия ещё не проверена.
  unknown,

  /// Пользователь не авторизован.
  unauthenticated,

  /// Пользователь авторизован.
  authenticated,
}

/// Совершаемое действие — используется для точечной индикации загрузки.
enum AuthAction { login, register, resetRequest, resetSubmit, profileUpdate, signOut }

/// Состояние слоя авторизации.
class AuthState extends Equatable {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.action,
    this.failure,
    this.infoMessage,
    this.resetChallenge,
    this.resetCompleted = false,
  });

  final AuthStatus status;
  final AppUser? user;

  /// Текущее выполняемое действие (для лоадеров на кнопках).
  final AuthAction? action;

  /// Последняя ошибка, требующая отображения пользователю.
  final AuthFailure? failure;

  /// Информационное сообщение (например, «код отправлен»).
  final String? infoMessage;

  /// Данные текущего сценария восстановления доступа.
  final PasswordResetChallenge? resetChallenge;

  /// Пароль успешно изменён.
  final bool resetCompleted;

  bool get isBusy => action != null;
  bool get isAuthenticated => status == AuthStatus.authenticated;

  bool isActionInProgress(AuthAction value) => action == value;

  AuthState copyWith({
    AuthStatus? status,
    AppUser? user,
    AuthAction? action,
    AuthFailure? failure,
    String? infoMessage,
    PasswordResetChallenge? resetChallenge,
    bool? resetCompleted,
    bool clearAction = false,
    bool clearFailure = false,
    bool clearInfo = false,
    bool clearReset = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      action: clearAction ? null : (action ?? this.action),
      failure: clearFailure ? null : (failure ?? this.failure),
      infoMessage: clearInfo ? null : (infoMessage ?? this.infoMessage),
      resetChallenge:
          clearReset ? null : (resetChallenge ?? this.resetChallenge),
      resetCompleted: resetCompleted ?? this.resetCompleted,
    );
  }

  @override
  List<Object?> get props => [
        status,
        user,
        action,
        failure,
        infoMessage,
        resetChallenge,
        resetCompleted,
      ];
}
