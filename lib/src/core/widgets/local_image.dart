import 'package:flutter/widgets.dart';

import 'local_image_stub.dart' if (dart.library.io) 'local_image_io.dart' as impl;

/// Провайдер картинки для файла из каталога приложения.
///
/// Импортированные обложки лежат на устройстве, а не в сети, поэтому
/// стандартный [Image.network] их не покажет. Возвращает `null`, если ссылка
/// не является локальным файлом или платформа не умеет работать с файлами
/// (браузер) — в этом случае обложка остаётся процедурной подложкой LUMA.
ImageProvider<Object>? localImageProvider(String location) =>
    impl.localImageProvider(location);
