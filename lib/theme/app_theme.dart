import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static const Color midnight = Color(0xff05070d);
  static const Color panel = Color(0xff10131f);
  static const Color panelStrong = Color(0xff171a29);
  static const Color electricBlue = Color(0xff38bdf8);
  static const Color violet = Color(0xff8b5cf6);
  static const Color pink = Color(0xffec4899);
  static const Color mint = Color(0xff34d399);
  static const Color ink = Color(0xfff8fafc);
  static const Color muted = Color(0xff9ca3af);
  static const Color hairline = Color(0x24ffffff);

  static const LinearGradient accentGradient = LinearGradient(
    colors: [electricBlue, violet, pink],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData get darkTheme {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: 'SF Pro Display',
      scaffoldBackgroundColor: midnight,
      colorScheme: const ColorScheme.dark(
        primary: electricBlue,
        secondary: violet,
        surface: panel,
        error: Color(0xffff6b7a),
      ),
    );

    return base.copyWith(
      splashFactory: InkRipple.splashFactory,
      highlightColor: Colors.white.withOpacity(0.06),
      textTheme: base.textTheme.apply(
        bodyColor: ink,
        displayColor: ink,
        fontFamilyFallback: const ['SF Pro Text', 'Helvetica Neue', 'Arial'],
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withOpacity(0.08),
        hintStyle: const TextStyle(color: muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: const BorderSide(color: electricBlue, width: 1.2),
        ),
      ),
    );
  }
}
