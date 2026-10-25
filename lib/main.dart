import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'src/app.dart';
import 'src/core/audio/audio_engine.dart';
import 'src/features/auth/data/mock_auth_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Фоновое воспроизведение: музыка продолжает играть, когда приложение
  // свёрнуто или закрыто, а системный плеер телефона показывает обложку,
  // название и кнопки управления в области уведомлений и на экране блокировки.
  //
  // Инициализация обязана пройти до создания первого AudioPlayer, иначе
  // just_audio не сможет привязать плеер к системному сервису.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.luma.audio.playback',
    androidNotificationChannelName: 'LUMA — воспроизведение',
    androidNotificationChannelDescription: 'Управление текущим треком LUMA',
    // Уведомление не исчезает на паузе: управление остаётся под рукой.
    androidStopForegroundOnPause: false,
  );

  // Интерфейс LUMA адаптивный: он сам подстраивает размеры под габариты
  // устройства, поэтому разрешаем все ориентации — приложение корректно
  // перестраивается при повороте телефона.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Аудиосессия настраивается до первого запуска звука, иначе плеер
  // может играть «в тишину» (см. AudioEngine).
  await AudioEngine.configure();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0A0A0F),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(LumaApp(authRepository: MockAuthRepository()));
}
