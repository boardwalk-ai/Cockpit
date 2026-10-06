import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/entities/studio.dart';
import '../../domain/entities/topic.dart';
import 'mobile_motion.dart';
import 'mobile_style.dart';

const _green = Color(0xFF30A46C);

/// The moment a studio is built: a check that draws itself, what was made
/// (counting up), and the first lesson one tap away.
class StudioReadyMobile extends StatefulWidget {
  const StudioReadyMobile({
    super.key,
    required this.studio,
    required this.onStart,
    required this.onLook,
    this.builtIn,
    this.updated = false,
  });

  final Studio studio;
  final void Function(Topic topic) onStart;
  final VoidCallback onLook;

  /// How long the build took, when known.
  final Duration? builtIn;

  /// New files went into a studio that existed.
  final bool updated;

  @override
  State<StudioReadyMobile> createState() => _StudioReadyMobileState();
}

class _StudioReadyMobileState extends State<StudioReadyMobile>
    with SingleTickerProviderStateMixin {
  late final _draw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SmHaptics.done();
      if (smReduceMotion(context)) {
        _draw.value = 1;
      } else {
        _draw.forward();
      }
    });
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final s = widget.studio;
    final first = s.topics.firstOrNull;
    final files = s.sourceFiles.length;
    final took = widget.builtIn;
    final how = [
      if (files > 0) 'Built from $files file${files == 1 ? '' : 's'}',
      if (took != null)
        took.inSeconds < 90
            ? 'in ${math.max(1, took.inSeconds)} s'
            : 'in ${(took.inSeconds / 60).round()} min',
    ].join(' ');
    var i = 2;
    Widget appear(Widget child) => SmAppear(index: i++, child: child);
    final counts = [
      (s.topics.length, 'topics'),
      (s.flashcardCount, 'flashcards'),
      (s.quizCount, 'questions'),
      (s.scenarioCount, 'scenarios'),
    ];
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  Semantics(
                    label: 'Ready',
                    child: AnimatedBuilder(
                      animation: _draw,
                      builder: (context, _) {
                        final pop = Curves.easeOutBack.transform(
                          (_draw.value / 0.4).clamp(0.0, 1.0),
                        );
                        return Transform.scale(
                          scale: 0.6 + 0.4 * pop,
                          child: SizedBox(
                            width: 132,
                            height: 132,
                            child: CustomPaint(
                              painter: _Check(
                                ring: Curves.easeOutCubic.transform(
                                  (_draw.value / 0.7).clamp(0.0, 1.0),
                                ),
                                tick: Curves.easeOutCubic.transform(
                                  ((_draw.value - 0.55) / 0.45).clamp(0.0, 1.0),
                                ),
                                track: c.line,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 22),
                  SmAppear(
                    index: 1,
                    child: Text(
                      widget.updated
                          ? 'Your studio is updated'
                          : 'Your studio is ready',
                      textAlign: TextAlign.center,
                      style: t.greeting.copyWith(fontSize: 26),
                    ),
                  ),
                  if (how.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    appear(Text(how, style: t.small.copyWith(fontSize: 13))),
                  ],
                  const SizedBox(height: 22),
                  appear(
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 2.1,
                      children: [
                        for (final (k, (n, label)) in counts.indexed)
                          _Count(value: n, label: label, delay: k),
                      ],
                    ),
                  ),
                  if (first != null) ...[
                    const SizedBox(height: 26),
                    appear(
                      Text('FIRST UP', style: t.section.copyWith(fontSize: 11)),
                    ),
                    const SizedBox(height: 6),
                    appear(
                      Text(
                        first.title,
                        textAlign: TextAlign.center,
                        style: t.title.copyWith(fontSize: 17),
                      ),
                    ),
                    const SizedBox(height: 16),
                    appear(
                      SmPressable(
                        semanticLabel: 'Start the first lesson',
                        haptic: SmHaptics.thud,
                        onTap: () => widget.onStart(first),
                        child: Container(
                          height: 52,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c.accent,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: [
                              BoxShadow(
                                color: c.accent.withValues(alpha: 0.3),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Text(
                            'Start the first lesson',
                            style: TextStyle(
                              fontFamily: SmFonts.heading,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  appear(
                    SmPressable(
                      semanticLabel: 'Look around first',
                      haptic: SmHaptics.tap,
                      onTap: widget.onLook,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          first == null
                              ? 'Open the studio'
                              : 'Look around first',
                          style: t.body.copyWith(fontSize: 14, color: c.muted),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A number that counts up from zero, over its label.
class _Count extends StatelessWidget {
  const _Count({required this.value, required this.label, required this.delay});

  final int value;
  final String label;
  final int delay;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.toDouble()),
            duration: smReduceMotion(context)
                ? Duration.zero
                : Duration(milliseconds: 900 + delay * 150),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => Text(
              '${v.round()}',
              style: TextStyle(
                fontFamily: SmFonts.heading,
                fontSize: 24,
                height: 1.1,
                fontWeight: FontWeight.w800,
                color: c.text,
              ),
            ),
          ),
          Text(label, style: t.small.copyWith(fontSize: 12)),
        ],
      ),
    );
  }
}

class _Check extends CustomPainter {
  _Check({required this.ring, required this.tick, required this.track});

  final double ring;
  final double tick;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * ring,
      false,
      paint..color = _green,
    );
    if (tick <= 0) return;
    final w = size.width;
    final path = Path()
      ..moveTo(w * 0.32, w * 0.52)
      ..lineTo(w * 0.45, w * 0.65)
      ..lineTo(w * 0.69, w * 0.39);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * tick),
      paint..color = _green,
    );
  }

  @override
  bool shouldRepaint(_Check old) =>
      old.ring != ring || old.tick != tick || old.track != track;
}
