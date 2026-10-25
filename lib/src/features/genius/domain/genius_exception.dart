/// Ошибка при обращении к Genius API.
///
/// Не прячем ошибки в `null` — слой представления сам решает, что показать
/// пользователю: скелетон, сообщение или фолбэк на локальный каталог.
class GeniusException implements Exception {
  const GeniusException(this.statusCode, this.message);

  /// HTTP-код ответа; `0` — ошибка до отправки запроса (конфигурация, сеть).
  final int statusCode;
  final String message;

  @override
  String toString() => 'GeniusException($statusCode): $message';
}

/// Genius не настроен: не задан токен доступа.
class GeniusNotConfiguredException extends GeniusException {
  const GeniusNotConfiguredException()
      : super(
          0,
          'Genius не настроен. Задайте GENIUS_ACCESS_TOKEN через --dart-define.',
        );
}

/// Сеть недоступна или запрос завершился ошибкой транспорта.
class GeniusNetworkException extends GeniusException {
  const GeniusNetworkException(String message) : super(0, message);
}
