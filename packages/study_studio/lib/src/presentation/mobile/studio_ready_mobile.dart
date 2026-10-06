import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/entities/studio.dart';
import '../../domain/entities/topic.dart';
import 'mobile_motion.dart';
import 'mobile_style.dart';
import 'sm_calendar.dart' show smMonths;

/// The moment a studio is built: a stamp lands (with a thud) — READY, the
/// studio's name and the date going round it — then what was made counts
/// up, and the first lesson is one tap away.
class StudioReadyMobile extends StatefulWidget {
  const StudioReadyMobile({
    super.key,
    required this.studio,
    required this.onStart,
    required this.onLook,
    this.builtIn,
    this.updated = false,
    this.now,
  });

  final Studio studio;
  final void Function(Topic topic) onStart;
  final VoidCallback onLook;

  /// How long the build took, when known.
  final Duration? builtIn;

  /// New files went into a studio that existed.
  final bool updated;
  final DateTime? now;

  @override
  State<StudioReadyMobile> createState() => _StudioReadyMobileState();
}

class _StudioReadyMobileState extends State<StudioReadyMobile>
    with TickerProviderStateMixin {
  /// The stamp coming down.
  late final _land = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  /// The words going round it.
  late final _turn = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );
  var _thudded = false;

  @override
  void initState() {
    super.initState();
    _land.addListener(() {
      // The thud as it meets the page.
      if (!_thudded && _land.value >= 0.55) {
        _thudded = true;
        SmHaptics.thud();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (smReduceMotion(context)) {
        _land.value = 1;
        _thudded = true;
        SmHaptics.done();
        return;
      }
      Future<void>.delayed(const Duration(milliseconds: 180), () {
        if (!mounted) return;
        _land.forward();
        _turn.repeat();
      });
    });
  }

  @override
  void dispose() {
    _land.dispose();
    _turn.dispose();
    super.dispose();
  }

  String get _ring {
    final d = widget.now ?? DateTime.now();
    var name = widget.studio.title.toUpperCase().trim();
    if (name.length > 22) name = '${name.substring(0, 21)}…';
    final date =
        '${smMonths[d.month - 1].substring(0, 3).toUpperCase()} ${d.day}';
    return '${widget.updated ? 'UPDATED' : 'READY'} · $name · $date · ';
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
      if (files > 0) '$files file${files == 1 ? '' : 's'}',
      if (took != null)
        took.inSeconds < 60
            ? 'built in ${math.max(1, took.inSeconds)} s'
            : 'built in ${took.inMinutes} min ${took.inSeconds % 60} s',
    ].join(' · ');
    var i = 3;
    Widget appear(Widget child) => SmAppear(index: i++, child: child);
    final counts = [
      (s.topics.length, 'TOPICS'),
      (s.flashcardCount, 'CARDS'),
      (s.quizCount, 'QUESTIONS'),
      (s.scenarioCount, 'CASES'),
    ];

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  Semantics(
                    label: widget.updated ? 'Updated' : 'Ready',
                    child: ExcludeSemantics(
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_land, _turn]),
                        builder: (context, _) => _Stamp(
                          land: _land.value,
                          turn: _turn.value,
                          ring: _ring,
                          count: s.topics.length,
                          ink: c.accent,
                          text: c.accentSoft,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  SmAppear(
                    index: 2,
                    child: Text(
                      widget.updated
                          ? 'Your studio\nis updated'
                          : 'Your studio\nis ready',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: SmFonts.heading,
                        fontSize: 30,
                        height: 1.05,
                        letterSpacing: -1,
                        fontWeight: FontWeight.w800,
                        color: c.text,
                      ),
                    ),
                  ),
                  if (how.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    appear(Text(how, style: t.small.copyWith(fontSize: 12.5))),
                  ],
                  const SizedBox(height: 26),
                  appear(
                    IntrinsicHeight(
                      child: Row(
                        children: [
                          for (final (k, (n, label)) in counts.indexed) ...[
                            if (k > 0) Container(width: 1, color: c.line),
                            Expanded(
                              child: _Count(value: n, label: label, delay: k),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (first != null) ...[
                    const SizedBox(height: 28),
                    appear(
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'FIRST UP',
                          style: t.section.copyWith(fontSize: 10.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    appear(
                      _FirstUp(
                        topic: first,
                        onTap: () => widget.onStart(first),
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
                                color: c.accent.withValues(alpha: 0.32),
                                blurRadius: 22,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Text(
                            'Start the first lesson',
                            style: TextStyle(
                              fontFamily: SmFonts.heading,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
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
                          style: TextStyle(
                            fontFamily: SmFonts.heading,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: c.muted,
                          ),
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

/// The stamp: two inked rings, the words round them, the count inside.
/// [land] 0→1 brings it down from above, a little turned, with a splash.
class _Stamp extends StatelessWidget {
  const _Stamp({
    required this.land,
    required this.turn,
    required this.ring,
    required this.count,
    required this.ink,
    required this.text,
  });

  final double land;
  final double turn;
  final String ring;
  final int count;
  final Color ink;
  final Color text;

  static const size = 156.0;

  @override
  Widget build(BuildContext context) {
    // Down fast, a small squash on contact, settle.
    final double scale;
    if (land < 0.55) {
      scale = 1.9 - 0.96 * Curves.easeIn.transform(land / 0.55);
    } else {
      scale = 0.94 + 0.06 * Curves.easeOut.transform((land - 0.55) / 0.45);
    }
    final angle = (-18 + 10 * Curves.easeOut.transform(land)) * math.pi / 180;
    final splash = land < 0.55
        ? 0.0
        : math.sin(((land - 0.55) / 0.45) * math.pi).clamp(0.0, 1.0);
    return Opacity(
      opacity: (land * 2.2).clamp(0.0, 1.0),
      child: Transform.rotate(
        angle: angle,
        child: Transform.scale(
          scale: scale,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // The ink spreading as it lands.
                Container(
                  width: size + 30 * splash,
                  height: size + 30 * splash,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ink.withValues(alpha: 0.10 * splash + 0.05 * land),
                  ),
                ),
                CustomPaint(
                  size: const Size(size, size),
                  painter: _StampPainter(ring: ring, turn: turn, ink: ink),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$count',
                      style: TextStyle(
                        fontFamily: SmFonts.heading,
                        fontSize: 34,
                        height: 1,
                        letterSpacing: -1.2,
                        fontWeight: FontWeight.w800,
                        color: text,
                      ),
                    ),
                    Text(
                      count == 1 ? 'LESSON' : 'LESSONS',
                      style: TextStyle(
                        fontFamily: SmFonts.heading,
                        fontSize: 8.5,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w800,
                        color: text,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StampPainter extends CustomPainter {
  _StampPainter({required this.ring, required this.turn, required this.ink});

  final String ring;
  final double turn;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..color = ink;
    canvas.drawCircle(center, r - 2, line..strokeWidth = 3);
    canvas.drawCircle(center, r - 26, line..strokeWidth = 1.5);

    // The words, one letter at a time round the band between the rings.
    final textR = r - 14;
    final style = TextStyle(
      fontFamily: SmFonts.heading,
      fontSize: 9.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 0,
      color: ink,
    );
    final chars = ring.characters.toList();
    final step = 2 * math.pi / chars.length;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(turn * 2 * math.pi);
    for (final ch in chars) {
      final tp = TextPainter(
        text: TextSpan(text: ch, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(0, -textR);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
      canvas.rotate(step);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StampPainter old) =>
      old.turn != turn || old.ring != ring || old.ink != ink;
}

/// A number that counts up from zero, over a small-caps label.
class _Count extends StatelessWidget {
  const _Count({required this.value, required this.label, required this.delay});

  final int value;
  final String label;
  final int delay;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.toDouble()),
          duration: smReduceMotion(context)
              ? Duration.zero
              : Duration(milliseconds: 1000 + delay * 160),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => Text(
            '${v.round()}',
            style: TextStyle(
              fontFamily: SmFonts.heading,
              fontSize: 26,
              height: 1.1,
              letterSpacing: -0.8,
              fontWeight: FontWeight.w800,
              color: c.text,
            ),
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(child: Text(label, style: t.section.copyWith(fontSize: 8.5))),
      ],
    );
  }
}

/// The first lesson as a row: its number in a ring, title, length and
/// importance.
class _FirstUp extends StatelessWidget {
  const _FirstUp({required this.topic, required this.onTap});

  final Topic topic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final stars = topic.importance.clamp(1, 5);
    return SmPressable(
      semanticLabel: 'First lesson: ${topic.title}',
      haptic: SmHaptics.thud,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border.symmetric(horizontal: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: c.line, width: 3),
              ),
              child: Text(
                '01',
                style: TextStyle(
                  fontFamily: SmFonts.heading,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: c.muted,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(topic.title, style: t.title.copyWith(fontSize: 15)),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${topic.estimatedStudyTimeMinutes} min  ',
                        ),
                        TextSpan(
                          text: '★' * stars,
                          style: const TextStyle(color: Color(0xFFF5C04A)),
                        ),
                      ],
                    ),
                    style: t.small.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.hint),
          ],
        ),
      ),
    );
  }
}
