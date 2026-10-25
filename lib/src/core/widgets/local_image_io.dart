import 'dart:io';

import 'package:flutter/widgets.dart';

/// Локальная обложка: файл из приватного каталога приложения.
///
/// Провайдер читает файл сам и кэшируется механизмом картинок Flutter,
/// поэтому повторные показы одной обложки не перечитывают диск.
ImageProvider<Object>? localImageProvider(String location) {
  final uri = Uri.tryParse(location);
  if (uri == null || uri.scheme != 'file') return null;
  return FileImage(File.fromUri(uri));
}
