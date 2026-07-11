import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Dark futuristic background gradients
  static const Color backgroundStart = Color(0xFF0F172A); // Deep slate dark
  static const Color backgroundEnd = Color(0xFF020617);   // Midnight black

  // Glassmorphic styling constants
  static const Color cardColor = Color(0x0EFFFFFF); // 5.5% white opacity
  static const Color cardBorder = Color(0x1BFFFFFF); // 10.5% white opacity

  // Premium Neon Accents
  static const Color primaryCyan = Color(0xFF06B6D4);     // Cyan highlight
  static const Color primaryCyanGlow = Color(0xFF22D3EE); // Bright cyan glow
  static const Color accentPurple = Color(0xFF8B5CF6);    // Electric violet
  static const Color accentPink = Color(0xFFEC4899);      // Pink accent
  
  static const Color textDark = Color(0xFFF8FAFC);        // Crisp off-white for primary text
  static const Color textLight = Color(0xFF94A3B8);       // Slate gray for secondary text

  static const Color accentGreen = Color(0xFF10B981);     // Emerald green (positive/safe)
  static const Color accentRed = Color(0xFFEF4444);       // Bright crimson (warning/alert)

  static ThemeData get theme {
    return ThemeData(
      primaryColor: primaryCyan,
      scaffoldBackgroundColor: Colors.transparent, // Gradient applied in wrapper
      brightness: Brightness.dark,
      textTheme: GoogleFonts.outfitTextTheme().copyWith(
        displayLarge: GoogleFonts.outfit(color: textDark, fontWeight: FontWeight.bold, fontSize: 32),
        bodyLarge: GoogleFonts.outfit(color: textDark, fontSize: 16),
        bodyMedium: GoogleFonts.outfit(color: textLight, fontSize: 14),
      ),
      colorScheme: const ColorScheme.dark(
        primary: primaryCyan,
        secondary: accentPurple,
        surface: backgroundStart,
      ),
    );
  }

  static BoxDecoration get backgroundGradient {
    return const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [backgroundStart, backgroundEnd],
      ),
    );
  }
}
