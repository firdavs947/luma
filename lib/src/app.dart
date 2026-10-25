import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'core/audio/streaming_track_resolver.dart';
import 'core/audio/track_stream_resolver.dart';
import 'core/files/file_storage_platform.dart';
import 'core/responsive/responsive.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/domain/auth_repository.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/auth/presentation/bloc/auth_event.dart';
import 'features/auth/presentation/bloc/auth_state.dart';
import 'features/catalog/data/archive_video_source.dart';
import 'features/catalog/data/audius_music_source.dart';
import 'features/catalog/data/genius_music_source.dart';
import 'features/catalog/data/mock_music_source.dart';
import 'features/catalog/domain/video_source.dart';
import 'features/catalog/presentation/bloc/catalog_cubit.dart';
import 'features/genius/data/genius_repository_impl.dart';
import 'features/genius/domain/genius_repository.dart';
import 'features/home/presentation/home_screen.dart';
import 'features/library/data/local_imported_audio_repository.dart';
import 'features/library/domain/imported_audio_repository.dart';
import 'features/library/presentation/library_cubit.dart';
import 'features/splash/splash_screen.dart';

/// Корневое приложение LUMA.
///
/// Здесь собирается граф зависимостей: репозиторий авторизации, источник
/// музыки Genius и Cubit каталога. Экраны получают зависимости из контекста,
/// поэтому конкретную реализацию можно заменить, не трогая интерфейс.
class LumaApp extends StatelessWidget {
  const LumaApp({super.key, required this.authRepository});

  final AuthRepository authRepository;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        // Ключ Genius приходит из окружения (--dart-define). Если он не
        // задан, источник сам переключится на локальный фолбэк.
        RepositoryProvider<GeniusRepository>(
          create: (_) => GeniusRemoteRepository.fromEnvironment(),
        ),
        // Библиотека загруженной музыки: файлы лежат в приватном каталоге
        // приложения, метаданные — в локальном манифесте.
        RepositoryProvider<ImportedAudioRepository>(
          create: (_) => LocalImportedAudioRepository(createFileStorage()),
        ),
        // Некоторые элементы могут прийти без готовой ссылки на звук
        // (например, метаданные Genius) — для них запись подбирает
        // стриминговый резолвер, который тоже работает с полными версиями.
        RepositoryProvider<TrackStreamResolver>(
          create: (_) => StreamingTrackResolver(),
        ),
        // Видеоконтент: фильмы, аниме, мультфильмы и сериалы из Internet
        // Archive. Ключ не нужен, контент легальный, квот нет. Тот же
        // экземпляр использует плеер, чтобы разрешать поток выбранного
        // качества под скорость соединения.
        RepositoryProvider<VideoSource>(create: (_) => ArchiveVideoSource()),
      ],
      child: Builder(
        builder: (context) => MultiBlocProvider(
          providers: [
            BlocProvider<AuthBloc>(
              create: (_) => AuthBloc(authRepository)..add(const AuthStarted()),
            ),
            BlocProvider<CatalogCubit>(
              create: (context) => CatalogCubit(
                // Видеокаталог приходит из Internet Archive: он покрывает
                // все четыре видеонаправления и отдаёт готовые потоки.
                videoSource: context.read<VideoSource>(),
                // Основной источник — Audius: он отдаёт полные версии треков
                // из неограниченной библиотеки и умеет постраничный поиск.
                // Genius остаётся резервом на случай недоступности каталога,
                // а локальный набор — последней страховкой.
                musicSource: AudiusMusicSource(
                  fallback: GeniusMusicSource(
                    repository: context.read<GeniusRepository>(),
                    fallback: const MockMusicSource(),
                  ),
                ),
              )..load(),
            ),
            BlocProvider<LibraryCubit>(
              create: (context) =>
                  LibraryCubit(context.read<ImportedAudioRepository>())..load(),
            ),
          ],
          child: ScreenUtilInit(
            // Опорный размер, под который свёрстан интерфейс LUMA (390×844 dp).
            // Любое устройство пересчитывается относительно него, поэтому
            // пропорции сохраняются и на узком экране 320 dp, и на планшете.
            designSize: DesignSpec.base,
            // В ландшафте высота экрана меньше опорной: без этого флага
            // вертикальный коэффициент провалился бы и элементы «сплющились».
            splitScreenMode: true,
            minTextAdapt: true,
            // Текст масштабируем по меньшей стороне: так строки не раздуваются
            // при повороте в горизонтальную ориентацию.
            fontSizeResolver: FontSizeResolvers.radius,
            // Перестраиваем дерево при смене размера экрана — это же событие
            // приходит и при повороте устройства.
            rebuildFactor: RebuildFactors.size,
            // На планшетах и десктопах пропорциональный масштаб отключается:
            // крупный экран выигрывает не гигантскими карточками, а тем, что
            // в него влезает больше контента. Сетки при этом перестраиваются
            // по фактической ширине (см. `gridColumnsFor`).
            enableScaleWH: () => isProportionalScalingEnabled,
            enableScaleText: () => isProportionalScalingEnabled,
            builder: (context, child) => MaterialApp(
              title: 'LUMA',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.dark,
              themeMode: ThemeMode.dark,
              darkTheme: AppTheme.dark,
              locale: const Locale('ru'),
              supportedLocales: const [Locale('ru'), Locale('en')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder: (context, child) {
                // Ограничиваем системный масштаб текста, чтобы вёрстка
                // оставалась стабильной на всех разрешениях.
                final mediaQuery = MediaQuery.of(context);
                return MediaQuery(
                  data: mediaQuery.copyWith(
                    textScaler: mediaQuery.textScaler.clamp(
                      minScaleFactor: 0.9,
                      maxScaleFactor: 1.3,
                    ),
                  ),
                  child: child ?? const SizedBox.shrink(),
                );
              },
              home: const AuthGate(),
            ),
          ),
        ),
      ),
    );
  }
}

/// Переключатель между сплэшем, экранами авторизации и домашним экраном.
///
/// Пока сессия не подтверждена, отображается анимированный сплэш;
/// после входа — домашний экран. Переход всегда выполняется по действию
/// пользователя либо по результату восстановления сессии.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (previous, current) => previous.status != current.status,
      listener: (context, state) {
        if (state.status == AuthStatus.authenticated) {
          // Закрываем все служебные маршруты поверх домашнего экрана.
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      },
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 520),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
                child: child,
              ),
            ),
            child: state.isAuthenticated
                ? const HomeScreen(key: ValueKey('home'))
                : const SplashScreen(key: ValueKey('splash')),
          );
        },
      ),
    );
  }
}

/// Единый фон приложения с фирменным градиентным свечением.
class BrandBackdrop extends StatelessWidget {
  const BrandBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.7, -1.0),
          radius: 1.5,
          colors: [Color(0x337C5CFF), AppColors.ink],
          stops: [0, 0.65],
        ),
      ),
      child: child,
    );
  }
}
