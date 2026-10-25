import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/theme/app_colors.dart';

/// Единый способ показать сообщение об ошибке или успехе.
abstract final class AuthFeedback {
  static void show(
    BuildContext context, {
    required String message,
    bool isError = false,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          backgroundColor: isError
              ? AppColors.error.withValues(alpha: 0.16)
              : AppColors.surfaceHigh,
          content: Row(
            children: [
              Container(
                padding: EdgeInsets.all(7.r),
                decoration: BoxDecoration(
                  color: (isError ? AppColors.error : AppColors.success)
                      .withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isError
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  size: 18.r,
                  color: isError ? AppColors.error : AppColors.success,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 13.5.sp,
                    fontWeight: FontWeight.w600,
                    color: isError ? AppColors.error : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }
}
