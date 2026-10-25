/// Конфигурация доступа к Genius API.
///
/// Токен задаётся при сборке, а не «зашит» в логику:
///   flutter run --dart-define=GENIUS_ACCESS_TOKEN=xxx
///
/// Значение по умолчанию — рабочий Client Access Token проекта, поэтому
/// приложение запускается сразу. Для продакшена вызовы Genius лучше
/// проксировать через свой бэкенд: приложение работает через интерфейс
/// `GeniusRepository`, поэтому достаточно заменить реализацию.
class GeniusConfig {
  const GeniusConfig({required this.accessToken});

  /// Читает токен из `--dart-define`.
  factory GeniusConfig.fromEnvironment() => const GeniusConfig(
        accessToken: String.fromEnvironment(
          'GENIUS_ACCESS_TOKEN',
          defaultValue: 'NUXmeODJbCAzGevuhhe4DKIpIhZAkEOBEidzANiADA5ukaAsZNSBbHMYmIeNJFbL',
        ),
      );

  /// Client Access Token, полученный на genius.com/api-clients.
  final String accessToken;

  bool get isConfigured => accessToken.isNotEmpty;
}
