import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'mobile_style.dart';

/// Study-minded greetings: a few for any time and a few for the time of
/// day. `{name}` is the user's first name; lines with it are skipped when
/// the name is not known.
abstract final class StudyGreetings {
  static const anytime = [
    'Welcome back, {name}',
    'Hey {name}, ready to learn?',
    'Let’s make it stick',
  ];

  static const morning = [
    'Good morning, {name}',
    'Morning, {name}. Fresh mind, fresh notes',
    'One topic before coffee?',
  ];

  static const afternoon = [
    'Good afternoon, {name}',
    'Hey {name}, time for a quick review?',
    'A little practice goes a long way',
  ];

  static const evening = [
    'Good evening, {name}',
    'Evening, {name}. Wind down with a review?',
  ];

  static const lateNight = [
    'Hey night owl',
    'Still up, {name}? Short sessions stick best',
    'Burning the midnight oil, {name}?',
  ];

  static List<String> forTime(DateTime time) => switch (time.hour) {
    >= 5 && < 12 => morning,
    >= 12 && < 17 => afternoon,
    >= 17 && < 22 => evening,
    _ => lateNight,
  };

  /// The lines that fit [time] and [name].
  static List<String> choices(DateTime time, String? name) {
    final first = name?.trim().split(RegExp(r'\s+')).first ?? '';
    final known = first.isNotEmpty && first != 'Guest';
    return [
      for (final line in [...forTime(time), ...anytime])
        if (known)
          line.replaceAll('{name}', first)
        else if (!line.contains('{name}'))
          line,
    ];
  }

  /// One line, picked by [seed] (the same all session, so the greeting
  /// does not change under the user on every rebuild).
  static String pick(DateTime time, String? name, {int seed = 0}) {
    final lines = choices(time, name);
    return lines[math.Random(seed).nextInt(lines.length)];
  }

  /// Fixed for the life of the app.
  static final sessionSeed = DateTime.now().millisecondsSinceEpoch;
}

/// The greeting, in the accent, with a highlight sweeping across it now and
/// then (as on GhostWriter's landing).
class SmGreeting extends StatefulWidget {
  const SmGreeting({super.key, required this.text});

  final String text;

  @override
  State<SmGreeting> createState() => _SmGreetingState();
}

class _SmGreetingState extends State<SmGreeting>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (smReduceMotion(context)) {
      _shine.stop();
    } else if (!_shine.isAnimating) {
      _shine.repeat();
    }
  }

  @override
  void dispose() {
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = Text(
      widget.text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: SmFonts.heading,
        fontSize: 17,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: c.accentSoft,
      ),
    );
    return AnimatedBuilder(
      animation: _shine,
      child: text,
      builder: (context, child) {
        final t = (_shine.value * 4).clamp(0.0, 1.0);
        final x = -2.5 + 5 * t;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(x - 0.7, 0),
            end: Alignment(x + 0.7, 0),
            colors: [
              c.accentSoft,
              dark ? const Color(0xFFFFD9DA) : const Color(0xFFFF8A8F),
              c.accentSoft,
            ],
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}
