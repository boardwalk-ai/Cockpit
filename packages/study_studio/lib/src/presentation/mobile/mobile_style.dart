import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Study Studio's phone look: the same faces, colours and touch as
/// GhostWriter and the Octopilot shell. Few cards: type, space and hairlines
/// carry the layout. Light or dark follows the app's theme.
abstract final class SmFonts {
  /// Headings and numbers.
  static const heading = 'packages/cockpit_ui/PlusJakartaSans';

  /// Body text.
  static const body = 'packages/cockpit_ui/Poppins';

  /// Long reading (a lesson's text): a serif made for screens.
  static const reading = 'packages/cockpit_ui/Literata';
}

class SmColors {
  const SmColors._({
    required this.background,
    required this.raised,
    required this.line,
    required this.text,
    required this.muted,
    required this.hint,
    required this.accent,
    required this.accentSoft,
    required this.gold,
  });

  final Color background;

  /// Pressed rows, tracks, the search field.
  final Color raised;

  /// Hairlines and ring tracks.
  final Color line;
  final Color text;
  final Color muted;
  final Color hint;
  final Color accent;

  /// Accent text on the background (a touch lighter in the dark).
  final Color accentSoft;
  final Color gold;

  static const dark = SmColors._(
    background: Color(0xFF222323),
    raised: Color(0xFF2A2B2B),
    line: Color(0xFF3A3C3C),
    text: Color(0xFFE6E6E8),
    muted: Color(0xFFA0A2A5),
    hint: Color(0xFF7C7E81),
    accent: Color(0xFFFF343C),
    accentSoft: Color(0xFFFF5258),
    gold: Color(0xFFFFC53D),
  );

  static const light = SmColors._(
    background: Color(0xFFF6F5F2),
    raised: Color(0xFFEDEBE6),
    line: Color(0xFFE0DDD6),
    text: Color(0xFF1B1C1C),
    muted: Color(0xFF5F5E5A),
    hint: Color(0xFF8A8984),
    accent: Color(0xFFE11D2E),
    accentSoft: Color(0xFFE11D2E),
    gold: Color(0xFFBA7517),
  );

  static SmColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// The text styles, coloured for the current theme.
class SmText {
  SmText.of(BuildContext context) : c = SmColors.of(context);

  final SmColors c;

  TextStyle get greeting => TextStyle(
    fontFamily: SmFonts.heading,
    fontSize: 24,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: c.text,
  );

  TextStyle get title => TextStyle(
    fontFamily: SmFonts.heading,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: c.text,
  );

  TextStyle get body => TextStyle(
    fontFamily: SmFonts.body,
    fontSize: 13,
    height: 1.35,
    color: c.text,
  );

  TextStyle get small => TextStyle(
    fontFamily: SmFonts.body,
    fontSize: 11,
    height: 1.35,
    color: c.muted,
  );

  /// CONTINUE, UP NEXT, YOUR STUDIOS.
  TextStyle get section => TextStyle(
    fontFamily: SmFonts.heading,
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.1,
    color: c.hint,
  );
}

/// Touch feedback, as GhostWriter gives it.
abstract final class SmHaptics {
  /// Opening something: a row, a studio.
  static void select() => HapticFeedback.selectionClick();

  /// A button.
  static void tap() => HapticFeedback.lightImpact();

  /// The main action (a new studio).
  static void thud() => HapticFeedback.mediumImpact();

  /// Something went wrong.
  static void error() => HapticFeedback.vibrate();

  /// A long wait is over: the studio is ready.
  static void done() => HapticFeedback.heavyImpact();
}

/// True when the user asked for less motion.
bool smReduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;
