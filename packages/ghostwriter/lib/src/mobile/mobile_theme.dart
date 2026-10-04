import 'package:flutter/material.dart';

/// Colours shared by the GhostWriter phone UI.
abstract final class GwColors {
  static const background = Color(0xFF222323);
  static const bar = Color(0xFF1B1C1C);
  static const panel = Color(0xFF181919);
  static const chip = Color(0xFF2A2B2B);
  static const border = Color(0xFF3A3C3C);
  static const muted = Color(0xFFA0A2A5);
  static const hint = Color(0xFF7C7E81);
  static const accent = Color(0xFFFF343C);
  static const accentSoft = Color(0xFFFF5258);
  static const gold = Color(0xFFFFC53D);
}

/// Typefaces. Primary is used for headings, buttons and labels; secondary
/// for body copy, hints and anything the user reads at length.
abstract final class GwFonts {
  // Package fonts are namespaced by Flutter as `packages/<package>/<family>`.
  static const primary = 'packages/cockpit_ui/PlusJakartaSans';
  static const secondary = 'packages/ghostwriter/Poppins';

  /// Secondary text falls back to the primary face if Poppins is missing.
  static const secondaryFallback = [primary];
}

/// Bundled images.
abstract final class GwAssets {
  static const ghost = 'packages/ghostwriter/assets/images/ghost.png';
  static const octo = 'packages/ghostwriter/assets/images/octo.png';
}

/// Composer and top-bar button size.
const double kGwButton = 44;

/// Body copy: chat bubbles, cards, anything read at length.
const TextStyle kGwBody = TextStyle(
  color: Color(0xFFE6E6E8),
  fontFamily: GwFonts.secondary,
  fontFamilyFallback: GwFonts.secondaryFallback,
  fontSize: 13,
  height: 1.55,
);

/// Small uppercase label above a section.
const TextStyle kGwLabel = TextStyle(
  color: GwColors.hint,
  fontSize: 10,
  letterSpacing: 1.6,
  fontWeight: FontWeight.w700,
);
