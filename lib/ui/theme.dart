import 'package:flutter/material.dart';

/// Minimal black & white theme. Tag colours are the only colour in the app.
ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final bg = dark ? Colors.black : Colors.white;
  final fg = dark ? Colors.white : Colors.black;
  final line = dark ? const Color(0xFF2A2A2A) : const Color(0xFFE6E6E6);
  final muted = dark ? const Color(0xFF9E9E9E) : const Color(0xFF6B6B6B);
  final soft = dark ? const Color(0xFF141414) : const Color(0xFFF5F5F5);

  final scheme = ColorScheme.fromSeed(
    seedColor: Colors.black,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
  ).copyWith(
    primary: fg,
    onPrimary: bg,
    secondary: fg,
    onSecondary: bg,
    surface: bg,
    onSurface: fg,
    onSurfaceVariant: muted,
    surfaceContainerLowest: bg,
    surfaceContainerLow: soft,
    surfaceContainer: soft,
    surfaceContainerHigh: soft,
    surfaceContainerHighest: soft,
    secondaryContainer: dark ? const Color(0xFF262626) : const Color(0xFFEAEAEA),
    onSecondaryContainer: fg,
    outline: muted,
    outlineVariant: line,
    error: dark ? Colors.white : Colors.black,
  );

  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
    side: BorderSide(color: line),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: fg,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(color: fg, fontSize: 22, fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(elevation: 0, color: bg, shape: shape, margin: EdgeInsets.zero),
    dividerTheme: DividerThemeData(color: line, space: 1, thickness: 1),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: bg,
      indicatorColor: scheme.secondaryContainer,
      surfaceTintColor: Colors.transparent,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: bg,
      selectedColor: fg,
      secondarySelectedColor: fg,
      checkmarkColor: bg,
      side: BorderSide(color: line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      labelStyle: TextStyle(color: fg),
      secondaryLabelStyle: TextStyle(color: bg),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: fg,
      foregroundColor: bg,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: fg,
      contentTextStyle: TextStyle(color: bg),
      actionTextColor: bg,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: fg)),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: bg, surfaceTintColor: Colors.transparent, showDragHandle: true),
    dialogTheme: DialogThemeData(backgroundColor: bg, surfaceTintColor: Colors.transparent),
    listTileTheme: ListTileThemeData(iconColor: fg),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? bg : muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? fg : soft),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? fg : line),
    ),
  );
}
