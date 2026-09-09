import 'package:flutter/material.dart';

/// Spacing scale for Doc Oct (logical px).
abstract final class DocSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

/// Corner radii — intentionally large and soft. In the borderless system,
/// rounded, floating surfaces (not outlines) do the visual separation.
abstract final class DocRadii {
  static const double sm = 10;
  static const double md = 16;
  static const double lg = 22;
  static const double xl = 28;
  static const double pill = 999;
}

/// The five academic citation styles Doc Oct supports (mirrors the web
/// FORMAT_STYLES). Kept as a first-class domain type — every project has one.
enum FormatStyle { mla, apa, chicago, ieee, harvard }

extension FormatStyleX on FormatStyle {
  /// Full label, e.g. "MLA (8th Edition)".
  String get label => switch (this) {
        FormatStyle.mla => 'MLA (8th Edition)',
        FormatStyle.apa => 'APA (7th Edition)',
        FormatStyle.chicago => 'Chicago (17th Edition)',
        FormatStyle.ieee => 'IEEE',
        FormatStyle.harvard => 'Harvard',
      };

  /// Short name for chips, e.g. "MLA".
  String get short => switch (this) {
        FormatStyle.mla => 'MLA',
        FormatStyle.apa => 'APA',
        FormatStyle.chicago => 'Chicago',
        FormatStyle.ieee => 'IEEE',
        FormatStyle.harvard => 'Harvard',
      };

  /// Single-letter badge.
  String get abbr => switch (this) {
        FormatStyle.mla => 'M',
        FormatStyle.apa => 'A',
        FormatStyle.chicago => 'C',
        FormatStyle.ieee => 'I',
        FormatStyle.harvard => 'H',
      };

  /// Accent colour used for the style's badge/dot (from the web palette).
  Color get color => switch (this) {
        FormatStyle.mla => const Color(0xFF8B5CF6), // violet
        FormatStyle.apa => const Color(0xFF3B82F6), // blue
        FormatStyle.chicago => const Color(0xFFEA580C), // orange
        FormatStyle.ieee => const Color(0xFF16A34A), // green
        FormatStyle.harvard => const Color(0xFF0EA5A6), // teal
      };
}
