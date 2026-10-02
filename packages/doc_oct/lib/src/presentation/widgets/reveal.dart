import 'package:flutter/material.dart';

/// A one-shot entrance animation — fades in and drifts up its [child] shortly
/// after it mounts. Give siblings increasing [delay]s for a staggered reveal.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 460),
    this.offset = 14,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  /// Vertical distance (px) the child rises from.
  final double offset;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  // The delay is a leading idle stretch of the animation itself (no timer to
  // leave pending or to fire after dispose).
  late final Duration _total = widget.delay + widget.duration;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _total,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _c,
    curve: Interval(
      widget.delay.inMicroseconds / _total.inMicroseconds,
      1,
      curve: Curves.easeOutCubic,
    ),
  );

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (_, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(
          offset: Offset(0, widget.offset * (1 - _curve.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
