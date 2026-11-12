import 'package:flutter/material.dart';

/// وضع المظهر المختار (يُحمَّل من حساب المستخدم)
final ValueNotifier<ThemeMode> themeModePref = ValueNotifier<ThemeMode>(ThemeMode.system);

ThemeMode themeModeFromString(String s) {
  switch (s) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

String themeModeToString(ThemeMode m) {
  switch (m) {
    case ThemeMode.light:
      return 'light';
    case ThemeMode.dark:
      return 'dark';
    default:
      return 'system';
  }
}
