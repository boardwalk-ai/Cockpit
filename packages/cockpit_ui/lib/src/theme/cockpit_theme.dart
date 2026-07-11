import 'package:flutter/material.dart';

import '../tokens/color_tokens.dart';
import '../tokens/spacing_tokens.dart';
import '../tokens/typography_tokens.dart';

/// Builds [ThemeData] from the global control tokens ([CockpitColors] +
/// [CockpitFonts]). One function so light/dark stay consistent and rebrands
/// are a single edit.
abstract final class CockpitTheme {
  static ThemeData build({
    required CockpitColors colors,
    required CockpitFonts fonts,
    required Brightness brightness,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: colors.primary,
      brightness: brightness,
    ).copyWith(
      primary: colors.primary,
      secondary: colors.secondary,
      tertiary: colors.tertiary,
      error: colors.error,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fonts.secondary, // body default
    );

    // Map the three font roles onto the text theme.
    final textTheme = base.textTheme.copyWith(
      displayLarge: base.textTheme.displayLarge?.copyWith(fontFamily: fonts.primary),
      displayMedium: base.textTheme.displayMedium?.copyWith(fontFamily: fonts.primary),
      displaySmall: base.textTheme.displaySmall?.copyWith(fontFamily: fonts.primary),
      headlineLarge: base.textTheme.headlineLarge?.copyWith(fontFamily: fonts.primary),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(fontFamily: fonts.primary),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(fontFamily: fonts.primary),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontFamily: fonts.primary),
      labelLarge: base.textTheme.labelLarge?.copyWith(fontFamily: fonts.tertiary),
      labelMedium: base.textTheme.labelMedium?.copyWith(fontFamily: fonts.tertiary),
      labelSmall: base.textTheme.labelSmall?.copyWith(fontFamily: fonts.tertiary),
    );

    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CockpitRadii.lg),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: CockpitSpacing.xl,
            vertical: CockpitSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CockpitRadii.md),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CockpitRadii.pill),
        ),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CockpitRadii.md),
          borderSide: BorderSide.none,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
      ),
    );
  }
}
