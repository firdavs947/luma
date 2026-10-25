import 'app_user.dart';

/// Результат запроса на восстановление доступа.
///
/// Содержит замаскированный адрес и — только в debug-сборке — код
/// подтверждения, чтобы сценарий можно было пройти в демо-режиме.
class PasswordResetChallenge {
  const PasswordResetChallenge({
    required this.email,
    required this.maskedEmail,
    this.debugCode,
  });

  final String email;

  /// Адрес в виде `us**@do**in.com`.
  final String maskedEmail;

  /// Код подтверждения. `null` в release-сборке.
  final String? debugCode;
}

/// Контракт репозитория аутентификации.
///
/// Позволяет подменить реализацию (локальный мок, REST, Firebase)
/// без изменения слоя представления и BLoC.
abstract interface class AuthRepository {
  /// Восстанавливает сохранённую сессию при запуске приложения.
  Future<AppUser?> restoreSession();

  /// Вход по e-mail и паролю.
  Future<AppUser> signIn({required String email, required String password});

  /// Регистрация нового пользователя.
  Future<AppUser> signUp({
    required String name,
    required String email,
    required String password,
  });

  /// Запрос кода восстановления доступа.
  Future<PasswordResetChallenge> requestPasswordReset({required String email});

  /// Установка нового пароля по коду подтверждения.
  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  });

  /// Завершение сессии.
  Future<void> signOut();

  /// Обновление профиля текущего пользователя.
  Future<AppUser> updateProfile({required String name});
}
