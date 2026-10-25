import 'package:equatable/equatable.dart';

/// События слоя авторизации.
sealed class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

/// Проверка сохранённой сессии при запуске приложения.
class AuthStarted extends AuthEvent {
  const AuthStarted();
}

/// Отправка формы входа.
class AuthSignInSubmitted extends AuthEvent {
  const AuthSignInSubmitted({required this.email, required this.password});

  final String email;
  final String password;

  @override
  List<Object?> get props => [email, password];
}

/// Отправка формы регистрации.
class AuthSignUpSubmitted extends AuthEvent {
  const AuthSignUpSubmitted({
    required this.name,
    required this.email,
    required this.password,
  });

  final String name;
  final String email;
  final String password;

  @override
  List<Object?> get props => [name, email, password];
}

/// Запрос кода восстановления доступа.
class AuthPasswordResetRequested extends AuthEvent {
  const AuthPasswordResetRequested({required this.email});

  final String email;

  @override
  List<Object?> get props => [email];
}

/// Установка нового пароля по коду.
class AuthPasswordResetSubmitted extends AuthEvent {
  const AuthPasswordResetSubmitted({
    required this.email,
    required this.code,
    required this.newPassword,
  });

  final String email;
  final String code;
  final String newPassword;

  @override
  List<Object?> get props => [email, code, newPassword];
}

/// Обновление имени профиля.
class AuthProfileUpdated extends AuthEvent {
  const AuthProfileUpdated({required this.name});

  final String name;

  @override
  List<Object?> get props => [name];
}

/// Выход из аккаунта.
class AuthSignOutRequested extends AuthEvent {
  const AuthSignOutRequested();
}

/// Сброс отображаемой ошибки или информационного сообщения.
class AuthFeedbackDismissed extends AuthEvent {
  const AuthFeedbackDismissed();
}
