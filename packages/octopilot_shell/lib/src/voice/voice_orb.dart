import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../motion.dart';

/// What the voice is doing; the orb's colour and motion follow it.
enum VoicePhase {
  idle,
  connecting,
  listening,
  thinking,
  speaking;

  List<Color> get colors => switch (this) {
    idle || connecting => const [Color(0xFFFF343C), Color(0xFFFF8A5B)],
    listening => const [Color(0xFFFF343C), Color(0xFFFF6FA3)],
    thinking => const [Color(0xFF8B83F0), Color(0xFF5B8DEF)],
    speaking => const [Color(0xFF2BB58C), Color(0xFFFF5A4E)],
  };
}

/// A living blob: breathes when idle, swells with [level] (0–1, the voice's
/// loudness), swirls while thinking.
class VoiceOrb extends StatefulWidget {
  const VoiceOrb({
    super.key,
    required this.size,
    this.phase = VoicePhase.idle,
    this.level = 0,
  });

  final double size;
  final VoicePhase phase;
  final double level;

  @override
  State<VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<VoiceOrb>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _time = ValueNotifier<double>(0);
  var _level = 0.0;
  var _swirl = 0.0;
  late List<Color> _colors = widget.phase.colors;
  Duration _last = Duration.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _ticker.stop();
    } else if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    // Follow the level quickly up, slowly down, like a VU meter.
    final target = widget.level.clamp(0.0, 1.0);
    final rate = target > _level ? 14.0 : 4.0;
    _level += (target - _level) * (1 - math.exp(-rate * dt));
    final thinking = widget.phase == VoicePhase.thinking ? 1.0 : 0.0;
    _swirl += (thinking - _swirl) * (1 - math.exp(-3 * dt));
    // Ease towards this phase's colours.
    final want = widget.phase.colors;
    _colors = [
      for (var i = 0; i < want.length; i++)
        Color.lerp(_colors[i], want[i], 1 - math.exp(-5 * dt))!,
    ];
    _time.value = elapsed.inMicroseconds / 1e6;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          painter: _OrbPainter(
            time: _time,
            state: this,
            still: reduceMotion(context),
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({required this.time, required this.state, required this.still})
    : super(repaint: time);

  final ValueNotifier<double> time;
  final _VoiceOrbState state;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final level = still ? 0.0 : state._level;
    final swirl = state._swirl;
    final colors = still ? state.widget.phase.colors : state._colors;
    final center = size.center(Offset.zero);
    final base = size.shortestSide * 0.31;
    final breathe = 1 + 0.035 * math.sin(t * 1.6);
    final r = base * breathe * (1 + level * 0.28);

    // Ripples that leave the orb when it is loud.
    for (var i = 0; i < 3; i++) {
      final p = ((t * 0.55) + i / 3) % 1;
      final ring = r * (1.05 + p * 0.55);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = colors[0].withValues(alpha: (1 - p) * (0.12 + level * 0.45));
      canvas.drawCircle(center, ring, paint);
    }

    // The glow behind it.
    canvas.drawCircle(
      center,
      r * 1.7,
      Paint()
        ..shader = RadialGradient(
          colors: [
            colors[0].withValues(alpha: 0.35 + level * 0.3),
            colors[0].withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: r * 1.7)),
    );

    // The blob: a circle whose edge waves, more as it gets louder.
    final wobble = 0.045 + level * 0.16 + swirl * 0.05;
    final path = Path();
    const steps = 96;
    for (var i = 0; i <= steps; i++) {
      final a = i / steps * 2 * math.pi;
      final w =
          math.sin(a * 3 + t * 2.1) * 0.5 +
          math.sin(a * 5 - t * 2.9 + 1.3) * 0.3 +
          math.sin(a * 2 + t * 1.3 + swirl * t * 4) * 0.2;
      final d = r * (1 + wobble * w);
      final p = center + Offset(math.cos(a), math.sin(a)) * d;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    final spin = t * (0.6 + swirl * 2.4);
    canvas.drawPath(
      path,
      Paint()
        ..shader = SweepGradient(
          colors: [colors[0], colors[1], colors[0]],
          transform: GradientRotation(spin),
        ).createShader(Rect.fromCircle(center: center, radius: r * 1.2)),
    );

    // A soft core, so the sweep has no point in the middle.
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          radius: 0.75,
          colors: [
            Color.lerp(colors[0], colors[1], 0.5)!,
            Color.lerp(colors[0], colors[1], 0.5)!.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );

    // Light from the top left.
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.45, -0.55),
          radius: 0.9,
          colors: [
            Colors.white.withValues(alpha: 0.55),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );
  }

  @override
  bool shouldRepaint(_OrbPainter old) => still || old.still != still;
}
