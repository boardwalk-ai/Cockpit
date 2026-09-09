import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';

/// OctoNotes design system — layered on the shared [CockpitTheme].
///
/// Direction (see `../../MEMORY.md`):
/// * **Single font: Poppins** for everything (display → labels).
/// * **Borderless / typography-first** (Swiss / GitBook aesthetic): no card
///   borders, no heavy dividers, no card-on-card, minimal shadow. Grouping comes
///   from **whitespace, type hierarchy, alignment and proximity** — not boxes.
/// * Restrained color: red is a functional accent only.
abstract final class OctoNotesTheme {
  // The single design-system font, shared from cockpit_ui (Plus Jakarta Sans,
  // namespaced `packages/cockpit_ui/PlusJakartaSans`).
  static const String _font = BorderlessTheme.font;
  static const CockpitFonts _fonts = CockpitFonts(
    primary: _font,
    secondary: _font,
    tertiary: _font,
  );

  static ThemeData build(Brightness brightness) {
    final base0 = CockpitTheme.build(
      colors: CockpitColors.brand,
      fonts: _fonts,
      brightness: brightness,
    );
    // OctoNotes dark is a neutral charcoal (page = #222323) — NOT pure black and
    // NOT warm/brown. Text + muted greys are neutral too. Light stays cream.
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

    // A pill button with NO ring/border — a solid shape reads clean on the
    // borderless surface.
    final pill = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
    );

    return base.copyWith(
      // Type-first: strong, tight headings; comfortable body.
      textTheme: _typography(base.textTheme, scheme),

      // Borderless cards — a card is just a padded surface, no outline.
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CockpitRadii.lg),
        ),
        margin: EdgeInsets.zero,
      ),

      // Faint, mostly-invisible dividers (use spacing instead of rules).
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.35),
        thickness: 1,
        space: 1,
      ),

      // Chips: subtle fill, no border.
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CockpitRadii.pill),
        ),
        side: BorderSide.none,
        backgroundColor: scheme.surfaceContainerHighest,
      ),

      // Inputs: borderless, subtle fill — no outline rectangles.
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

      // Buttons: solid pill (primary), no ring; text/tonal for the rest.
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
          side: BorderSide.none, // borderless: no outline
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

      // No app-bar hairline.
      appBarTheme: base.appBarTheme.copyWith(
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }

  /// Editorial type scale — larger, tighter headings carry the hierarchy.
  static TextTheme _typography(TextTheme t, ColorScheme scheme) {
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
      // Section labels: small, uppercase-friendly, muted — the docs-style eyebrow.
      labelSmall: t.labelSmall?.copyWith(
          fontWeight: FontWeight.w600, letterSpacing: 0.6),
    );
  }

  /// Wraps [child] in the OctoNotes theme, following the current brightness so
  /// it tracks the app-wide dark/light setting.
  static Widget wrap({required BuildContext context, required Widget child}) {
    return Theme(
      data: build(Theme.of(context).brightness),
      child: child,
    );
  }
}
