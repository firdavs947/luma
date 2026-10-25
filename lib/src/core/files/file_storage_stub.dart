import 'dart:typed_data';

import 'file_storage.dart';

/// Хранилище для платформ без файловой системы (браузер).
///
/// Собственной файловой системы у веб-сборки нет, поэтому импорт музыки там
/// отключён: интерфейс спрашивает [FileStorage.isSupported] и объясняет
/// пользователю, что функция доступна в приложении.
class _UnsupportedFileStorage implements FileStorage {
  const _UnsupportedFileStorage();

  @override
  bool get isSupported => false;

  @override
  Future<String> save({
    required String fileName,
    required Uint8List bytes,
  }) async {
    throw UnsupportedError('Локальное хранилище недоступно на этой платформе');
  }

  @override
  Future<void> delete(String location) async {}

  @override
  Future<bool> exists(String location) async => false;

  @override
  Future<Uint8List?> read(String location) async => null;
}

FileStorage createPlatformFileStorage() => const _UnsupportedFileStorage();
