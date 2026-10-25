import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/app_colors.dart';
import '../../catalog/presentation/bloc/catalog_cubit.dart';
import 'tabs/home_tab.dart';
import 'tabs/library_tab.dart';
import 'tabs/profile_tab.dart';
import 'tabs/search_tab.dart';
import '../../player/presentation/widgets/mini_player.dart';
import 'widgets/luma_bottom_nav.dart';

/// Домашний экран приложения: каталог, поиск, библиотека и профиль.
///
/// Разделы переключаются плавной анимацией `PageView`, состояние каждого
/// раздела сохраняется.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _pageController = PageController();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestNotificationPermission();
  }

  /// Возврат из фона — повод обновить новинки.
  ///
  /// Каталог обновляется сам по таймеру, но телефон мог спать несколько
  /// часов: проверка устаревания сразу после возврата показывает свежие
  /// релизы без ручного обновления.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(context.read<CatalogCubit>().refreshIfStale());
    }
  }

  /// Запрос разрешения на уведомления для Android 13+.
  ///
  /// Без этого системный плеер не сможет показать карточку управления в
  /// области уведомлений, и фоновое воспроизведение будет нестабильным.
  Future<void> _requestNotificationPermission() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    if (index == _index) return;
    setState(() => _index = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  /// Поиск с домашнего экрана: запрос валидируется и открывает раздел поиска.
  Future<void> _searchFromHome(String query) async {
    final accepted = await context.read<CatalogCubit>().search(query);
    if (!accepted || !mounted) return;
    _selectTab(1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      extendBody: true,
      body: Stack(
        children: [
          // Фирменное свечение в верхней части экрана.
          Positioned(
            top: -180.h,
            left: -80.w,
            right: -80.w,
            height: 420.h,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [Color(0x337C5CFF), Colors.transparent],
                  stops: [0, 0.7],
                ),
              ),
            ),
          ),
          PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            onPageChanged: (value) => setState(() => _index = value),
            children: [
              HomeTab(onSearchSubmitted: _searchFromHome),
              const SearchTab(),
              const LibraryTab(),
              const ProfileTab(),
            ],
          ),
          // Мини-плеер, который всегда виден над навигацией при наличии музыки.
          Positioned(
            left: 0,
            right: 0,
            bottom: 112.h, // Значительно подняли, чтобы избежать тесноты и наложения на навбар
            child: const MiniPlayer(),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: LumaBottomNav(currentIndex: _index, onSelect: _selectTab),
      ),
    );
  }
}
