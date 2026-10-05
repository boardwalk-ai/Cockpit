import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/entities/topic.dart';
import 'mobile_header.dart';
import 'mobile_motion.dart';
import 'mobile_style.dart';

/// A topic before its lesson: how well it is known (a ring), how much it
/// matters and how hard it is, three key points, what it builds on, where
/// it came from, and the ways to study it. Start lesson waits at the foot.
class TopicOverviewMobile extends StatelessWidget {
  const TopicOverviewMobile({
    super.key,
    required this.topic,
    required this.number,
    required this.total,
    required this.onBack,
    required this.onStart,
    required this.onQuiz,
    required this.onFlashcards,
    this.onOpenTopic,
    this.earlier = const {},
  });

  final Topic topic;
  final int number;
  final int total;
  final VoidCallback onBack;
  final VoidCallback onStart;
  final VoidCallback onQuiz;
  final VoidCallback onFlashcards;

  /// Earlier topics by title, so "Before this" can open them.
  final Map<String, Topic> earlier;
  final void Function(Topic topic)? onOpenTopic;

  /// The key points: the summary, or, on older studios, the definition.
  List<String> get points {
    final summary = topic.summary.where((p) => p.trim().isNotEmpty).toList();
    if (summary.isNotEmpty) return summary.take(4).toList();
    final d = topic.definition.trim();
    return d.isEmpty ? const [] : [d];
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final top = MediaQuery.paddingOf(context).top + SmHeader.clearance;
    var i = 0;
    Widget appear(Widget child) => SmAppear(index: i++, child: child);
    final seen = <String>{};
    final sources = [
      for (final s in topic.sources)
        if (seen.add('${s.fileName}#${s.page}')) s,
    ];

    return Scaffold(
      backgroundColor: c.background,
      body: SmHeaderPage(
        header: SmHeader(title: 'Topic $number of $total', onBack: onBack),
        child: Stack(
          children: [
            Positioned.fill(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(22, top + 8, 22, 110),
                children: [
                  appear(_Head(topic: topic)),
                  const SizedBox(height: 18),
                  appear(_Stats(topic: topic)),
                  if (points.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    appear(_Summary(points: points)),
                  ],
                  const SizedBox(height: 14),
                  appear(
                    Column(
                      children: [
                        _Action(
                          icon: Icons.help_rounded,
                          color: const Color(0xFF378ADD),
                          label: 'Quiz me on this',
                          count: topic.quizQuestions.length,
                          onTap: onQuiz,
                        ),
                        _Action(
                          icon: Icons.style_rounded,
                          color: const Color(0xFFF0997B),
                          label: 'Flashcards',
                          count: topic.flashcards.length,
                          onTap: onFlashcards,
                        ),
                      ],
                    ),
                  ),
                  if (topic.prerequisites.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    appear(
                      _ChipGroup(
                        title: 'BEFORE THIS',
                        chips: [
                          for (final name in topic.prerequisites)
                            _Chip(
                              icon: Icons.undo_rounded,
                              label: name,
                              onTap:
                                  earlier[name] == null || onOpenTopic == null
                                  ? null
                                  : () => onOpenTopic!(earlier[name]!),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (sources.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    appear(
                      _ChipGroup(
                        title: 'FROM YOUR NOTES',
                        chips: [
                          for (final s in sources)
                            _Chip(
                              icon: Icons.description_outlined,
                              label: s.page == null
                                  ? s.fileName
                                  : '${s.fileName} · p.${s.page}',
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (points.isEmpty && topic.prerequisites.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Text(
                        'The lesson has the whole story.',
                        textAlign: TextAlign.center,
                        style: t.small.copyWith(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _Start(onTap: onStart),
            ),
          ],
        ),
      ),
    );
  }
}

/// The mastery ring and the title.
class _Head extends StatelessWidget {
  const _Head({required this.topic});

  final Topic topic;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final pct = (topic.mastery * 100).round();
    return Row(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(end: topic.mastery.clamp(0, 1)),
          duration: smReduceMotion(context)
              ? Duration.zero
              : const Duration(milliseconds: 1000),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => SizedBox(
            width: 78,
            height: 78,
            child: CustomPaint(
              painter: _Ring(
                value: v,
                track: c.line,
                color: v >= 0.8 ? const Color(0xFF30A46C) : c.accent,
              ),
              child: Center(
                child: Semantics(
                  label: '$pct percent mastered',
                  child: Text(
                    '$pct%',
                    style: TextStyle(
                      fontFamily: SmFonts.heading,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: c.text,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            topic.title,
            style: TextStyle(
              fontFamily: SmFonts.heading,
              fontSize: 23,
              height: 1.15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: c.text,
            ),
          ),
        ),
      ],
    );
  }
}

class _Ring extends CustomPainter {
  _Ring({required this.value, required this.track, required this.color});

  final double value;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 6.5;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (value > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * value,
        false,
        paint..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_Ring old) =>
      old.value != value || old.color != color || old.track != track;
}

/// Importance (stars), difficulty (a five-step bar), the lesson's length.
class _Stats extends StatelessWidget {
  const _Stats({required this.topic});

  final Topic topic;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final level = topic.difficulty.clamp(1, 5);
    final stars = topic.importance.clamp(1, 5);
    const gold = Color(0xFFF5C04A);
    const amber = Color(0xFFF5A623);
    Widget cell(Widget top, String label) => Expanded(
      child: Column(
        children: [
          SizedBox(height: 20, child: Center(child: top)),
          const SizedBox(height: 4),
          Text(label, style: t.small.copyWith(fontSize: 11.5)),
        ],
      ),
    );
    Widget rule() => Container(width: 1, height: 34, color: c.line);
    return Semantics(
      label:
          'Importance $stars of 5, '
          'difficulty $level of 5, '
          '${topic.estimatedStudyTimeMinutes} minute lesson',
      child: ExcludeSemantics(
        child: Row(
          children: [
            cell(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var s = 1; s <= 5; s++)
                    Icon(
                      s <= stars
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 15,
                      color: s <= stars ? gold : c.line,
                    ),
                ],
              ),
              'Importance',
            ),
            rule(),
            cell(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var s = 1; s <= 5; s++)
                    Container(
                      width: 13,
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(
                        color: s <= level ? amber : c.line,
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                ],
              ),
              switch (level) {
                <= 2 => 'Easy',
                3 => 'Medium',
                _ => 'Hard',
              },
            ),
            rule(),
            cell(
              Text(
                '${topic.estimatedStudyTimeMinutes} min',
                style: TextStyle(
                  fontFamily: SmFonts.heading,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: c.text,
                ),
              ),
              'Lesson',
            ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.points});

  final List<String> points;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SUMMARY', style: t.section.copyWith(fontSize: 11)),
        const SizedBox(height: 10),
        for (final p in points)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(top: 10, right: 12),
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text(
                    p.trim(),
                    style: TextStyle(
                      fontFamily: SmFonts.reading,
                      fontSize: 16,
                      height: 1.55,
                      color: c.text.withValues(alpha: 0.92),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.color,
    required this.label,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return SmPressable(
      semanticLabel: label,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: t.body.copyWith(fontSize: 14))),
            if (count > 0)
              Text('$count', style: t.small.copyWith(fontSize: 12)),
            Icon(Icons.chevron_right_rounded, size: 20, color: c.hint),
          ],
        ),
      ),
    );
  }
}

class _ChipGroup extends StatelessWidget {
  const _ChipGroup({required this.title, required this.chips});

  final String title;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: SmText.of(context).section.copyWith(fontSize: 11)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: chips),
    ],
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c.muted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.small.copyWith(fontSize: 12.5, color: c.text),
            ),
          ),
        ],
      ),
    );
    return onTap == null
        ? chip
        : SmPressable(semanticLabel: label, onTap: onTap, child: chip);
  }
}

class _Start extends StatelessWidget {
  const _Start({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        28,
        16,
        14 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.45],
          colors: [c.background.withValues(alpha: 0), c.background],
        ),
      ),
      child: SmPressable(
        semanticLabel: 'Start lesson',
        haptic: SmHaptics.thud,
        onTap: onTap,
        child: Container(
          height: 50,
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
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.menu_book_rounded, color: Colors.white, size: 19),
              SizedBox(width: 8),
              Text(
                'Start lesson',
                style: TextStyle(
                  fontFamily: SmFonts.heading,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
