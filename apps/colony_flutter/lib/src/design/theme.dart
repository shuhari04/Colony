import 'package:flutter/material.dart';

import 'tokens.dart';

class ColonyTheme {
  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    final colorScheme = const ColorScheme.dark(
      primary: ColonyColors.accentCyan,
      secondary: ColonyColors.info,
      surface: ColonyColors.surface0,
      error: ColonyColors.danger,
      onPrimary: Colors.black,
      onSecondary: ColonyColors.text0,
      onSurface: ColonyColors.text0,
      onError: Colors.black,
    );

    final textTheme = base.textTheme.copyWith(
      titleMedium: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      titleSmall: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      bodyMedium: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
      bodySmall: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
    );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: ColonyColors.bg0,
      textTheme: textTheme.apply(bodyColor: ColonyColors.text0, displayColor: ColonyColors.text0),
      dividerColor: ColonyColors.border0,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ColonyColors.surface0,
        hintStyle: const TextStyle(color: ColonyColors.text1),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ColonyRadii.r2),
          borderSide: const BorderSide(color: ColonyColors.border0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ColonyRadii.r2),
          borderSide: const BorderSide(color: ColonyColors.border0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ColonyRadii.r2),
          borderSide: const BorderSide(color: ColonyColors.accentCyan, width: 2),
        ),
      ),
    );
  }
}
