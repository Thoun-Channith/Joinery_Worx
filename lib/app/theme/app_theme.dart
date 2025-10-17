import 'package:flutter/material.dart';

class AppTheme {
  // --- Private Color Constants ---
  // The deep navy blue from "JOINERYWORX"
  static const Color primaryDarkBlue = Color(0xFF003366);
  // The vibrant light blue from the accents
  static const Color primaryLightBlue = Color(0xFF00AEEF);
  // A neutral color for text and disabled elements
  static const Color neutralGrey = Color(0xFF6C757D);

  // --- Main ThemeData ---
  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    primaryColor: primaryDarkBlue,
    fontFamily: 'Roboto', // A clean, standard font

    // The ColorScheme is the modern way to define Flutter themes.
    colorScheme: const ColorScheme.light(
      primary: primaryDarkBlue,
      onPrimary: Colors.white, // Text/icons on top of the primary color
      secondary: primaryLightBlue,
      onSecondary: Colors.white, // Text/icons on top of the secondary color
      background: Colors.white,
      onBackground: primaryDarkBlue, // Text on the background
      surface: Color(0xFFF8F9FA), // Color for Cards, Dialogs, etc.
      onSurface: primaryDarkBlue, // Text on surfaces
      error: Colors.redAccent,
      onError: Colors.white,
    ),

    // --- Component Themes ---

    // AppBar Theme
    appBarTheme: const AppBarTheme(
      backgroundColor: primaryDarkBlue,
      foregroundColor: Colors.white, // Color for icons and back button
      elevation: 0.5,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),

    // ElevatedButton Theme
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryLightBlue, // Use the vibrant blue for buttons
        foregroundColor: Colors.white, // White text on buttons
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),

    // Text Theme
    textTheme: const TextTheme(
      displayLarge: TextStyle(color: primaryDarkBlue, fontWeight: FontWeight.bold),
      displayMedium: TextStyle(color: primaryDarkBlue, fontWeight: FontWeight.bold),
      displaySmall: TextStyle(color: primaryDarkBlue, fontWeight: FontWeight.bold),
      headlineMedium: TextStyle(color: primaryDarkBlue, fontWeight: FontWeight.bold),
      headlineSmall: TextStyle(color: primaryDarkBlue, fontWeight: FontWeight.bold),
      titleLarge: TextStyle(color: primaryDarkBlue, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(color: neutralGrey, fontSize: 16),
      bodyMedium: TextStyle(color: neutralGrey, fontSize: 14),
    ),

    // Card Theme
    cardTheme: CardThemeData(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: Colors.white,
      surfaceTintColor: Colors.white,
    ),

    // Input Decoration Theme (for TextFields)
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF8F9FA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryLightBlue, width: 2),
      ),
      prefixIconColor: neutralGrey,
    ),
  );
}