import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Doc Oct's motion kit — the tactile layer shared by every screen:
//
// * [Pressable]   — squish on press, springy release, hover lift + glow.
// * [BlinkSwitcher] — page changes as a camera shutter: two flat blades slide
//   in from top + bottom and meet in the middle, the page swaps while it is
//   shut, then the blades slide back out onto the new page.
// * [showDocDialog] — dialogs pop in over a blurred backdrop.
// * [docMotionTheme] — ripples + hover/press states for every Material button.

/// Brand red used for the shutter's edge glow.
const _kRim = Color(0xFFE5283A);

// ── Pressable ────────────────────────────────────────────────────────────────

/// Wraps any tappable (pill, chip, card, button) with physical feedback: it
/// dips while pressed and eases back on release. Hover never moves or resizes
/// anything (that makes text shimmer and wobble) — it only lights up: a soft
/// glow for CTAs, plus the child's own ink hover. It only *listens* to the
/// pointer, so the child's `InkWell` / button keeps handling the tap.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.enabled = true,
    this.pressedScale = 0.96,
    this.glowColor,
    this.borderRadius = const BorderRadius.all(Radius.circular(999)),
  });

  final Widget child;

  /// Disabled controls stay still (no fake feedback).
  final bool enabled;
  final double pressedScale;

  /// A soft colored glow on hover (e.g. the primary red for CTAs).
  final Color? glowColor;
  final BorderRadius borderRadius;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hover = false;
  bool _down = false;

  void _setDown(bool v) {
    if (!widget.enabled || _down == v) return;
    setState(() => _down = v);
    if (v) HapticFeedback.selectionClick();
  }

  void _setHover(bool v) {
    if (_hover == v) return;
    setState(() {
      _hover = v;
      if (!v) _down = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled;
    final glow = widget.glowColor;

    Widget child = widget.child;
    if (glow != null) {
      child = AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          boxShadow: [
            BoxShadow(
              color: glow.withValues(alpha: on && _hover ? 0.38 : 0.0),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      );
    }

    return MouseRegion(
      cursor: on ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: Listener(
        onPointerDown: (_) => _setDown(true),
        onPointerUp: (_) => _setDown(false),
        onPointerCancel: (_) => _setDown(false),
        child: AnimatedScale(
          scale: on && _down ? widget.pressedScale : 1.0,
          // Quick dip in, smooth ease back out — no overshoot, no wobble.
          duration: Duration(milliseconds: _down ? 110 : 200),
          curve: Curves.easeOutCubic,
          child: child,
        ),
      ),
    );
  }
}

// ── Entrances ────────────────────────────────────────────────────────────────

/// Start delay for a page's entrance, so it plays as the shutter opens (the
/// page mounts while the shutter is shut, ~0.38 s into the blink).
const kEntranceDelay = Duration(milliseconds: 180);

/// A decelerating "expo-out" feel shared by the entrances.
const Curve kEntranceCurve = Cubic(0.16, 1, 0.3, 1);

/// A one-shot entrance: the child rises into place from behind an invisible
/// edge just below it (a masked line reveal) while it fades in. Stagger
/// siblings with increasing [delay]s. Plays once, when it mounts.
class MaskReveal extends StatefulWidget {
  const MaskReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 900),
    this.axis = Axis.vertical,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  /// Vertical rises up from below; horizontal slides in from the left.
  final Axis axis;

  @override
  State<MaskReveal> createState() => _MaskRevealState();
}

class _MaskRevealState extends State<MaskReveal>
    with SingleTickerProviderStateMixin {
  // The delay is part of the animation (a leading idle interval) rather than a
  // timer, so nothing is left pending and it can't fire after dispose.
  late final Duration _total = widget.delay + widget.duration;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _total,
  );
  late final double _start =
      widget.delay.inMicroseconds / _total.inMicroseconds;
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Interval(_start, 1, curve: kEntranceCurve),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: Interval(_start, 1, curve: Curves.easeOut),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Respect "reduce motion": just show it.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vertical = widget.axis == Axis.vertical;
    return ClipRect(
      clipper: const _LooseClip(),
      child: AnimatedBuilder(
        animation: _t,
        builder: (_, child) {
          final v = _t.value;
          final off = 1 - v;
          return Opacity(
            opacity: _fade.value,
            child: FractionalTranslation(
              translation: vertical
                  ? Offset(0, off * 1.05)
                  : Offset(-off * 0.15, 0),
              child: child,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// Clips to the child's box, extended a little so glyph descenders and
/// italics are never cut; only the "below the line" start position is hidden.
class _LooseClip extends CustomClipper<Rect> {
  const _LooseClip();
  @override
  Rect getClip(Size s) =>
      Rect.fromLTRB(-24, -s.height * 0.3, s.width + 24, s.height * 1.12);
  @override
  bool shouldReclip(_LooseClip old) => false;
}

/// A loading placeholder bar with a soft light sweeping across it — used for
/// skeletons while content is on its way.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, this.width, this.height = 12, this.radius = 6});

  final double? width;
  final double height;
  final double radius;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = Theme.of(context).colorScheme.onSurface;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final x = -2.0 + 4.0 * _c.value; // sweep from left of bar to right
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(x - 1, 0),
              end: Alignment(x + 1, 0),
              colors: [
                on.withValues(alpha: 0.05),
                on.withValues(alpha: 0.13),
                on.withValues(alpha: 0.05),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Blink / shutter page transition ──────────────────────────────────────────

/// How shut the shutter is at progress [t] (0…1): 0 = open, 1 = shut.
/// Closes fast, holds a beat while the page swaps, opens a touch slower.
double blinkClosure(double t) {
  const closeEnd = 0.40, openStart = 0.52;
  if (t <= closeEnd) return Curves.easeInCubic.transform(t / closeEnd);
  if (t < openStart) return 1;
  return 1 - Curves.easeOutCubic.transform((t - openStart) / (1 - openStart));
}

/// Switches between pages with a camera-shutter blink. Give each page a
/// distinct [pageKey]; when it changes the blades close over the old page, the
/// new page is swapped in while shut, and the blades open onto it.
class BlinkSwitcher extends StatefulWidget {
  const BlinkSwitcher({
    super.key,
    required this.pageKey,
    required this.child,
    this.duration = const Duration(milliseconds: 820),
  });

  final Object pageKey;
  final Widget child;
  final Duration duration;

  @override
  State<BlinkSwitcher> createState() => _BlinkSwitcherState();
}

class _BlinkSwitcherState extends State<BlinkSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..value = 1;

  /// The page still on screen until the shutter is shut.
  Widget? _outgoing;
  Object? _outgoingKey;

  @override
  void didUpdateWidget(BlinkSwitcher old) {
    super.didUpdateWidget(old);
    if (old.pageKey != widget.pageKey) {
      // Mid-blink re-navigation: keep whatever is currently visible.
      if (!(_c.isAnimating && _c.value < 0.5)) {
        _outgoing = old.child;
        _outgoingKey = old.pageKey;
      }
      _c.forward(from: 0);
    }
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
      builder: (context, _) {
        final t = _c.value;
        final settled = !_c.isAnimating;
        final c = settled ? 0.0 : blinkClosure(t);
        final showNew = settled || t >= 0.46 || _outgoing == null;
        final page = showNew
            ? KeyedSubtree(key: ValueKey(widget.pageKey), child: widget.child)
            : KeyedSubtree(key: ValueKey(_outgoingKey), child: _outgoing!);
        if (settled) _outgoing = null;

        // The old page recedes as the blades close; the new one settles from a
        // slight zoom as they open — plus a focus-pull blur while shut. The
        // tree shape never changes (so pages keep their state); at rest the
        // blur is disabled and the shutter paints nothing.
        final scale = showNew ? 1 + 0.035 * c : 1 - 0.03 * c;
        final blur = 7.0 * c;
        return Stack(
          fit: StackFit.expand,
          children: [
            AbsorbPointer(
              absorbing: !settled, // no double-taps mid-blink
              child: ImageFiltered(
                enabled: blur > 0.01,
                imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: Transform.scale(scale: scale, child: page),
              ),
            ),
            IgnorePointer(child: CustomPaint(painter: _ShutterPainter(c))),
          ],
        );
      },
    );
  }
}

/// A two-blade camera shutter: flat top and bottom halves slide in and meet in
/// the middle, then slide back out.
class _ShutterPainter extends CustomPainter {
  _ShutterPainter(this.c);

  /// Closure: 0 open … 1 shut.
  final double c;

  @override
  void paint(Canvas canvas, Size size) {
    if (c <= 0) return;
    final w = size.width, h = size.height, mid = h / 2;
    // Each blade covers `reach` px from its side; at c = 1 they meet at `mid`.
    final reach = mid * c;

    // The scene darkens as the shutter closes.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(w / 2, mid),
          math.max(w, h) * 0.75,
          [Colors.transparent, Colors.black.withValues(alpha: 0.5 * c)],
        ),
    );

    // Blades — near-black, a touch lighter toward the leading edge — each
    // throwing a soft shadow onto the page just past its edge.
    void blade({required bool top}) {
      final edgeY = top ? reach : h - reach;
      final rect = top
          ? Rect.fromLTRB(0, -1, w, edgeY)
          : Rect.fromLTRB(0, edgeY, w, h + 1);
      if (c < 1) {
        const shadow = 18.0;
        final s = top
            ? Rect.fromLTRB(0, edgeY, w, edgeY + shadow)
            : Rect.fromLTRB(0, edgeY - shadow, w, edgeY);
        canvas.drawRect(
          s,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset(0, edgeY),
              Offset(0, top ? edgeY + shadow : edgeY - shadow),
              [Colors.black.withValues(alpha: 0.45 * c), Colors.transparent],
            ),
        );
      }
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, top ? 0 : h),
            Offset(0, edgeY),
            const [Color(0xFF050506), Color(0xFF18181B)],
          ),
      );
      // Faint seams between the blade's slats (a real shutter's leaves).
      final seam = Paint()
        ..color = Colors.white.withValues(alpha: 0.035)
        ..strokeWidth = 1;
      for (final f in const [0.33, 0.66]) {
        final y = top ? edgeY * f : h - (h - edgeY) * f;
        canvas.drawLine(Offset(0, y), Offset(w, y), seam);
      }
    }

    blade(top: true);
    blade(top: false);

    // Leading edges: a crisp red line with a soft glow, brightest when shut.
    final glow = Paint()
      ..strokeWidth = 6
      ..color = _kRim.withValues(alpha: 0.5 * c)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    final line = Paint()
      ..strokeWidth = 1.4
      ..color = _kRim.withValues(alpha: 0.9 * c);
    for (final y in [reach, h - reach]) {
      canvas.drawLine(Offset(0, y), Offset(w, y), glow);
      canvas.drawLine(Offset(0, y), Offset(w, y), line);
    }
  }

  @override
  bool shouldRepaint(_ShutterPainter old) => old.c != c;
}

// ── Dialogs ──────────────────────────────────────────────────────────────────

/// `showDialog`, but the dialog pops in (scale with a little overshoot + fade)
/// over a backdrop that blurs in behind it.
Future<T?> showDocDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 420),
    pageBuilder: (ctx, _, _) => builder(ctx),
    transitionBuilder: (ctx, anim, _, child) {
      final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
      final pop = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      );
      return BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: 8 * fade.value,
          sigmaY: 8 * fade.value,
        ),
        child: FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: Tween(begin: 0.86, end: 1.0).animate(pop),
            child: child,
          ),
        ),
      );
    },
  );
}

// ── Theme ────────────────────────────────────────────────────────────────────

/// Adds motion to every Material button under Doc Oct: expanding ink ripples,
/// a stronger pressed overlay, and a hover lift (elevation) on filled buttons.
ThemeData docMotionTheme(ThemeData base) {
  final scheme = base.colorScheme;
  WidgetStateProperty<Color?> overlay(Color c) =>
      WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.pressed)) return c.withValues(alpha: 0.22);
        if (s.contains(WidgetState.hovered)) return c.withValues(alpha: 0.09);
        if (s.contains(WidgetState.focused)) return c.withValues(alpha: 0.12);
        return null;
      });
  const motion = ButtonStyle(
    animationDuration: Duration(milliseconds: 220),
    splashFactory: InkRipple.splashFactory,
    enableFeedback: true,
  );
  final lift = WidgetStateProperty.resolveWith<double>((s) {
    if (s.contains(WidgetState.disabled)) return 0;
    if (s.contains(WidgetState.pressed)) return 0;
    if (s.contains(WidgetState.hovered)) return 3;
    return 0;
  });

  return base.copyWith(
    splashFactory: InkRipple.splashFactory,
    filledButtonTheme: FilledButtonThemeData(
      style: motion
          .copyWith(
            overlayColor: overlay(Colors.white),
            elevation: lift,
            shadowColor: WidgetStatePropertyAll(
              scheme.primary.withValues(alpha: 0.55),
            ),
          )
          .merge(base.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: motion
          .copyWith(overlayColor: overlay(scheme.onSurface))
          .merge(base.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: motion
          .copyWith(overlayColor: overlay(scheme.primary))
          .merge(base.textButtonTheme.style),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: motion
          .copyWith(overlayColor: overlay(scheme.onSurface))
          .merge(base.iconButtonTheme.style),
    ),
  );
}
