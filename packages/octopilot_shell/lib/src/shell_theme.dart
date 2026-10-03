import 'package:flutter/material.dart';

/// The shell's colours, for dark and light. Widgets read them with
/// `ShellColors.of(context)`.
@immutable
class ShellColors extends ThemeExtension<ShellColors> {
  const ShellColors({
    required this.background,
    required this.surface,
    required this.raised,
    required this.border,
    required this.text,
    required this.muted,
    required this.hint,
    required this.accent,
    required this.onAccent,
  });

  /// GhostWriter's palette: near-black, red accent.
  static const dark = ShellColors(
    background: Color(0xFF222323),
    surface: Color(0xFF1B1C1C),
    raised: Color(0xFF2A2B2B),
    border: Color(0xFF3A3C3C),
    text: Color(0xFFE6E6E8),
    muted: Color(0xFFA0A2A5),
    hint: Color(0xFF7C7E81),
    accent: Color(0xFFFF343C),
    onAccent: Colors.white,
  );

  /// Warm off-white, same red.
  static const light = ShellColors(
    background: Color(0xFFF6F5F2),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFEDEBE6),
    border: Color(0xFFE0DDD6),
    text: Color(0xFF1B1C1C),
    muted: Color(0xFF5F5E5A),
    hint: Color(0xFF8A8984),
    accent: Color(0xFFE11D2E),
    onAccent: Colors.white,
  );

  final Color background;

  /// Cards and sheets.
  final Color surface;

  /// The user's bubbles, pressed rows, chips.
  final Color raised;
  final Color border;
  final Color text;
  final Color muted;
  final Color hint;
  final Color accent;
  final Color onAccent;

  static ShellColors of(BuildContext context) =>
      Theme.of(context).extension<ShellColors>() ?? dark;

  @override
  ShellColors copyWith({
    Color? background,
    Color? surface,
    Color? raised,
    Color? border,
    Color? text,
    Color? muted,
    Color? hint,
    Color? accent,
    Color? onAccent,
  }) => ShellColors(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    raised: raised ?? this.raised,
    border: border ?? this.border,
    text: text ?? this.text,
    muted: muted ?? this.muted,
    hint: hint ?? this.hint,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
  );

  @override
  ShellColors lerp(ShellColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return ShellColors(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      raised: mix(raised, other.raised),
      border: mix(border, other.border),
      text: mix(text, other.text),
      muted: mix(muted, other.muted),
      hint: mix(hint, other.hint),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
    );
  }
}

/// The shared face, bundled by cockpit_ui.
const String kShellFont = 'packages/cockpit_ui/PlusJakartaSans';

ThemeData buildShellTheme(Brightness brightness) {
  final c = brightness == Brightness.dark
      ? ShellColors.dark
      : ShellColors.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: c.accent,
        brightness: brightness,
      ).copyWith(
        primary: c.accent,
        onPrimary: c.onAccent,
        surface: c.background,
        onSurface: c.text,
        outline: c.border,
      );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.background,
    fontFamily: kShellFont,
    dividerColor: c.border,
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.raised,
      contentTextStyle: TextStyle(color: c.text, fontFamily: kShellFont),
    ),
    extensions: [c],
  );
}
