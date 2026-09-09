import 'package:flutter/material.dart';

import '../tokens/color_tokens.dart';
import '../tokens/spacing_tokens.dart';
import '../tokens/typography_tokens.dart';
import 'cockpit_theme.dart';

/// The **borderless / typography-first** design system (Swiss · GitBook): a
/// single Poppins font, a neutral `#222323` dark, and no card/divider outlines.
/// Shared so every app (OctoNotes, Study Studio, …) can adopt one look.
///
/// Grouping comes from whitespace, hierarchy and proximity — not boxes.
abstract final class BorderlessTheme {
  /// The single design-system font. Declared in `cockpit_ui`'s pubspec, so
  /// Flutter namespaces the family as `packages/cockpit_ui/PlusJakartaSans`.
  static const String font = 'packages/cockpit_ui/PlusJakartaSans';

  static const CockpitFonts _fonts = CockpitFonts(
    primary: font,
    secondary: font,
    tertiary: font,
  );

  static ThemeData build(Brightness brightness) {
    final base0 = CockpitTheme.build(
      colors: CockpitColors.brand,
      fonts: _fonts,
      brightness: brightness,
    );
    // Neutral charcoal dark (page = #222323); NOT pure black, NOT warm/brown.
    // Light stays the warm cream from CockpitTheme.
    final scheme = brightness == Brightness.dark
        ? base0.colorScheme.copyWith(
            surface: const Color(0xFF222323),
            onSurface: const Color(0xFFECEDED),
            onSurfaceVariant: const Color(0xFF9BA0A0),
            surfaceContainerLowest: const Color(0xFF1B1C1C),
            surfaceContainerLow: const Color(0xFF2A2B2B),
            surfaceContainer: const Color(0xFF2F3030),
            surfaceContainerHigh: const Color(0xFF353737),
            surfaceContainerHighest: const Color(0xFF3D3F3F),
            outline: const Color(0xFF4C4E4E),
            outlineVariant: const Color(0xFF383A3A),
          )
        : base0.colorScheme;
    final base = base0.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
    );

    final pill = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
    );

    return base.copyWith(
      textTheme: _typography(base.textTheme),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CockpitRadii.lg),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.35),
        thickness: 1,
        space: 1,
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CockpitRadii.pill),
        ),
        side: BorderSide.none,
        backgroundColor: scheme.surfaceContainerHighest,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CockpitRadii.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CockpitRadii.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CockpitRadii.md),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: CockpitSpacing.xl,
            vertical: CockpitSpacing.md,
          ),
          shape: pill,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: CockpitSpacing.xl,
            vertical: CockpitSpacing.md,
          ),
          side: BorderSide.none,
          backgroundColor: scheme.surfaceContainerHigh,
          foregroundColor: scheme.onSurface,
          shape: pill,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          shape: pill,
        ),
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: scheme.surface,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }

  static TextTheme _typography(TextTheme t) {
    return t.copyWith(
      displaySmall: t.displaySmall?.copyWith(
          fontWeight: FontWeight.w700, letterSpacing: -0.5, height: 1.1),
      headlineLarge: t.headlineLarge?.copyWith(
          fontWeight: FontWeight.w700, letterSpacing: -0.5, height: 1.15),
      headlineMedium: t.headlineMedium?.copyWith(
          fontWeight: FontWeight.w600, letterSpacing: -0.4, height: 1.2),
      headlineSmall: t.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600, letterSpacing: -0.3, height: 1.25),
      titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: t.bodyLarge?.copyWith(height: 1.55),
      bodyMedium: t.bodyMedium?.copyWith(height: 1.55),
      labelSmall: t.labelSmall?.copyWith(
          fontWeight: FontWeight.w600, letterSpacing: 0.6),
    );
  }

  /// Wraps [child] in the borderless theme, following the current brightness.
  static Widget wrap({required BuildContext context, required Widget child}) {
    return Theme(
      data: build(Theme.of(context).brightness),
      child: child,
    );
  }
}
