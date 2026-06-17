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

    return _decorate(base, ink, muted, Colors.white.withOpacity(0.08));
  }

  static ThemeData get lightTheme {
    final base = ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      fontFamily: 'SF Pro Display',
      scaffoldBackgroundColor: const Color(0xfff5f7fb),
      colorScheme: const ColorScheme.light(
        primary: electricBlue,
        secondary: violet,
        surface: Colors.white,
        error: Color(0xffdc2626),
      ),
    );

    return _decorate(base, const Color(0xff111827), const Color(0xff667085), Colors.black.withOpacity(0.05));
  }

  static ThemeData _decorate(ThemeData base, Color textColor, Color hintColor, Color inputFill) {
    return base.copyWith(
      splashFactory: InkRipple.splashFactory,
      highlightColor: base.brightness == Brightness.dark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05),
      textTheme: base.textTheme.apply(
        bodyColor: textColor,
        displayColor: textColor,
        fontFamilyFallback: const ['SF Pro Text', 'Helvetica Neue', 'Arial'],
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        hintStyle: TextStyle(color: hintColor),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: inputFill),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: inputFill),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: const BorderSide(color: electricBlue, width: 1.2),
        ),
      ),
    );
  }
}
