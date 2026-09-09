import 'package:flutter/material.dart';

/// The five academic citation styles Doc Oct supports (mirrors the web
/// FORMAT_STYLES). Every document has one. In the borderless system the style
/// shows as a muted label + a small colored dot — never a boxed badge.
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

  /// One-letter mark for the style's dot (mirrors the web `abbr`).
  String get abbr => switch (this) {
        FormatStyle.mla => 'M',
        FormatStyle.apa => 'A',
        FormatStyle.chicago => 'C',
        FormatStyle.ieee => 'I',
        FormatStyle.harvard => 'H',
      };

  /// The functional accent for this style (matches the web FORMAT_STYLES).
  Color get color => switch (this) {
        FormatStyle.mla => const Color(0xFF7C3AED),
        FormatStyle.apa => const Color(0xFF2563EB),
        FormatStyle.chicago => const Color(0xFFEA580C),
        FormatStyle.ieee => const Color(0xFF16A34A),
        FormatStyle.harvard => const Color(0xFF0369A1),
      };
}
