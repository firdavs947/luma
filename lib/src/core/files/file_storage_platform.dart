import 'file_storage.dart';
import 'file_storage_stub.dart'
    if (dart.library.io) 'file_storage_io.dart' as platform;

/// Создаёт хранилище файлов для текущей платформы.
///
/// Платформенная часть выбирается условным импортом, поэтому один и тот же
/// код библиотеки работает и в нативных приложениях, и в браузере (там
/// хранилище сообщает, что импорт недоступен, и приложение не падает).
FileStorage createFileStorage() => platform.createPlatformFileStorage();
