import 'package:flutter/material.dart';

class AppTheme {
  static const Color blue = Color(0xff246bfd);
  static const Color deepBlue = Color(0xff174fd4);
  static const Color purple = Color(0xff7657ff);
  static const Color cyan = Color(0xff30b8f2);
  static const Color canvas = Color(0xfff5f6fa);
  static const Color ink = Color(0xff171a23);
  static const Color muted = Color(0xff747986);
  static const Color track = Color(0xffe6e9f1);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xff286cf4), Color(0xff5a8bff)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData light() => _theme(Brightness.light);
  static ThemeData dark() => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: blue,
      brightness: brightness,
      primary: blue,
      secondary: purple,
      tertiary: cyan,
      surface: isDark ? const Color(0xff111318) : Colors.white,
      onSurface: isDark ? const Color(0xfff5f6fa) : ink,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? const Color(0xff111318) : canvas,
      fontFamily: 'SF Pro Display',
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: isDark ? const Color(0xff111318) : canvas,
        foregroundColor: scheme.onSurface,
        toolbarHeight: 68,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 25,
          height: 1.1,
          fontWeight: FontWeight.w800,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface, size: 24),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? const Color(0xff1b1e26) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xff1b1e26) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : const Color(0xffeceef4),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: const BorderSide(color: blue, width: 1.4),
        ),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 46),
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : const Color(0xffe4e7ef),
        ),
        backgroundColor:
            isDark ? const Color(0xff1b1e26) : const Color(0xfff8f9fc),
        selectedColor:
            isDark ? blue.withValues(alpha: 0.25) : const Color(0xffe8efff),
        labelStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        secondaryLabelStyle: const TextStyle(
          color: blue,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: blue,
        linearTrackColor: isDark ? const Color(0xff303542) : track,
        linearMinHeight: 5,
        circularTrackColor: isDark ? const Color(0xff303542) : track,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: blue,
        inactiveTrackColor: isDark ? const Color(0xff303542) : track,
        thumbColor: blue,
        overlayColor: blue.withValues(alpha: 0.14),
        trackHeight: 5,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor:
            isDark ? const Color(0xff151821) : Colors.white,
        indicatorColor:
            isDark ? blue.withValues(alpha: 0.2) : const Color(0xffe7eeff),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? blue
                : scheme.onSurfaceVariant,
            size: 24,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            color: states.contains(WidgetState.selected)
                ? blue
                : scheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
          );
        }),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? const Color(0xff171a22) : canvas,
        modalBackgroundColor: isDark ? const Color(0xff171a22) : canvas,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? const Color(0xff1b1e26) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      dividerColor:
          isDark ? Colors.white.withValues(alpha: 0.07) : const Color(0xffe9ebf2),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: blue,
        unselectedItemColor: scheme.onSurfaceVariant,
        backgroundColor: isDark ? const Color(0xff151821) : Colors.white,
        elevation: 0,
      ),
    );
  }
}
