import 'package:flutter/material.dart';

const Color kPrimary = Color(0xFF6C63FF);
const Color kSecondary = Color(0xFF03DAC6);
const Color kBackground = Color(0xFF0D0D1A);
const Color kSurface = Color(0xFF16162D);
const Color kCardColor = Color(0xFF1F1F3E);
const Color kError = Color(0xFFCF6679);
const Color kOnPrimary = Colors.white;

ThemeData get appTheme {
  return ThemeData.dark().copyWith(
    useMaterial3: true,
    colorScheme: const ColorScheme.dark(
      primary: kPrimary,
      secondary: kSecondary,
      surface: kSurface,
      error: kError,
      onPrimary: kOnPrimary,
    ),
    scaffoldBackgroundColor: kBackground,
    cardTheme: CardThemeData(
      color: kCardColor,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kCardColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kPrimary, width: 1.5),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kPrimary,
        foregroundColor: kOnPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),
  );
}

BoxDecoration get glassDecoration {
  return BoxDecoration(
    color: kCardColor.withOpacity(0.85),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      color: Colors.white.withOpacity(0.1),
      width: 1.0,
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.3),
        blurRadius: 12,
        offset: const Offset(0, 4),
      )
    ],
  );
}
