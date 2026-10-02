import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'mobile_theme.dart';

/// Screen background for the phone UI: charcoal base, slow red fades and a
/// halftone dot field whose dots swell in drifting waves and under the
/// user's finger.
class GwBackground extends StatefulWidget {
  const GwBackground({super.key, required this.child});

  final Widget child;

  @override
  State<GwBackground> createState() => _GwBackgroundState();
}

class _GwBackgroundState extends State<GwBackground>
    with TickerProviderStateMixin {
  /// Loops forever and drives the waves and the fades.
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );

  /// 1 while a finger is down, easing back to 0 after it lifts.
  late final AnimationController _touch = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    reverseDuration: const Duration(milliseconds: 1100),
  );

  final ValueNotifier<Offset> _touchPoint = ValueNotifier(Offset.zero);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    _touch.dispose();
    _touchPoint.dispose();
    super.dispose();
  }

  void _onPointer(PointerEvent event) {
    _touchPoint.value = event.localPosition;
    if (_touch.status != AnimationStatus.forward &&
        _touch.status != AnimationStatus.completed) {
      _touch.forward();
    }
  }

  void _onPointerEnd(PointerEvent event) => _touch.reverse();

  @override
  Widget build(BuildContext context) {
    // Listener sees every touch without taking it away from the buttons.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointer,
      onPointerMove: _onPointer,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: ColoredBox(
        color: GwColors.background,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _BackgroundPainter(
                      drift: _drift,
                      touch: _touch,
                      touchPoint: _touchPoint,
                    ),
                  ),
                ),
              ),
            ),
            widget.child,
          ],
        ),
      ),
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  _BackgroundPainter({
    required this.drift,
    required this.touch,
    required this.touchPoint,
  }) : super(repaint: Listenable.merge([drift, touch, touchPoint]));

  final Animation<double> drift;
  final Animation<double> touch;
  final ValueNotifier<Offset> touchPoint;

  static const double _spacing = 15;
  static const double _maxRadius = 3.6;
  static const double _touchReach = 130;

  // colour, phase, x position, y position, size, strength
  static const _fades = [
    (Color(0xFFFF343C), 0.00, 0.15, 0.08, 0.90, 0.20),
    (Color(0xFFB71922), 0.40, 0.92, 0.50, 0.70, 0.13),
    (Color(0xFFFF5A3D), 0.72, 0.25, 0.95, 0.65, 0.09),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = drift.value * 2 * math.pi;

    _paintFades(canvas, size, t);
    _paintDots(canvas, size, t);
  }

  void _paintFades(Canvas canvas, Size size, double t) {
    for (final (color, phase, x, y, scale, alpha) in _fades) {
      final p = phase * 2 * math.pi;
      final center = Offset(
        size.width * (x + 0.10 * math.cos(t + p)),
        size.height * (y + 0.05 * math.sin(t + p)),
      );
      final radius = size.width * scale * (1 + 0.10 * math.sin(t + p));

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  void _paintDots(Canvas canvas, Size size, double t) {
    final paint = Paint()..color = GwColors.accent.withValues(alpha: 0.72);

    final columns = (size.width / _spacing).ceil() + 1;
    final rows = (size.height / _spacing).ceil() + 1;
    final offsetX = (size.width - (columns - 1) * _spacing) / 2;
    final offsetY = (size.height - (rows - 1) * _spacing) / 2;

    final touchStrength = Curves.easeOut.transform(touch.value);
    final finger = touchPoint.value;

    for (var row = 0; row < rows; row++) {
      final y = offsetY + row * _spacing;
      final ny = y / size.height;

      // Keep the dots quiet behind the composer at the bottom.
      final calm = 1 - 0.75 * Curves.easeIn.transform(ny.clamp(0.0, 1.0));

      for (var column = 0; column < columns; column++) {
        final x = offsetX + column * _spacing;
        final nx = x / size.width;

        // Two wave fronts crossing each other make soft moving bands.
        final a = math.sin(nx * 5.2 + ny * 2.4 - t);
        final b = math.sin(nx * 2.1 - ny * 6.0 + t * 2 + 1.3);
        var level = ((a + b) * 0.25 + 0.5) * calm;
        level = level * math.sqrt(level);

        if (touchStrength > 0) {
          final distance = (Offset(x, y) - finger).distance;
          if (distance < _touchReach) {
            final near = 1 - distance / _touchReach;
            level += near * near * 1.4 * touchStrength;
          }
        }

        final radius = _maxRadius * level.clamp(0.0, 1.35);
        if (radius < 0.35) continue;

        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_BackgroundPainter oldDelegate) => false;
}
