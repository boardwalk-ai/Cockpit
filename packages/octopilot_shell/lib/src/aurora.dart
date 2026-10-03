import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'motion.dart';
import 'shell_theme.dart';

/// Slow glows drifting behind the shell's screens: the mode colours over the
/// background. [energy] (0–1) brightens and quickens them, e.g. while the
/// voice is speaking.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({
    super.key,
    required this.child,
    this.energy = 0,
    this.colors,
  });

  final Widget child;
  final double energy;

  /// Defaults to red, teal and violet.
  final List<Color>? colors;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 40),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final colors =
        widget.colors ??
        const [Color(0xFFFF343C), Color(0xFF2BB58C), Color(0xFF8B83F0)];
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: c.background),
        RepaintBoundary(
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: widget.energy),
            duration: const Duration(milliseconds: 600),
            builder: (context, energy, _) => CustomPaint(
              painter: _AuroraPainter(
                time: _c,
                colors: colors,
                energy: energy,
                strength: dark ? 0.22 : 0.16,
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({
    required this.time,
    required this.colors,
    required this.energy,
    required this.strength,
  }) : super(repaint: time);

  final Animation<double> time;
  final List<Color> colors;
  final double energy;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value * 2 * math.pi;
    final span = size.longestSide;
    for (var i = 0; i < colors.length; i++) {
      final phase = i * 2.1;
      // Each glow wanders on its own slow figure-of-eight.
      final center = Offset(
        size.width * (0.5 + 0.38 * math.sin(t * (1 + i * 0.3) + phase)),
        size.height * (0.35 + 0.3 * math.sin(t * (0.7 + i * 0.2) * 2 + phase)),
      );
      final radius =
          span * (0.42 + 0.08 * math.sin(t * 3 + phase)) * (1 + energy * 0.25);
      final alpha = (strength * (1 + energy * 1.4)).clamp(0.0, 0.6);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            colors[i].withValues(alpha: alpha),
            colors[i].withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) =>
      old.energy != energy || old.strength != strength || old.colors != colors;
}
