import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Whether to keep motion to a minimum (the OS "reduce motion" setting).
/// Endless animations stop and entrances are instant.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

const Curve kShellEase = Curves.easeOutCubic;

/// [duration], or none with reduced motion.
Duration motion(BuildContext context, Duration duration) =>
    reduceMotion(context) ? Duration.zero : duration;

/// Fades and slides [child] in once, after [delay]. Lists stagger with it.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 520),
    this.offset = const Offset(0, 0.18),
    this.scale = 0.96,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  /// Where it comes from, as a fraction of its size.
  final Offset offset;
  final double scale;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.duration);
  late final _t = CurvedAnimation(parent: _c, curve: kShellEase);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.status != AnimationStatus.dismissed) return;
    if (reduceMotion(context)) {
      _c.value = 1;
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _t,
    child: SlideTransition(
      position: Tween(begin: widget.offset, end: Offset.zero).animate(_t),
      child: ScaleTransition(
        scale: Tween(begin: widget.scale, end: 1.0).animate(_t),
        child: widget.child,
      ),
    ),
  );
}

/// Shrinks a little while pressed, springs back on release.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.scale = 0.96,
    this.onLongPress,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  var _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: Duration(milliseconds: _down ? 90 : 380),
        curve: _down ? Curves.easeOut : Curves.elasticOut,
        child: widget.child,
      ),
    );
  }
}

/// Three dots that bounce in turn.
class BouncingDots extends StatefulWidget {
  const BouncingDots({super.key, required this.color, this.size = 7});

  final Color color;
  final double size;

  @override
  State<BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<BouncingDots>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!reduceMotion(context) && !_c.isAnimating) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Transform.translate(
              offset: Offset(0, -_hop((_c.value - i * 0.16) % 1) * 6),
              child: Container(
                width: widget.size,
                height: widget.size,
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                decoration: BoxDecoration(
                  color: widget.color.withValues(
                    alpha: 0.45 + 0.55 * _hop((_c.value - i * 0.16) % 1),
                  ),
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Up and down in the first 40% of the cycle, still for the rest.
  static double _hop(double t) =>
      t < 0.4 ? Curves.easeInOut.transform(1 - (t / 0.2 - 1).abs()) : 0;
}

/// The page transition: the new page rises and fades in over a slight zoom.
Widget shellPageTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondary,
  Widget child,
) {
  final t = CurvedAnimation(
    parent: animation,
    curve: kShellEase,
    reverseCurve: Curves.easeInCubic,
  );
  final out = CurvedAnimation(parent: secondary, curve: Curves.easeInOutCubic);
  return FadeTransition(
    opacity: Tween(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: out, curve: const Interval(0, 0.7))),
    child: ScaleTransition(
      scale: Tween(begin: 1.0, end: 0.94).animate(out),
      child: FadeTransition(
        opacity: t,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(t),
          child: ScaleTransition(
            scale: Tween(begin: 1.04, end: 1.0).animate(t),
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// Touch feedback, named for what it means.
abstract final class Haptics {
  /// A choice changed (a voice, a mode).
  static void select() => HapticFeedback.selectionClick();

  /// A light tap: a button, the mic opening.
  static void tap() => HapticFeedback.lightImpact();

  /// Something starts: the voice begins to speak.
  static void thud() => HapticFeedback.mediumImpact();

  /// Something ends: the voice call.
  static void end() => HapticFeedback.heavyImpact();
}
