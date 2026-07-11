import 'package:flutter/material.dart';

/// The three global **color controls** — primary, secondary, tertiary — plus a
/// small set of derived semantic colors.
///
/// This is the single source of truth for brand color. Change [brand] (or push
/// new values via the theme controller / backend RemoteConfig) to re-skin the
/// entire app. Widgets must read colors from the [ColorScheme] built off these
/// tokens, never hard-code a hex value.
@immutable
class CockpitColors {
  const CockpitColors({
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
  });

  final Color primary;
  final Color secondary;
  final Color tertiary;

  final Color success;
  final Color warning;
  final Color error;
  final Color info;

  /// Default Octopilot brand palette.
  static const CockpitColors brand = CockpitColors(
    primary: Color(0xFF4F46E5), // indigo 600
    secondary: Color(0xFF0EA5E9), // sky 500
    tertiary: Color(0xFFF59E0B), // amber 500
    success: Color(0xFF16A34A),
    warning: Color(0xFFF59E0B),
    error: Color(0xFFDC2626),
    info: Color(0xFF2563EB),
  );

  CockpitColors copyWith({
    Color? primary,
    Color? secondary,
    Color? tertiary,
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
  }) {
    return CockpitColors(
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      tertiary: tertiary ?? this.tertiary,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
    );
  }
}
