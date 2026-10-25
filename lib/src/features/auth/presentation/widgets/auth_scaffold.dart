import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/luma_logo.dart';
import '../../../../core/widgets/motion.dart';

/// Общая оболочка экранов авторизации.
///
/// Обеспечивает единый фирменный фон, адаптивную прокрутку и
/// каскадное появление элементов.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.showBackButton = true,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.8, -1.05),
            radius: 1.6,
            colors: [Color(0x337C5CFF), AppColors.ink],
            stops: [0, 0.6],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(28.w, 8.h, 28.w, 28.h + bottomInset),
            children: [
              if (showBackButton)
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: AppColors.textPrimary,
                      tooltip: 'Назад',
                    ),
                  ],
                )
              else
                SizedBox(height: 40.h),
              SizedBox(height: 8.h),
              Reveal(
                delay: const Duration(milliseconds: 40),
                child: Row(
                  children: [
                    LumaLogo(size: 54.r, pulse: true, glow: true),
                    SizedBox(width: 14.w),
                    LumaWordmark(fontSize: 25.sp),
                  ],
                ),
              ),
              SizedBox(height: 34.h),
              Reveal(
                delay: const Duration(milliseconds: 130),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 34.sp,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.1,
                    height: 1.06,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              SizedBox(height: 12.h),
              Reveal(
                delay: const Duration(milliseconds: 210),
                child: Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 15.sp,
                    color: AppColors.textMuted,
                    height: 1.45,
                  ),
                ),
              ),
              SizedBox(height: 32.h),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
