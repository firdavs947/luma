/// Технические требования к импортируемым аудиофайлам.
///
/// Лимиты заданы в одном месте: клиентская валидация в диалоге импорта и
/// проверка при сохранении используют одни и те же константы, поэтому
/// правила не могут разойтись.
abstract final class AudioImportRules {
  /// Максимальный размер аудиофайла — 50 МБ (технические требования LUMA).
  static const int maxAudioBytes = 50 * 1024 * 1024;

  /// Максимальный размер обложки — 8 МБ.
  static const int maxCoverBytes = 8 * 1024 * 1024;

  /// Поддерживаемые форматы аудио.
  static const List<String> audioExtensions = ['mp3', 'wav', 'flac', 'aac'];

  /// Поддерживаемые форматы обложек.
  static const List<String> coverExtensions = ['jpg', 'jpeg', 'png', 'webp'];

  /// Список форматов для подсказки в интерфейсе: `MP3, WAV, FLAC, AAC`.
  static String get audioFormatsLabel =>
      audioExtensions.map((extension) => extension.toUpperCase()).join(', ');

  /// Расширение файла в нижнем регистре, без точки.
  static String extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }

  /// Проверяет формат и размер аудиофайла.
  ///
  /// Возвращает текст ошибки или `null`, если файл допустим.
  static String? validateAudio({required String fileName, required int sizeBytes}) {
    final extension = extensionOf(fileName);

    if (!audioExtensions.contains(extension)) {
      final format = extension.isEmpty
          ? 'Файл без расширения'
          : 'Формат ${extension.toUpperCase()}';
      return '$format не поддерживается. Доступны: $audioFormatsLabel.';
    }
    if (sizeBytes <= 0) return 'Файл пуст — выберите другой.';
    if (sizeBytes > maxAudioBytes) {
      return 'Файл ${formatBytes(sizeBytes)} больше лимита '
          '${formatBytes(maxAudioBytes)}.';
    }
    return null;
  }

  /// Проверяет формат и размер обложки.
  static String? validateCover({required String fileName, required int sizeBytes}) {
    final extension = extensionOf(fileName);

    if (!coverExtensions.contains(extension)) {
      return 'Обложка должна быть в формате '
          '${coverExtensions.map((value) => value.toUpperCase()).join(', ')}.';
    }
    if (sizeBytes <= 0) return 'Файл обложки пуст — выберите другой.';
    if (sizeBytes > maxCoverBytes) {
      return 'Обложка ${formatBytes(sizeBytes)} больше лимита '
          '${formatBytes(maxCoverBytes)}.';
    }
    return null;
  }

  /// Размер файла в удобном для чтения виде: `2,4 МБ`, `860 КБ`.
  static String formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      final megabytes = bytes / (1024 * 1024);
      final precision = megabytes >= 10 ? 0 : 1;
      return '${megabytes.toStringAsFixed(precision).replaceAll('.', ',')} МБ';
    }
    if (bytes >= 1024) return '${(bytes / 1024).round()} КБ';
    return '$bytes Б';
  }
}
