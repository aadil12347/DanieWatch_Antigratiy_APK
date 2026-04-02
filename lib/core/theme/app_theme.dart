import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  // Backgrounds (Claude Verified)
  static const background = Color(0xFF141413); // Warm charcoal
  static const surface = Color(0xFF1A1A19);
  static const surfaceElevated = Color(0xFF1E1E1E);
  static const card = Color(0xFF27272A); // Zinc 800
  static const input = Color(0xFF18181B); // Zinc 900

  // Brand / Accent (Claude Rust)
  static const primary = Color(0xFFD97757); // Peach/Rust
  static const primaryHover = Color(0xFFC26547);
  static const secondary = Color(0xFF6A9BCC); // Claude Blue accent

  // Text
  static const textPrimary = Color(0xFFE4E4E7); // Zinc 200
  static const textSecondary = Color(0xFFA1A1AA); // Zinc 400
  static const textMuted = Color(0xFF71717A); // Zinc 500
  static const textHint = Color(0xFF52525B); // Zinc 600

  // Status Colors
  static const success = Color(0xFF34D399); // Emerald 400
  static const error = Color(0xFFF87171); // Red 400
  static const errorBg = Color(0x337F1D1D); // Red 900 with 20% opacity

  // Rating colors (Muted for Claude)
  static const ratingHigh = Color(0xFF34D399); // Emerald
  static const ratingMid = Color(0xFFFBBF24); // Amber
  static const ratingLow = Color(0xFFF87171); // Red

  // Dividers / borders
  static const border = Color(0xFF3F3F46); // Zinc 700
  static const divider = Color(0xFF27272A);

  // Gradients
  static const gradientStart = Color(0x00000000);
  static const gradientEnd = Color(0xFF000000);
  static const heroDimGradient = Color(0x99000000);
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final baseTextTheme =
        GoogleFonts.interTextTheme(ThemeData.dark().textTheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        surface: AppColors.background,
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        onSurface: AppColors.textPrimary,
        onPrimary: Colors.white,
        error: AppColors.error,
      ),
      scaffoldBackgroundColor: AppColors.background,
      cardColor: AppColors.card,
      dividerColor: AppColors.divider,

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background.withValues(alpha: 0.95),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.lora(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),

      // Card Theme (Premium 24px)
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      ),

      // Bottom Nav
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.background,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        selectedLabelStyle: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontSize: 11,
        ),
        type: BottomNavigationBarType.fixed,
        elevation: 20,
      ),

      // Text
      textTheme: baseTextTheme.copyWith(
        displayLarge: GoogleFonts.lora(
          fontSize: 36,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
          letterSpacing: -1.0,
        ),
        headlineMedium: GoogleFonts.lora(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        titleLarge: GoogleFonts.lora(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
          height: 1.5,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondary,
          height: 1.5,
        ),
        labelSmall: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textMuted,
          letterSpacing: 0.5,
        ),
      ),

      // Input
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.input,
        hintStyle: const TextStyle(color: AppColors.textHint),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),

      // Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          elevation: 2,
        ),
      ),

      // Scrollbar
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) return const Color(0xFF52525B);
          return const Color(0xFF3F3F46);
        }),
        trackColor: const WidgetStatePropertyAll(Color(0xFF1E1E1E)),
        radius: const Radius.circular(4),
        thickness: const WidgetStatePropertyAll(8),
      ),

      // Icon
      iconTheme: const IconThemeData(color: AppColors.textSecondary, size: 24),
    );
  }
}
