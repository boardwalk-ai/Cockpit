import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tokens/color_tokens.dart';
import '../tokens/typography_tokens.dart';
import 'cockpit_theme.dart';

/// Current state of the global controls.
@immutable
class ThemeState {
  const ThemeState({
    required this.colors,
    required this.fonts,
    required this.mode,
  });

  final CockpitColors colors;
  final CockpitFonts fonts;
  final ThemeMode mode;

  ThemeData get light =>
      CockpitTheme.build(colors: colors, fonts: fonts, brightness: Brightness.light);

  ThemeData get dark =>
      CockpitTheme.build(colors: colors, fonts: fonts, brightness: Brightness.dark);

  ThemeState copyWith({
    CockpitColors? colors,
    CockpitFonts? fonts,
    ThemeMode? mode,
  }) {
    return ThemeState(
      colors: colors ?? this.colors,
      fonts: fonts ?? this.fonts,
      mode: mode ?? this.mode,
    );
  }
}

/// Holds and mutates the global controls at runtime. Can later be seeded from
/// backend RemoteConfig (`GET /config`).
class ThemeController extends Notifier<ThemeState> {
  @override
  ThemeState build() => const ThemeState(
        colors: CockpitColors.brand,
        fonts: CockpitFonts.brand,
        mode: ThemeMode.system,
      );

  void setColors(CockpitColors colors) => state = state.copyWith(colors: colors);
  void setFonts(CockpitFonts fonts) => state = state.copyWith(fonts: fonts);
  void setMode(ThemeMode mode) => state = state.copyWith(mode: mode);

  void setPrimary(Color color) =>
      state = state.copyWith(colors: state.colors.copyWith(primary: color));
}

final themeControllerProvider =
    NotifierProvider<ThemeController, ThemeState>(ThemeController.new);
