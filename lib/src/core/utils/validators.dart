/// Валидаторы пользовательского ввода.
///
/// Все проверки выполняются на стороне клиента для мгновенной обратной связи.
/// Сообщения об ошибках не раскрывают внутреннюю логику сервиса и
/// соответствуют требованиям безопасности магазинов приложений.
abstract final class Validators {
  /// Максимально допустимая длина пользовательских строк.
  static const int maxNameLength = 40;
  static const int maxEmailLength = 254;
  static const int minPasswordLength = 8;
  static const int maxSearchLength = 60;

  static final RegExp _emailRegExp = RegExp(
    r'^[\w.!#$%&’*+/=?^`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+$',
  );
  static final RegExp _digitsOnly = RegExp(r'^\d+$');
  static final RegExp _safeSearch =
      RegExp(r"^[\p{L}\p{N}\s_.!?&:'()-]+$", unicode: true);

  /// Проверка имени пользователя.
  static String? name(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return 'Введите имя';
    if (input.length < 2) return 'Имя слишком короткое';
    if (input.length > maxNameLength) return 'Не более $maxNameLength символов';
    if (_digitsOnly.hasMatch(input)) return 'Имя не может состоять из цифр';
    return null;
  }

  /// Проверка адреса электронной почты.
  static String? email(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return 'Введите e-mail';
    if (input.length > maxEmailLength) return 'Адрес слишком длинный';
    if (!_emailRegExp.hasMatch(input)) return 'Некорректный e-mail';
    return null;
  }

  /// Проверка пароля с политикой сложности.
  static String? password(String? value) {
    final input = value ?? '';
    if (input.isEmpty) return 'Введите пароль';
    if (input.length < minPasswordLength) {
      return 'Минимум $minPasswordLength символов';
    }
    if (!RegExp(r'[A-Za-zА-Яа-я]').hasMatch(input)) {
      return 'Добавьте хотя бы одну букву';
    }
    if (!RegExp(r'\d').hasMatch(input)) return 'Добавьте хотя бы одну цифру';
    if (input.contains(' ')) return 'Пароль не должен содержать пробелы';
    return null;
  }

  /// Проверка подтверждения пароля.
  static String? confirmPassword(String? value, String original) {
    if ((value ?? '').isEmpty) return 'Повторите пароль';
    if (value != original) return 'Пароли не совпадают';
    return null;
  }

  /// Проверка поискового запроса на домашнем экране.
  static String? searchQuery(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return 'Введите поисковый запрос';
    if (input.length < 2) return 'Минимум 2 символа';
    if (input.length > maxSearchLength) {
      return 'Не более $maxSearchLength символов';
    }
    if (!_safeSearch.hasMatch(input)) return 'Запрос содержит недопустимые символы';
    return null;
  }

  /// Оценка надёжности пароля от 0 до 1 — используется в индикаторе силы.
  static double passwordStrength(String value) {
    if (value.isEmpty) return 0;

    var score = 0.0;
    if (value.length >= minPasswordLength) score += 0.3;
    if (value.length >= 12) score += 0.15;
    if (RegExp(r'[a-zа-я]').hasMatch(value)) score += 0.15;
    if (RegExp(r'[A-ZА-Я]').hasMatch(value)) score += 0.15;
    if (RegExp(r'\d').hasMatch(value)) score += 0.15;
    if (RegExp(r'[^\w\s]').hasMatch(value)) score += 0.1;

    return score.clamp(0.0, 1.0);
  }

  /// Простая нормализация пользовательского ввода перед отправкой.
  static String normalize(String value) => value.trim();
}
