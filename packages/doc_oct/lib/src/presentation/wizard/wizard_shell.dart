import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';

import '../widgets/doc_widgets.dart';
import '../widgets/motion.dart';

/// The wizard frame, restyled borderless. Keeps the web's two-part composition —
/// a left context rail (eyebrow · display headline · step tracker) and a
/// right content column — but strips the grid, glows and number watermark; the
/// charcoal page + whitespace do the work.
class WizardShell extends StatelessWidget {
  const WizardShell({
    super.key,
    required this.step,
    required this.eyebrow,
    required this.headline,
    required this.child,
    this.onBack,
    this.scroll = false,
    this.wideContent = false,
  });

  /// 1..3
  final int step;
  final String eyebrow;

  /// The display headline, one span per line (a line may be red). Each line
  /// rises into place in turn when the page appears.
  final List<InlineSpan> headline;
  final Widget child;
  final VoidCallback? onBack;

  /// When true the content column can overflow and scrolls (top-aligned)
  /// instead of vertically centering — used by the taller Analysis step.
  final bool scroll;

  /// Give the content column most of the width (a narrower rail) — for a
  /// step with a lot to show, like the Analysis breakdown + outline.
  final bool wideContent;

  static const _labels = ['Topic', 'Setup', 'Analysis'];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // The headline scales with the window so it holds its half of the layout.
    final headlineSize = wide
        ? (width * (wideContent ? 0.027 : 0.031)).clamp(34.0, 46.0)
        : 32.0;

    // Tighter padding on the inner edges keeps the two halves close together.
    final rail = Padding(
      padding: wide
          ? const EdgeInsets.fromLTRB(
              CockpitSpacing.xxxl,
              CockpitSpacing.xxxl,
              CockpitSpacing.xl,
              CockpitSpacing.xxxl,
            )
          : const EdgeInsets.all(CockpitSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (wide) const Spacer(),
          // Entrance: eyebrow slides in, then each headline line rises from
          // behind its baseline, then the step tracker plays.
          MaskReveal(
            delay: kEntranceDelay,
            axis: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 18, height: 1.5, color: scheme.primary),
                const SizedBox(width: CockpitSpacing.sm),
                Text(
                  eyebrow.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: CockpitSpacing.lg),
          DefaultTextStyle.merge(
            style: theme.textTheme.displaySmall?.copyWith(
              fontSize: headlineSize,
              fontWeight: FontWeight.w700,
              height: 1.08,
              letterSpacing: -headlineSize * 0.022,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < headline.length; i++)
                  MaskReveal(
                    delay:
                        kEntranceDelay + Duration(milliseconds: 120 * (i + 1)),
                    child: Text.rich(headline[i]),
                  ),
              ],
            ),
          ),
          if (wide)
            const Spacer()
          else
            const SizedBox(height: CockpitSpacing.xl),
          _StepTracker(
            step: step,
            label: _labels[step - 1],
            delay:
                kEntranceDelay +
                Duration(milliseconds: 120 * (headline.length + 1)),
          ),
        ],
      ),
    );

    // Vertically center the content only when it fits (wide, non-scroll);
    // otherwise top-align so it can grow and scroll.
    final centered = wide && !scroll;
    final content = Padding(
      padding: wide
          ? const EdgeInsets.fromLTRB(
              CockpitSpacing.xl,
              CockpitSpacing.xxxl,
              CockpitSpacing.xxxl,
              CockpitSpacing.xxxl,
            )
          : const EdgeInsets.all(CockpitSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: centered ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: centered
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          if (onBack != null) ...[
            _BackButton(onTap: onBack!),
            const SizedBox(height: CockpitSpacing.xl),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wideContent ? 980 : 520),
            child: child,
          ),
        ],
      ),
    );

    if (!wide) {
      return ListView(children: [rail, content]);
    }
    // Cap the composition width so the two halves read as one layout instead
    // of drifting to opposite edges of a wide screen.
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: wideContent ? 1360 : 1200),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: wideContent ? 4 : 1, child: rail),
            Expanded(
              flex: wideContent ? 9 : 1,
              child: scroll ? SingleChildScrollView(child: content) : content,
            ),
          ],
        ),
      ),
    );
  }
}

/// The 1 · 2 · 3 progress stepper, animated as the page appears: the segment
/// you just completed fills in, its check mark draws itself, and the current
/// step pops in and keeps a slow pulsing ring.
class _StepTracker extends StatefulWidget {
  const _StepTracker({
    required this.step,
    required this.label,
    this.delay = Duration.zero,
  });
  final int step;
  final String label;
  final Duration delay;

  @override
  State<_StepTracker> createState() => _StepTrackerState();
}

class _StepTrackerState extends State<_StepTracker>
    with TickerProviderStateMixin {
  static const _entrance = Duration(milliseconds: 1300);

  /// Pulses of the "you are here" ring after the entrance, then it rests.
  static const _pulses = 3;

  /// The one-shot entrance. Its duration includes the start [delay] as a
  /// leading idle stretch (no timers to leave pending).
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: widget.delay + _entrance,
  );

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  int _pulsesLeft = _pulses;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _in.value = 1;
      return;
    }
    _in.forward().whenComplete(_nextPulse);
  }

  void _nextPulse() {
    if (!mounted || _pulsesLeft-- <= 0) return;
    _pulse.forward(from: 0).whenComplete(_nextPulse);
  }

  @override
  void dispose() {
    _in.dispose();
    _pulse.dispose();
    super.dispose();
  }

  /// Entrance progress (0 → 1) after the delay.
  double get _v {
    final total = _in.duration!.inMicroseconds;
    final lead = widget.delay.inMicroseconds;
    return ((_in.value * total - lead) / (total - lead)).clamp(0.0, 1.0);
  }

  /// [_v] mapped into [begin, end], eased.
  double _seg(double begin, double end, [Curve curve = kEntranceCurve]) =>
      curve.transform(((_v - begin) / (end - begin)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final step = widget.step;

    return AnimatedBuilder(
      animation: Listenable.merge([_in, _pulse]),
      builder: (context, _) {
        Widget dot(int n) {
          final active = n == step;
          final done = n < step;
          // Earlier steps settle first; the current one pops in last.
          final appear = _seg(0.05 * n, 0.3 + 0.05 * n);
          final pop = active ? _seg(0.35, 0.8, Curves.easeOutBack) : 1.0;
          final check = done ? _seg(0.1, 0.45, Curves.easeOutCubic) : 0.0;
          final p = _pulse.value;

          return SizedBox(
            width: 26,
            height: 26,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                if (active && _pulse.isAnimating && p > 0)
                  // The ring grows out of the dot and fades away.
                  Container(
                    width: 26 + 16 * p,
                    height: 26 + 16 * p,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.5 * (1 - p)),
                        width: 1.5,
                      ),
                    ),
                  ),
                Opacity(
                  opacity: appear,
                  child: Transform.scale(
                    scale: active ? 0.55 + 0.45 * pop : 1,
                    child: Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: active
                            ? scheme.primary
                            : done
                            ? scheme.onSurface.withValues(alpha: 0.14)
                            : Colors.transparent,
                        border: active || done
                            ? null
                            : Border.all(
                                color: scheme.onSurface.withValues(alpha: 0.1),
                              ),
                        boxShadow: active
                            ? [
                                BoxShadow(
                                  color: scheme.primary.withValues(
                                    alpha: 0.45 * pop.clamp(0.0, 1.0),
                                  ),
                                  blurRadius: 14,
                                ),
                              ]
                            : null,
                      ),
                      child: done
                          ? CustomPaint(
                              size: const Size(12, 12),
                              painter: _CheckPainter(
                                progress: check,
                                color: scheme.onSurface.withValues(alpha: 0.75),
                              ),
                            )
                          : Text(
                              '$n',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: active
                                    ? Colors.white
                                    : scheme.onSurfaceVariant.withValues(
                                        alpha: 0.6,
                                      ),
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        Widget line(int n) {
          // The segment leading into the current step fills left → right.
          final fill = n < step ? _seg(0.12, 0.55, Curves.easeInOutCubic) : 0.0;
          return Container(
            width: 26,
            height: 1.5,
            margin: const EdgeInsets.symmetric(horizontal: CockpitSpacing.sm),
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(1),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fill,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      scheme.primary.withValues(alpha: 0.35),
                      scheme.primary.withValues(alpha: 0.8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          );
        }

        final labelIn = _seg(0.55, 1.0);
        return Row(
          children: [
            for (var n = 1; n <= 3; n++) ...[dot(n), if (n < 3) line(n)],
            const SizedBox(width: CockpitSpacing.md),
            Opacity(
              opacity: labelIn,
              child: Transform.translate(
                offset: Offset(-8 * (1 - labelIn), 0),
                child: Text(
                  widget.label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A check mark that draws itself as [progress] goes 0 → 1.
class _CheckPainter extends CustomPainter {
  _CheckPainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.12, h * 0.55)
      ..lineTo(w * 0.4, h * 0.8)
      ..lineTo(w * 0.9, h * 0.22);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * progress),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.progress != progress || old.color != color;
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      pressedScale: 0.9,
      child: DocHoverRow(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.sm,
          vertical: CockpitSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chevron_left_rounded,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 2),
            Text(
              'Back',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
