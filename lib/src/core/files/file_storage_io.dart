import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'file_storage.dart';

/// Хранилище файлов для платформ с файловой системой.
class _IoFileStorage implements FileStorage {
  /// Подкаталог библиотеки внутри приватного каталога приложения.
  static const String folder = 'library_files';

  @override
  bool get isSupported => true;

  /// Приватный каталог приложения.
  ///
  /// На Android это `/data/user/0/<package>/files`, на iOS —
  /// `Library/Application Support`: содержимое недоступно другим приложениям
  /// и не показывается в файловых менеджерах.
  Future<Directory> _root() async {
    final base = await getApplicationSupportDirectory();
    final directory = Directory(
      '${base.path}${Platform.pathSeparator}$folder',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  @override
  Future<String> save({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final root = await _root();
    final file = File('${root.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.uri.toString();
  }

  @override
  Future<void> delete(String location) async {
    try {
      final file = File.fromUri(Uri.parse(location));
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Файла уже нет — для вызывающей стороны результат тот же.
    }
  }

  @override
  Future<bool> exists(String location) async {
    try {
      return await File.fromUri(Uri.parse(location)).exists();
    } on FileSystemException {
      return false;
    }
  }

  @override
  Future<Uint8List?> read(String location) async {
    try {
      final file = File.fromUri(Uri.parse(location));
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
  }
}

FileStorage createPlatformFileStorage() => _IoFileStorage();
