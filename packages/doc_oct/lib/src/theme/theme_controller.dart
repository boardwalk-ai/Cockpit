import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Current Doc Oct theme mode. Dark is the default; the floating theme switcher
/// (bottom-right) flips it. Kept module-local so Doc Oct owns its own look.
class DocThemeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.dark;

  void toggle() =>
      state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;

  void set(ThemeMode mode) => state = mode;

  bool get isDark => state == ThemeMode.dark;
}

final docThemeControllerProvider =
    NotifierProvider<DocThemeController, ThemeMode>(DocThemeController.new);
