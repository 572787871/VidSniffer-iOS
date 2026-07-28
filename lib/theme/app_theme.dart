import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// A single source of truth for the app's Apple-platform visual language.
///
/// The values mirror iOS semantic colors instead of baking page-specific
/// decoration into individual screens. This keeps every menu, sheet, dialog,
/// field and progress surface consistent in light and dark appearances.
abstract final class AppTheme {
  static const Color blue = Color(0xff007aff);
  static const Color deepBlue = Color(0xff0057d9);
  static const Color purple = Color(0xffaf52de);
  static const Color cyan = Color(0xff32ade6);
  static const Color green = Color(0xff34c759);
  static const Color orange = Color(0xffff9500);
  static const Color red = Color(0xffff3b30);
  static const Color canvas = Color(0xfff7f6fb);
  static const Color ink = Color(0xff1c1c1e);
  static const Color muted = Color(0xff8e8e93);
  static const Color track = Color(0xffd1d1d6);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [blue, Color(0xff3b8cff)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData light() => _theme(Brightness.light);
  static ThemeData dark() => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background =
        dark ? const Color(0xff000000) : const Color(0xfff7f6fb);
    final surface = dark ? const Color(0xff1c1c1e) : Colors.white;
    final secondarySurface =
        dark ? const Color(0xff2c2c2e) : const Color(0xffebeaf0);
    final label = dark ? const Color(0xffffffff) : ink;
    final secondaryLabel =
        dark ? const Color(0xff98989d) : const Color(0xff6c6c70);
    final separator =
        dark ? const Color(0xff38383a) : const Color(0xffc6c6c8);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: blue,
      onPrimary: Colors.white,
      primaryContainer:
          dark ? const Color(0xff0a3a68) : const Color(0xffe5f1ff),
      onPrimaryContainer: dark ? Colors.white : const Color(0xff003c75),
      secondary: purple,
      onSecondary: Colors.white,
      secondaryContainer:
          dark ? const Color(0xff442354) : const Color(0xfff7e8ff),
      onSecondaryContainer: dark ? Colors.white : const Color(0xff4d1265),
      tertiary: cyan,
      onTertiary: Colors.white,
      tertiaryContainer:
          dark ? const Color(0xff154151) : const Color(0xffe1f5ff),
      onTertiaryContainer: dark ? Colors.white : const Color(0xff003f54),
      error: red,
      onError: Colors.white,
      errorContainer:
          dark ? const Color(0xff54201d) : const Color(0xffffe9e7),
      onErrorContainer: dark ? Colors.white : const Color(0xff7a1712),
      surface: surface,
      onSurface: label,
      onSurfaceVariant: secondaryLabel,
      outline: secondaryLabel,
      outlineVariant: separator.withValues(alpha: dark ? 0.75 : 0.55),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: dark ? Colors.white : const Color(0xff2c2c2e),
      onInverseSurface: dark ? Colors.black : Colors.white,
      inversePrimary: const Color(0xff64a8ff),
      surfaceTint: Colors.transparent,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: blue.withValues(alpha: 0.12),
      fontFamilyFallback: const [
        '.SF Pro Text',
        '.SF UI Text',
        'SF Pro Text',
        'PingFang SC',
        'Helvetica Neue',
      ],
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        },
      ),
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: blue,
        scaffoldBackgroundColor: background,
        barBackgroundColor: surface.withValues(alpha: 0.88),
        textTheme: CupertinoTextThemeData(
          primaryColor: blue,
          textStyle: TextStyle(
            color: label,
            fontSize: 17,
            letterSpacing: -0.2,
          ),
          navTitleTextStyle: TextStyle(
            color: label,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
          navLargeTitleTextStyle: TextStyle(
            color: label,
            fontSize: 34,
            height: 1.06,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
          ),
        ),
      ),
    );

    final textTheme = base.textTheme.copyWith(
      displaySmall: TextStyle(
        color: label,
        fontSize: 34,
        height: 1.08,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      headlineSmall: TextStyle(
        color: label,
        fontSize: 28,
        height: 1.12,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      titleLarge: TextStyle(
        color: label,
        fontSize: 22,
        height: 1.18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.35,
      ),
      titleMedium: TextStyle(
        color: label,
        fontSize: 17,
        height: 1.24,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      bodyLarge: TextStyle(
        color: label,
        fontSize: 17,
        height: 1.35,
        letterSpacing: -0.2,
      ),
      bodyMedium: TextStyle(
        color: label,
        fontSize: 15,
        height: 1.35,
        letterSpacing: -0.1,
      ),
      bodySmall: TextStyle(
        color: secondaryLabel,
        fontSize: 13,
        height: 1.35,
        letterSpacing: 0,
      ),
      labelLarge: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      labelMedium: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: background.withValues(alpha: 0.94),
        surfaceTintColor: Colors.transparent,
        foregroundColor: label,
        toolbarHeight: 58,
        titleSpacing: 18,
        titleTextStyle: textTheme.titleMedium,
        iconTheme: IconThemeData(color: label, size: 23),
        actionsIconTheme: IconThemeData(color: label, size: 23),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: secondarySurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        prefixIconColor: secondaryLabel,
        suffixIconColor: secondaryLabel,
        hintStyle: TextStyle(color: secondaryLabel),
        labelStyle: TextStyle(color: secondaryLabel),
        floatingLabelStyle: const TextStyle(color: blue),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: const BorderSide(color: blue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: const BorderSide(color: red),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(44, 50)),
          elevation: const WidgetStatePropertyAll(0),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
          overlayColor: WidgetStatePropertyAll(
            Colors.white.withValues(alpha: 0.14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(44, 48)),
          foregroundColor: const WidgetStatePropertyAll(blue),
          side: WidgetStatePropertyAll(
            BorderSide(color: blue.withValues(alpha: 0.4)),
          ),
          elevation: const WidgetStatePropertyAll(0),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
          foregroundColor: const WidgetStatePropertyAll(blue),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
          iconSize: const WidgetStatePropertyAll(22),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          ),
          overlayColor: WidgetStatePropertyAll(
            secondaryLabel.withValues(alpha: 0.12),
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        minTileHeight: 50,
        iconColor: blue,
        textColor: label,
        subtitleTextStyle: textTheme.bodySmall,
        titleTextStyle: textTheme.bodyLarge,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide.none,
        backgroundColor: secondarySurface,
        selectedColor:
            dark ? const Color(0xff0a3a68) : const Color(0xffe5f1ff),
        disabledColor: secondarySurface.withValues(alpha: 0.45),
        labelStyle: TextStyle(
          color: secondaryLabel,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: const TextStyle(
          color: blue,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        dividerHeight: 0,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: secondarySurface,
          borderRadius: BorderRadius.circular(22),
        ),
        labelColor: label,
        unselectedLabelColor: secondaryLabel,
        labelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: blue,
        linearTrackColor: dark ? const Color(0xff3a3a3c) : track,
        linearMinHeight: 4,
        circularTrackColor: dark ? const Color(0xff3a3a3c) : track,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: blue,
        inactiveTrackColor: dark ? const Color(0xff3a3a3c) : track,
        thumbColor: Colors.white,
        overlayColor: blue.withValues(alpha: 0.14),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 70,
        elevation: 0,
        backgroundColor: surface.withValues(alpha: 0.94),
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? blue
                : secondaryLabel,
            size: 24,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? blue
                : secondaryLabel,
            fontSize: 11,
            height: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 0,
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: Colors.black.withValues(alpha: 0.36),
        showDragHandle: true,
        dragHandleColor: secondaryLabel.withValues(alpha: 0.55),
        dragHandleSize: const Size(36, 5),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 24,
        backgroundColor: surface.withValues(alpha: 0.98),
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(32),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        elevation: 16,
        color: surface.withValues(alpha: 0.98),
        surfaceTintColor: Colors.transparent,
        textStyle: textTheme.bodyLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : const Color(0xfff4f4f4),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? green
              : (dark ? const Color(0xff39393d) : const Color(0xffe9e9ea)),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? blue : Colors.transparent,
        ),
        side: BorderSide(color: secondaryLabel, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? blue : secondaryLabel,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: separator.withValues(alpha: dark ? 0.8 : 0.48),
        thickness: 0.5,
        space: 0.5,
        indent: 16,
      ),
      dividerColor: separator.withValues(alpha: dark ? 0.8 : 0.48),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 12,
        backgroundColor:
            dark ? const Color(0xff2c2c2e) : const Color(0xff2c2c2e),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        elevation: 6,
        highlightElevation: 2,
        backgroundColor: blue,
        foregroundColor: Colors.white,
        shape: CircleBorder(),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? const Color(0xff3a3a3c) : const Color(0xee2c2c2e),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: blue,
        unselectedItemColor: secondaryLabel,
        backgroundColor: surface.withValues(alpha: 0.94),
        selectedLabelStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        elevation: 0,
      ),
    );
  }
}
