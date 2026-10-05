import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'mobile_style.dart';

/// Rises and fades in after [index] × a short step: a screen's parts arrive
/// one after another. Still when the user asked for less motion.
class SmAppear extends StatefulWidget {
  const SmAppear({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<SmAppear> createState() => _SmAppearState();
}

class _SmAppearState extends State<SmAppear>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(
      Duration(milliseconds: 45 * math.min(widget.index, 12)),
      () {
        if (mounted) _in.forward();
      },
    );
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (smReduceMotion(context)) return widget.child;
    final curve = CurvedAnimation(parent: _in, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.12),
          end: Offset.zero,
        ).animate(curve),
        child: widget.child,
      ),
    );
  }
}

/// A row or button that dips a little under the finger, with a haptic tick.
class SmPressable extends StatefulWidget {
  const SmPressable({
    super.key,
    required this.onTap,
    required this.child,
    this.haptic = SmHaptics.select,
    this.scale = 0.97,
    this.semanticLabel,
  });

  final VoidCallback? onTap;
  final Widget child;
  final void Function() haptic;
  final double scale;
  final String? semanticLabel;

  @override
  State<SmPressable> createState() => _SmPressableState();
}

class _SmPressableState extends State<SmPressable> {
  var _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapCancel: () => _set(false),
        onTapUp: (_) => _set(false),
        onTap: enabled
            ? () {
                widget.haptic();
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: smReduceMotion(context)
              ? Duration.zero
              : const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

/// A mastery ring that fills to [value] (0–1) when it first shows.
class SmRing extends StatelessWidget {
  const SmRing({
    super.key,
    required this.value,
    this.size = 46,
    this.stroke = 3.5,
    this.label,
    this.labelSize = 11,
    this.caption,
  });

  final double value;
  final double size;
  final double stroke;

  /// In the middle; defaults to the percentage.
  final String? label;
  final double labelSize;

  /// A small word under the number ("mastered").
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final target = value.clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: target),
      duration: smReduceMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(v, c.line, c.accent, stroke),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label ?? '${(target * 100).round()}%',
                  style: TextStyle(
                    fontFamily: SmFonts.heading,
                    fontSize: labelSize,
                    fontWeight: FontWeight.w600,
                    color: c.text,
                  ),
                ),
                if (caption != null)
                  Text(
                    caption!,
                    style: TextStyle(
                      fontFamily: SmFonts.body,
                      fontSize: 12,
                      color: c.hint,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.track, this.fill, this.stroke);

  final double value;
  final Color track;
  final Color fill;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final circle = rect.deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(circle, 0, math.pi * 2, false, paint..color = track);
    if (value > 0) {
      canvas.drawArc(
        circle,
        -math.pi / 2,
        // A sliver at least, so a started topic shows.
        math.max(value, 0.02) * math.pi * 2,
        false,
        paint..color = fill,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.track != track || old.fill != fill;
}
