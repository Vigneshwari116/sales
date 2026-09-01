import 'package:flutter/material.dart';

/// Single source of truth for colors and font sizes across the whole app.
/// Import this anywhere instead of hardcoding Colors.xxx or fontSize
/// values, so changing the look later only means editing this one file.
class AppColors {
  AppColors._();

  static const background = Color(0xFFEEF1F4);
  static const headerBand = Color(0xFFE4E9EF);
  static const navy = Color(0xFF2C3E50);
  static const mutedBlue = Color(0xFF5B7A8E);
  static const tableHeader = Color(0xFFD9DFE6);
  static const border = Color(0xFFD3D9E0);
  static const cardWhite = Colors.white;
  static const accentBlue = Color(0xFF1E4E76);
  static const drawerNavy = Color(0xFF1B2A38);
  static const drawerActive = Color(0xFF3D6A8A);
  static const tabActive = Color(0xFF3D5A73);
  static const danger = Color(0xFF9C1C1C);
  static const success = Color(0xFF155724);
  static const warningBg = Color(0xFFFFF3CD);
  static const warningFg = Color(0xFF856404);
  static const successBg = Color(0xFFD4EDDA);
}

class AppTextSizes {
  AppTextSizes._();

  static const appBarTitle = 16.0;
  static const statNumber = 22.0;
  static const statLabel = 12.5;
  static const sectionHeader = 13.0;
  static const fieldLabel = 13.0;
  static const fieldText = 14.0;
  static const listTitle = 13.0;
  static const listSubtitle = 11.5;
  static const buttonText = 13.0;
  static const tableHeaderText = 12.5;
  static const tableRowText = 12.5;
}

class AppTheme {
  AppTheme._();

  static ThemeData get theme {
    return ThemeData(
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.navy,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.navy,
        primary: AppColors.navy,
        background: AppColors.background,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.headerBand,
        foregroundColor: AppColors.navy,
        centerTitle: true,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.navy),
        actionsIconTheme: IconThemeData(color: AppColors.navy),
        titleTextStyle: TextStyle(
          fontSize: AppTextSizes.appBarTitle,
          fontWeight: FontWeight.w600,
          color: AppColors.navy,
        ),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(fontSize: AppTextSizes.fieldText),
        bodyMedium: TextStyle(fontSize: AppTextSizes.listTitle),
        bodySmall: TextStyle(fontSize: AppTextSizes.listSubtitle),
        titleLarge: TextStyle(
            fontSize: AppTextSizes.statNumber, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(
            fontSize: AppTextSizes.sectionHeader, fontWeight: FontWeight.w600),
        labelLarge: TextStyle(fontSize: AppTextSizes.buttonText),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        filled: true,
        fillColor: AppColors.cardWhite,
        labelStyle: const TextStyle(
            fontSize: AppTextSizes.fieldLabel, color: AppColors.mutedBlue),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        errorStyle: const TextStyle(fontSize: 11),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(
              fontSize: AppTextSizes.buttonText, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.navy,
          textStyle: const TextStyle(fontSize: AppTextSizes.buttonText),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardWhite,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        dense: true,
        titleTextStyle: TextStyle(
            fontSize: AppTextSizes.listTitle,
            fontWeight: FontWeight.w600,
            color: AppColors.navy),
        subtitleTextStyle: TextStyle(
            fontSize: AppTextSizes.listSubtitle, color: Colors.black54),
      ),
      useMaterial3: true,
    );
  }
}
