import 'package:flutter/material.dart';

/// Фирменная палитра бренда LUMA.
///
/// Все цвета подобраны вручную под «премиальную» тёмную тему стримингового
/// сервиса: глубокий чернильный фон, фиолетово-циановый градиент акцентов
/// и мягкие нейтральные оттенки для текста.
abstract final class AppColors {
  /// Основной фон приложения.
  static const Color ink = Color(0xFF0A0A0F);

  /// Фон карточек и панелей первого уровня.
  static const Color surface = Color(0xFF14141C);

  /// Фон элементов второго уровня (чипы, поля ввода).
  static const Color surfaceHigh = Color(0xFF1E1E2A);

  /// Границы и разделители.
  static const Color outline = Color(0xFF2A2A38);

  /// Основной акцент бренда — фиолетовый.
  static const Color primary = Color(0xFF7C5CFF);

  /// Вторичный акцент — циан.
  static const Color secondary = Color(0xFF22D3EE);

  /// Акцент направления «Музыка».
  static const Color music = Color(0xFFFF4D8D);

  /// Акцент направления «Фильмы».
  static const Color movies = Color(0xFF7C5CFF);

  /// Акцент направления «Аниме».
  static const Color anime = Color(0xFF22D3EE);

  /// Акцент направления «Сериалы».
  static const Color series = Color(0xFFFFB020);

  /// Акцент направления «Мультфильмы».
  static const Color cartoons = Color(0xFF34D399);

  /// Основной цвет текста.
  static const Color textPrimary = Color(0xFFF5F5FA);

  /// Второстепенный цвет текста.
  static const Color textMuted = Color(0xFF8A8AA0);

  /// Цвет успешного состояния.
  static const Color success = Color(0xFF34D399);

  /// Цвет ошибки (соответствует требованиям доступности AA).
  static const Color error = Color(0xFFFF5C7A);

  /// Фирменный градиент LUMA.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, secondary],
  );

  /// Мягкое свечение логотипа.
  static const Color glow = Color(0x557C5CFF);
}
