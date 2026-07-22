import 'package:flutter/material.dart';

/// Presentation-only accent + status swatches for Study Studio's newer screens
/// (Ask AI, Manage). These are decorative — *not* brand tokens — so they live
/// here instead of the theme's [ColorScheme]. Centralizing them keeps the same
/// swatch from being repeated inline across widgets; brand roles (primary,
/// surface, error, …) still come from `Theme.of(context).colorScheme`.
abstract final class StudyPalette {
  // Semantic / status.
  static const Color success = Color(0xFF10B981); // emerald
  static const Color warning = Color(0xFFF59E0B); // amber
  static const Color danger = Color(0xFFEF4444); // red
  static const Color info = Color(0xFF3B82F6); // blue

  // Accents.
  static const Color violet = Color(0xFF8B5CF6);
  static const Color violetDeep = Color(0xFF7C3AED);
  static const Color purple = Color(0xFF9333EA);
  static const Color pink = Color(0xFFEC4899);
  static const Color amberBright = Color(0xFFFBBF24);
}
