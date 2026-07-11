import 'package:flutter/material.dart';

/// The three global **font controls** — primary, secondary, tertiary.
///
/// - [primary]  : display & headings
/// - [secondary]: body / default text
/// - [tertiary] : labels, buttons, accents
///
/// A `null` family means "use the platform default". When you bundle custom
/// fonts (see `apps/cockpit/assets/fonts` + pubspec `fonts:`), set the family
/// names here and the whole app picks them up — no widget changes needed.
@immutable
class CockpitFonts {
  const CockpitFonts({
    this.primary,
    this.secondary,
    this.tertiary,
  });

  final String? primary;
  final String? secondary;
  final String? tertiary;

  /// Brand default. `Outfit` is bundled in `apps/cockpit/assets/fonts` and
  /// declared in that app's pubspec, which makes the family available app-wide.
  static const CockpitFonts brand = CockpitFonts(
    primary: 'Outfit',
    secondary: 'Outfit',
    tertiary: 'Outfit',
  );

  CockpitFonts copyWith({
    String? primary,
    String? secondary,
    String? tertiary,
  }) {
    return CockpitFonts(
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      tertiary: tertiary ?? this.tertiary,
    );
  }
}
