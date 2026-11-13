import 'package:flutter/material.dart';

class ThemeController {
  // Global notifier for Dark vs Light mode (Default: dark mode)
  static final ValueNotifier<bool> isDarkMode = ValueNotifier<bool>(false);

  static void toggleTheme() {
    isDarkMode.value = !isDarkMode.value;
  }

  static void setDarkMode(bool value) {
    isDarkMode.value = value;
  }
}
