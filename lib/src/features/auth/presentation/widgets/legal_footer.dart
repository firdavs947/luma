import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/theme/app_colors.dart';

/// Юридический блок, обязательный для публикации в магазинах приложений.
///
/// Пользователь должен быть проинформирован об обработке данных и
/// правилах сервиса до завершения регистрации.
class LegalFooter extends StatelessWidget {
  const LegalFooter({super.key, this.dense = false});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: dense ? 10.h : 22.h),
      child: Text.rich(
        TextSpan(
          style: TextStyle(
            fontSize: 12.sp,
            height: 1.5,
            color: AppColors.textMuted,
          ),
          children: [
            const TextSpan(text: 'Продолжая, вы принимаете '),
            TextSpan(
              text: 'Условия использования',
              style: TextStyle(
                color: AppColors.textPrimary.withValues(alpha: 0.85),
                fontWeight: FontWeight.w600,
              ),
            ),
            const TextSpan(text: ' и '),
            TextSpan(
              text: 'Политику конфиденциальности',
              style: TextStyle(
                color: AppColors.textPrimary.withValues(alpha: 0.85),
                fontWeight: FontWeight.w600,
              ),
            ),
            const TextSpan(
              text: ' LUMA. Мы не передаём данные третьим лицам '
                  'и храним их в зашифрованном виде.',
            ),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
