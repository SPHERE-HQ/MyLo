import 'package:flutter/material.dart';

class MyloColors {
  // Primary
  static const primary = Color(0xFF0A84FF);
  static const primaryLight = Color(0xFF4DA6FF);
  static const primaryDark = Color(0xFF0060CC);
  // Secondary
  static const secondary = Color(0xFF7B5EA7);
  static const secondaryLight = Color(0xFFA688D4);
  // Accent
  static const accent = Color(0xFF30D158);
  // Danger / Warning
  static const danger = Color(0xFFFF453A);
  static const warning = Color(0xFFFFD60A);
  // Light mode
  static const background = Color(0xFFF2F2F7);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSecondary = Color(0xFFE5E5EA);
  static const textPrimary = Color(0xFF1C1C1E);
  static const textSecondary = Color(0xFF636366);
  static const textTertiary = Color(0xFFAEAEB2);
  static const border = Color(0xFFD1D1D6);
  // Dark mode
  static const backgroundDark = Color(0xFF000000);
  static const surfaceDark = Color(0xFF1C1C1E);
  static const surfaceSecondaryDark = Color(0xFF2C2C2E);
  static const textPrimaryDark = Color(0xFFFFFFFF);
  static const textSecondaryDark = Color(0xFFEBEBF5);
  static const borderDark = Color(0xFF38383A);
}

class MyloSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
  static const huge = 48.0;
}

class MyloRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const full = 999.0;
}

class MyloTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: MyloColors.primary,
      brightness: Brightness.light,
      background: MyloColors.background,
      surface: MyloColors.surface,
      primary: MyloColors.primary,
      secondary: MyloColors.secondary,
      error: MyloColors.danger,
    ),
    fontFamily: 'Inter',
    scaffoldBackgroundColor: MyloColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: MyloColors.surface,
      foregroundColor: MyloColors.textPrimary,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardTheme(
      color: MyloColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MyloRadius.md),
        side: const BorderSide(color: MyloColors.border, width: 0.5),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MyloColors.surfaceSecondary,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MyloRadius.md),
        borderSide: BorderSide.none,
      ),
      hintStyle: const TextStyle(color: MyloColors.textTertiary),
    ),
  );

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: MyloColors.primary,
      brightness: Brightness.dark,
      background: MyloColors.backgroundDark,
      surface: MyloColors.surfaceDark,
      primary: MyloColors.primary,
      secondary: MyloColors.secondary,
      error: MyloColors.danger,
    ),
    fontFamily: 'Inter',
    scaffoldBackgroundColor: MyloColors.backgroundDark,
    appBarTheme: const AppBarTheme(
      backgroundColor: MyloColors.surfaceDark,
      foregroundColor: MyloColors.textPrimaryDark,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
  );
}
