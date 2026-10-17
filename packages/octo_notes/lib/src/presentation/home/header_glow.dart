import 'dart:math' as math;

import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// The phone home's background: a soft red-and-gold glow behind the header
/// and the live session that drifts on its own and leans toward a finger or
/// the pointer, then fades out before the content below. Everything else on
/// the page stays the plain borderless surface.
class HeaderGlow extends StatefulWidget {
  const HeaderGlow({super.key, required this.child, this.height = 340});

  final Widget child;

  /// How far down the glow reaches before it has faded out.
  final double height;

  @override
  State<HeaderGlow> createState() => _HeaderGlowState();
}

class _HeaderGlowState extends State<HeaderGlow>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _glow = ValueNotifier<_GlowState>(const _GlowState(Offset(.6, .28), 0));
  Offset? _target;
  Duration _lastTouch = Duration.zero;
  Duration _now = Duration.zero;
  Size _size = Size.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still && _ticker.isActive) _ticker.stop();
    if (!still && !_ticker.isActive) _ticker.start();
  }

  void _tick(Duration now) {
    _now = now;
    final t = now.inMilliseconds / 1000;
    // Idle a few seconds: drift on a slow loop. Otherwise lean to the touch.
    final idle =
        _target == null || now - _lastTouch > const Duration(seconds: 3);
    final aim = idle
        ? Offset(.6 + math.sin(t * .4) * .18, .26 + math.cos(t * .3) * .08)
        : _target!;
    final cur = _glow.value.focus;
    _glow.value = _GlowState(Offset.lerp(cur, aim, .04)!, t);
  }

  void _touch(Offset local) {
    if (_size.isEmpty) return;
    // Only the band the glow lives in pulls it.
    _target = Offset(
      (local.dx / _size.width).clamp(0, 1),
      (local.dy / widget.height).clamp(0, .62),
    );
    _lastTouch = _now;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => _touch(e.localPosition),
      onPointerMove: (e) => _touch(e.localPosition),
      onPointerHover: (e) => _touch(e.localPosition),
      onPointerSignal: (e) {
        if (e is PointerScrollEvent) _lastTouch = Duration.zero;
      },
      child: LayoutBuilder(
        builder: (context, box) {
          _size = box.biggest;
          return Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: widget.height,
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _GlowPainter(_glow, dark: dark),
                    ),
                  ),
                ),
              ),
              widget.child,
            ],
          );
        },
      ),
    );
  }
}

@immutable
class _GlowState {
  const _GlowState(this.focus, this.t);

  /// Where the glow centres, as fractions of the band's width and height.
  final Offset focus;
  final double t;
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.glow, {required this.dark}) : super(repaint: glow);

  final ValueNotifier<_GlowState> glow;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final s = glow.value;
    final red = CockpitColors.brand.primary;
    final gold = CockpitColors.brand.tertiary;
    final c = Offset(s.focus.dx * size.width, s.focus.dy * size.height);
    final blobs = [
      (c, size.width * .55, red.withValues(alpha: dark ? .22 : .16)),
      (
        c +
            Offset(
              -size.width * .28 + math.sin(s.t * .7) * 26,
              size.height * .12,
            ),
        size.width * .42,
        gold.withValues(alpha: dark ? .16 : .14),
      ),
    ];
    final layer = Offset.zero & size;
    canvas.saveLayer(layer, Paint());
    for (final (center, radius, color) in blobs) {
      canvas.drawRect(
        layer,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
    // Fade to nothing before the content below the live session.
    canvas.drawRect(
      layer,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, .55, 1],
          colors: [Colors.white, Colors.white, Color(0x00FFFFFF)],
        ).createShader(layer),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.dark != dark;
}
