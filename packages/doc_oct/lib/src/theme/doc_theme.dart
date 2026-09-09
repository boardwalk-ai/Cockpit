import 'package:flutter/material.dart';

import 'doc_tokens.dart';

/// The heart of the **borderless** design system.
///
/// In Doc Oct nothing is separated by a 1px outline. Instead, every surface is
/// a rounded, floating panel distinguished by a *layered background* and a
/// *soft shadow*. This extension carries those layered surfaces + shadows so
/// widgets never hard-code them and light/dark stay consistent.
@immutable
class DocSurfaces extends ThemeExtension<DocSurfaces> {
  const DocSurfaces({
    required this.canvas,
    required this.surface,
    required this.surfaceHigh,
    required this.surfaceMuted,
    required this.glass,
    required this.hairline,
    required this.shadowSoft,
    required this.shadowLift,
  });

  /// The page background behind all cards.
  final Color canvas;

  /// A resting card / panel.
  final Color surface;

  /// A raised / hovered / focused surface.
  final Color surfaceHigh;

  /// A recessed fill (inputs, wells) — reads as slightly *into* the canvas.
  final Color surfaceMuted;

  /// Translucent base for glass panels (compose over a blur).
  final Color glass;

  /// The faintest possible separator, for the rare case a line is unavoidable
  /// (e.g. a table row rule). Almost invisible — borderless by default.
  final Color hairline;

  /// Resting elevation.
  final List<BoxShadow> shadowSoft;

  /// Raised / hovered elevation.
  final List<BoxShadow> shadowLift;

  @override
  DocSurfaces copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceHigh,
    Color? surfaceMuted,
    Color? glass,
    Color? hairline,
    List<BoxShadow>? shadowSoft,
    List<BoxShadow>? shadowLift,
  }) {
    return DocSurfaces(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      glass: glass ?? this.glass,
      hairline: hairline ?? this.hairline,
      shadowSoft: shadowSoft ?? this.shadowSoft,
      shadowLift: shadowLift ?? this.shadowLift,
    );
  }

  @override
  DocSurfaces lerp(covariant DocSurfaces? other, double t) {
    if (other == null) return this;
    return DocSurfaces(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      glass: Color.lerp(glass, other.glass, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      shadowSoft: BoxShadow.lerpList(shadowSoft, other.shadowSoft, t)!,
      shadowLift: BoxShadow.lerpList(shadowLift, other.shadowLift, t)!,
    );
  }
}

/// Builds the Doc Oct [ThemeData] for a brightness. Cockpit-native palette
/// (red accent, Outfit type) rendered in the borderless system.
abstract final class DocTheme {
  static const Color _red = Color(0xFFE5142A); // brand red
  static const Color _redSoft = Color(0xFFFF4D5E);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static DocSurfaces surfacesOf(BuildContext context) =>
      Theme.of(context).extension<DocSurfaces>()!;

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme.fromSeed(
      seedColor: _red,
      brightness: brightness,
    ).copyWith(
      primary: _red,
      onPrimary: Colors.white,
      secondary: _redSoft,
      // Surfaces: warm, layered, borderless.
      surface: isDark ? const Color(0xFF0C0C0E) : const Color(0xFFF4F1EC),
      onSurface: isDark ? const Color(0xFFF3EFE7) : const Color(0xFF1A1815),
      onSurfaceVariant:
          isDark ? const Color(0xFF9C968B) : const Color(0xFF6B6560),
      // Keep outlines essentially invisible — the system is borderless.
      outline: isDark ? const Color(0x14FFFFFF) : const Color(0x14000000),
      outlineVariant: isDark ? const Color(0x0DFFFFFF) : const Color(0x0D000000),
    );

    final surfaces = isDark
        ? const DocSurfaces(
            canvas: Color(0xFF0C0C0E),
            surface: Color(0xFF171719),
            surfaceHigh: Color(0xFF1F1F22),
            surfaceMuted: Color(0xFF121214),
            glass: Color(0x14FFFFFF),
            hairline: Color(0x12FFFFFF),
            shadowSoft: [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 28,
                offset: Offset(0, 12),
              ),
            ],
            shadowLift: [
              BoxShadow(
                color: Color(0x80000000),
                blurRadius: 40,
                offset: Offset(0, 20),
              ),
            ],
          )
        : const DocSurfaces(
            canvas: Color(0xFFF4F1EC),
            surface: Color(0xFFFFFFFF),
            surfaceHigh: Color(0xFFFFFFFF),
            surfaceMuted: Color(0xFFECE8E1),
            glass: Color(0x0A000000),
            hairline: Color(0x14000000),
            shadowSoft: [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
            shadowLift: [
              BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 34,
                offset: Offset(0, 18),
              ),
            ],
          );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Outfit',
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      extensions: [surfaces],
      // Borderless cards: filled surface + soft shadow via widgets, no side.
      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaces.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DocRadii.lg),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: DocSpacing.xl,
            vertical: DocSpacing.md + 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DocRadii.pill),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      // Borderless inputs: filled recessed well, no visible border.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaces.surfaceMuted,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DocSpacing.lg,
          vertical: DocSpacing.md + 2,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DocRadii.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DocRadii.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DocRadii.md),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      dividerTheme: DividerThemeData(color: surfaces.hairline, thickness: 1),
    );
  }
}
