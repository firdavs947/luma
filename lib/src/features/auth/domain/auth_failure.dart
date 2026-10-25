import 'package:equatable/equatable.dart';

/// Коды ошибок авторизации.
enum AuthErrorCode {
  invalidCredentials,
  emailAlreadyInUse,
  userNotFound,
  weakPassword,
  invalidResetCode,
  network,
  unknown,
}

/// Доменная ошибка авторизации.
///
/// Наружу отдаётся только безопасное пользовательское сообщение:
/// внутренние детали и различия между «нет пользователя» и «неверный пароль»
/// не раскрываются, чтобы исключить перечисление аккаунтов.
class AuthFailure extends Equatable implements Exception {
  const AuthFailure(this.code, {this.message});

  final AuthErrorCode code;
  final String? message;

  String get userMessage {
    if (message != null) return message!;
    return switch (code) {
      AuthErrorCode.invalidCredentials =>
        'Неверный e-mail или пароль. Проверьте данные и попробуйте снова.',
      AuthErrorCode.emailAlreadyInUse =>
        'Аккаунт с таким e-mail уже существует. Войдите или восстановите пароль.',
      AuthErrorCode.userNotFound =>
        'Не удалось найти аккаунт с указанным e-mail.',
      AuthErrorCode.weakPassword =>
        'Пароль слишком простой. Используйте буквы и цифры, минимум 8 символов.',
      AuthErrorCode.invalidResetCode =>
        'Код подтверждения неверен или истёк. Запросите новый код.',
      AuthErrorCode.network =>
        'Нет соединения. Проверьте интернет и повторите попытку.',
      AuthErrorCode.unknown => 'Что-то пошло не так. Повторите попытку позже.',
    };
  }

  @override
  List<Object?> get props => [code, message];
}
