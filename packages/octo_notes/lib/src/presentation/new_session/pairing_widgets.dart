import 'dart:async';
import 'dart:math' as math;

import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The pairing screens' haptics, one name per moment.
abstract final class PairHaptics {
  static void key() => HapticFeedback.lightImpact();
  static void select() => HapticFeedback.selectionClick();
  static void found() => HapticFeedback.mediumImpact();
  static void start() => HapticFeedback.heavyImpact();

  /// Two beats: paired.
  static Future<void> success() async {
    await HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 110));
    await HapticFeedback.lightImpact();
  }

  /// Three short buzzes: wrong code.
  static Future<void> error() async {
    for (var i = 0; i < 3; i++) {
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 70));
    }
  }
}

/// Two options with a pill that slides (springy) to the chosen one.
class PairSegment extends StatelessWidget {
  const PairSegment({super.key, required this.labels, required this.icons, required this.index, required this.onChanged});

  final List<String> labels;
  final List<IconData> icons;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(99)),
      child: Stack(
        children: [
          AnimatedAlign(
            alignment: index == 0 ? Alignment.centerLeft : Alignment.centerRight,
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutBack,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(99)),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == index,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(99),
                      onTap: i == index
                          ? null
                          : () {
                              PairHaptics.select();
                              onChanged(i);
                            },
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 250),
                          style: theme.textTheme.labelLarge!.copyWith(
                            color: i == index ? scheme.onSurface : scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icons[i], size: 16, color: i == index ? scheme.onSurface : scheme.onSurfaceVariant),
                              const SizedBox(width: 6),
                              Text(labels[i]),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The 6-digit code rolling in digit by digit ("482 913").
class RollingCode extends StatefulWidget {
  const RollingCode({super.key, required this.code});
  final String code;

  @override
  State<RollingCode> createState() => _RollingCodeState();
}

class _RollingCodeState extends State<RollingCode> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();

  @override
  void didUpdateWidget(covariant RollingCode old) {
    super.didUpdateWidget(old);
    if (old.code != widget.code) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.displaySmall?.copyWith(
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
    final digits = widget.code.split('');
    return Semantics(
      label: 'Pairing code ${digits.join(' ')}',
      child: ExcludeSemantics(
        child: ClipRect(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < digits.length; i++) ...[
                  if (i == 3) const SizedBox(width: 14),
                  Builder(builder: (context) {
                    final t = Curves.easeOutBack.transform(
                        Interval(i * 0.09, math.min(1, i * 0.09 + 0.45)).transform(_c.value).clamp(0.0, 1.0));
                    return Opacity(
                      opacity: t.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, (1 - t) * 36),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Text(digits[i], style: style),
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rings rippling out behind the code or QR while it waits.
class RadarRings extends StatefulWidget {
  const RadarRings({super.key, required this.child, this.size = 200});
  final Widget child;
  final double size;

  @override
  State<RadarRings> createState() => _RadarRingsState();
}

class _RadarRingsState extends State<RadarRings> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _RadarPainter(_c, Theme.of(context).colorScheme.primary)),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.t, this.color) : super(repaint: t);
  final Animation<double> t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final base = size.shortestSide * 0.38;
    for (var i = 0; i < 3; i++) {
      final p = (t.value + i / 3) % 1;
      canvas.drawCircle(
        c,
        base * (0.6 + p * 0.95),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withValues(alpha: (1 - p) * 0.55),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) => old.color != color;
}

/// A small ring that empties as the code's time runs out, plus "9:41".
class CountdownRing extends StatefulWidget {
  const CountdownRing({super.key, required this.expiresAt, this.total = const Duration(minutes: 10)});
  final DateTime? expiresAt;
  final Duration total;

  @override
  State<CountdownRing> createState() => _CountdownRingState();
}

class _CountdownRingState extends State<CountdownRing> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final left = widget.expiresAt?.difference(DateTime.now()) ?? widget.total;
    final secs = left.inSeconds.clamp(0, widget.total.inSeconds);
    final frac = secs / widget.total.inSeconds;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            value: frac,
            strokeWidth: 3,
            color: CockpitColors.brand.tertiary,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// A check that draws itself, with a burst of brand-coloured dots.
class SuccessCheck extends StatefulWidget {
  const SuccessCheck({super.key, this.size = 80});
  final double size;

  @override
  State<SuccessCheck> createState() => _SuccessCheckState();
}

class _SuccessCheckState extends State<SuccessCheck> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.size * 1.9,
        height: widget.size * 1.9,
        child: CustomPaint(
          painter: _CheckPainter(_c, CockpitColors.brand, Theme.of(context).colorScheme.onSurface),
        ),
      );
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.t, this.brand, this.light) : super(repaint: t);
  final Animation<double> t;
  final CockpitColors brand;
  final Color light;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 1.9 / 2;
    final green = brand.success;
    final v = t.value;

    // Burst: 18 dots flying out and fading.
    final b = const Interval(0.15, 0.9, curve: Curves.easeOutCubic).transform(v);
    if (b > 0 && b < 1) {
      final colors = [brand.primary, brand.tertiary, green, light];
      for (var i = 0; i < 18; i++) {
        final a = i / 18 * math.pi * 2 + (i.isEven ? 0.1 : -0.1);
        final d = r * (1.05 + b * (0.75 + (i % 3) * 0.12));
        canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * d, 3.2 * (1 - b * 0.7),
            Paint()..color = colors[i % 4].withValues(alpha: 1 - b));
      }
    }

    // Disc pops in.
    final s = Curves.easeOutBack.transform(const Interval(0, 0.45).transform(v));
    canvas.drawCircle(c, r * s, Paint()..color = green.withValues(alpha: 0.16));
    canvas.drawCircle(
        c,
        r * s,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = green);

    // Check draws itself.
    final path = Path()
      ..moveTo(c.dx - r * 0.38, c.dy + r * 0.02)
      ..lineTo(c.dx - r * 0.1, c.dy + r * 0.3)
      ..lineTo(c.dx + r * 0.42, c.dy - r * 0.28);
    final p = const Interval(0.3, 0.75, curve: Curves.easeOut).transform(v);
    for (final m in path.computeMetrics()) {
      canvas.drawPath(
        m.extractPath(0, m.length * p),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.11
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = green,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CheckPainter old) => false;
}

/// How the code boxes look right now.
enum CodeBoxesState { typing, wrong, right }

/// Six boxes for the code: the next one has a blinking caret, a new digit
/// pops in, a wrong code goes red, the right one ripples green.
class CodeBoxes extends StatelessWidget {
  const CodeBoxes({super.key, required this.value, this.state = CodeBoxesState.typing});
  final String value;
  final CodeBoxesState state;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Pairing code, ${value.length} of 6 digits',
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 6; i++) ...[
              if (i == 3) const SizedBox(width: 10),
              _Box(index: i, digit: i < value.length ? value[i] : null, current: i == value.length, state: state),
              if (i != 5 && i != 2) const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.index, required this.digit, required this.current, required this.state});
  final int index;
  final String? digit;
  final bool current;
  final CodeBoxesState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brand = CockpitColors.brand;
    final (border, fill) = switch (state) {
      CodeBoxesState.wrong => (brand.error, brand.error.withValues(alpha: 0.1)),
      CodeBoxesState.right => (brand.success, brand.success.withValues(alpha: 0.12)),
      _ => (current ? scheme.primary : scheme.outlineVariant, scheme.surfaceContainerLow),
    };
    Widget box = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 42,
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 1.6),
        boxShadow: current && state == CodeBoxesState.typing
            ? [BoxShadow(color: scheme.primary.withValues(alpha: 0.18), spreadRadius: 4)]
            : null,
      ),
      child: digit != null
          ? TweenAnimationBuilder<double>(
              key: ValueKey('$index$digit'),
              tween: Tween(begin: 0.5, end: 1),
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutBack,
              builder: (_, s, child) => Transform.scale(scale: s, child: child),
              child: Text(digit!,
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            )
          : current && state == CodeBoxesState.typing
              ? const _Caret()
              : null,
    );
    if (state == CodeBoxesState.right) {
      // A green wave across the boxes.
      box = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 420 + index * 60),
        builder: (_, t, child) {
          final local = ((t * (420 + index * 60) - index * 60) / 420).clamp(0.0, 1.0);
          return Transform.translate(offset: Offset(0, -math.sin(local * math.pi) * 7), child: child);
        },
        child: box,
      );
    }
    return box;
  }
}

class _Caret extends StatefulWidget {
  const _Caret();
  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Opacity(
          opacity: _c.value < 0.5 ? 1 : 0,
          child: Container(width: 2, height: 24, color: Theme.of(context).colorScheme.primary),
        ),
      );
}

/// A number pad: 1–9, paste, 0, delete.
class NumberPad extends StatelessWidget {
  const NumberPad({super.key, required this.onDigit, required this.onDelete, required this.onPaste});
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget key(Widget child, VoidCallback onTap, {String? label, bool ghost = false}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Semantics(
              button: true,
              label: label,
              child: Material(
                color: ghost ? Colors.transparent : scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    PairHaptics.key();
                    onTap();
                  },
                  child: SizedBox(height: 52, child: Center(child: child)),
                ),
              ),
            ),
          ),
        );
    final style = Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w500);
    Widget digit(String d) => key(Text(d, style: style), () => onDigit(d));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(children: [for (final d in row) digit(d)]),
        Row(
          children: [
            key(Icon(Icons.content_paste_rounded, color: scheme.onSurfaceVariant), onPaste, label: 'Paste', ghost: true),
            digit('0'),
            key(Icon(Icons.backspace_outlined, color: scheme.onSurfaceVariant), onDelete, label: 'Delete', ghost: true),
          ],
        ),
      ],
    );
  }
}

/// Shakes its child when [trigger] changes (a wrong code).
class Shake extends StatefulWidget {
  const Shake({super.key, required this.trigger, required this.child});
  final int trigger;
  final Widget child;

  @override
  State<Shake> createState() => _ShakeState();
}

class _ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));

  @override
  void didUpdateWidget(covariant Shake old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Transform.translate(
          offset: Offset(math.sin(_c.value * math.pi * 4) * 9 * (1 - _c.value), 0),
          child: child,
        ),
        child: widget.child,
      );
}
