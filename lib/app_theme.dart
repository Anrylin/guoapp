import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class AppTheme {
  static const Color gold = Color(0xFFE8C87A);
  static const Color goldDeep = Color(0xFF8A6A1F);
  static const Color actionBlue = Color(0xFF7FB8FF);

  static final light = _theme(Brightness.light);
  static final dark = _theme(Brightness.dark);

  static ThemeMode mode(String preference) => switch (preference) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  static String label(String preference) => switch (preference) {
    'light' => '浅色',
    'dark' => '深色',
    _ => '跟随系统',
  };

  static SystemUiOverlayStyle systemBars(Brightness brightness) {
    final icons = brightness == Brightness.dark
        ? Brightness.light
        : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: icons,
      statusBarBrightness: brightness,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: icons,
      systemNavigationBarContrastEnforced: false,
    );
  }

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = dark ? const Color(0xFF0A0A0C) : const Color(0xFFFAF8F4);
    final scheme = ColorScheme.fromSeed(
      seedColor: gold,
      brightness: brightness,
      primary: dark ? gold : goldDeep,
      onPrimary: dark ? const Color(0xFF241A00) : Colors.white,
      primaryContainer: dark
          ? const Color(0xFF3A2E12)
          : const Color(0xFFF6E7C2),
      onPrimaryContainer: dark
          ? const Color(0xFFF6E7C2)
          : const Color(0xFF3A2E12),
      secondary: dark ? actionBlue : const Color(0xFF2F5C99),
      onSecondary: dark ? const Color(0xFF00121F) : Colors.white,
      tertiary: dark ? const Color(0xFFC9C6D2) : const Color(0xFF5A5560),
      surface: dark ? const Color(0xFF141417) : Colors.white,
      onSurface: dark ? const Color(0xFFEDEDF0) : const Color(0xFF1D1B16),
      onSurfaceVariant: dark
          ? const Color(0xFF8A8A93)
          : const Color(0xFF6B6660),
      outline: dark ? const Color(0xFF5C5C66) : const Color(0xFF8C867D),
      outlineVariant: dark ? const Color(0x1AFFFFFF) : const Color(0xFFE7E1D5),
      surfaceContainerLowest: dark
          ? const Color(0xFF070708)
          : const Color(0xFFFFFEFC),
      surfaceContainerLow: dark
          ? const Color(0xFF111114)
          : const Color(0xFFF6F3ED),
      surfaceContainer: dark
          ? const Color(0xFF141417)
          : const Color(0xFFF1EDE6),
      surfaceContainerHigh: dark
          ? const Color(0xFF1B1B20)
          : const Color(0xFFEBE6DE),
      surfaceContainerHighest: dark
          ? const Color(0xFF232329)
          : const Color(0xFFE4DED4),
      surfaceTint: Colors.transparent,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        scrolledUnderElevation: 3,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        systemOverlayStyle: systemBars(brightness),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? const Color(0xFF0D0D10) : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: dark
            ? const Color(0x1AE8C87A)
            : const Color(0x1A8A6A1F),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: background,
        useIndicator: false,
        selectedIconTheme: IconThemeData(color: scheme.primary),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF232329) : const Color(0xFF2B2A28),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
