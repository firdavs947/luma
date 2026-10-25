/// Ошибка импорта аудиофайла.
///
/// Сообщение готово к показу пользователю: оно объясняет, что не так с
/// файлом, и не раскрывает внутреннее устройство приложения.
class AudioImportException implements Exception {
  const AudioImportException(this.message);

  /// Текст для интерфейса.
  final String message;

  @override
  String toString() => 'AudioImportException: $message';
}
