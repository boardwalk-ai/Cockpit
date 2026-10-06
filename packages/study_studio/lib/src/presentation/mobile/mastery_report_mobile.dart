import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/activity.dart';
import '../../domain/card_schedule.dart';
import '../../domain/entities/flashcard.dart';
import '../../domain/entities/studio.dart';
import '../../domain/entities/topic.dart';
import 'mobile_header.dart';
import 'mobile_motion.dart';
import 'mobile_style.dart';
import 'sm_calendar.dart' show smWeekdays;

/// What the next study step on a topic is.
enum ReportStep { cards, quiz, lesson }

/// One stop on "Your path": a weak topic, the day it's for, and how.
class PathStop {
  const PathStop({
    required this.topic,
    required this.day,
    required this.minutes,
    required this.step,
    required this.due,
  });

  final Topic topic;

  /// 0 = today.
  final int day;
  final int minutes;
  final ReportStep step;

  /// Cards on this topic due now.
  final int due;
}

/// A topic's memory: how much would be recalled now, when it was last
/// reviewed, and how many cards to go over.
class FadingTopic {
  const FadingTopic({
    required this.topic,
    required this.recall,
    required this.lastSeen,
    required this.toReview,
  });

  final Topic topic;
  final double recall;
  final DateTime lastSeen;
  final int toReview;

  bool get slipping => recall < 0.85;
}

/// The numbers behind the report, all from the studio as it is now.
class MasteryReport {
  MasteryReport(this.studio, this.now);

  final Studio studio;
  final DateTime now;

  static const goal = 0.8;
  static const pathLength = 3;

  double get mastery => studio.overallMastery;

  List<Topic> get learned => [
    for (final t in studio.topics)
      if (t.mastery >= goal) t,
  ]..sort((a, b) => b.mastery.compareTo(a.mastery));

  List<Topic> get weak => studio.weakTopics;

  int dueOn(Topic t) =>
      t.flashcards.where((c) => CardSchedule.isDue(c, now)).length;

  int get dueNow => studio.topics.fold(0, (n, t) => n + dueOn(t));

  /// Cards coming back on each of the next [days] days (today: everything
  /// due by the end of it, new cards included).
  List<int> upcoming([int days = 7]) {
    final today = DateTime(now.year, now.month, now.day);
    final counts = List.filled(days, 0);
    for (final t in studio.topics) {
      for (final c in t.flashcards) {
        final due = c.dueDate;
        final d = due == null || !due.isAfter(now)
            ? 0
            : DateTime(due.year, due.month, due.day).difference(today).inDays;
        if (d >= 0 && d < days) counts[d]++;
      }
    }
    return counts;
  }

  /// Below the goal, the topics that matter most and are known least first.
  List<Topic> get toFix {
    final list = [
      for (final t in studio.topics)
        if (t.mastery < goal) t,
    ];
    double weight(Topic t) => t.importance.clamp(1, 5) * (1 - t.mastery);
    return list..sort((a, b) => weight(b).compareTo(weight(a)));
  }

  /// A step a day for the most pressing topics.
  List<PathStop> get path => [
    for (final (i, t) in toFix.take(pathLength).indexed)
      PathStop(
        topic: t,
        day: i,
        minutes: _minutes(t),
        due: dueOn(t),
        step: dueOn(t) > 0
            ? ReportStep.cards
            : t.mastery >= 0.4 && t.quizQuestions.isNotEmpty
            ? ReportStep.quiz
            : ReportStep.lesson,
      ),
  ];

  /// Rough study time left to bring every topic to the goal.
  int get minutesToGoal => toFix.fold(0, (n, t) => n + _minutes(t));

  static int _minutes(Topic t) {
    final full = t.estimatedStudyTimeMinutes <= 0
        ? 10
        : t.estimatedStudyTimeMinutes;
    // The further from the goal, the more of the lesson's time it takes.
    final share = ((goal - t.mastery) / goal).clamp(0.3, 1.0);
    return (full * share / 5).ceil() * 5;
  }

  /// How likely a reviewed card is recalled now: 90% on its due day,
  /// fading the same way after it. Null for a card never reviewed.
  static double? recall(Flashcard c, DateTime now) {
    final due = c.dueDate;
    if (c.reps == 0 || due == null) return null;
    final interval = math.max(c.intervalDays, 0.5);
    final last = due.subtract(
      Duration(minutes: (c.intervalDays * Duration.minutesPerDay).round()),
    );
    final days =
        math.max(0, now.difference(last).inMinutes) / Duration.minutesPerDay;
    return math.pow(0.9, days / interval).toDouble();
  }

  /// Topics with reviewed cards, the most forgotten first.
  List<FadingTopic> get fading {
    final out = <FadingTopic>[];
    for (final t in studio.topics) {
      final seen = [
        for (final c in t.flashcards)
          if (recall(c, now) case final r?) (c, r),
      ];
      if (seen.isEmpty) continue;
      final avg = seen.fold(0.0, (n, e) => n + e.$2) / seen.length;
      final last = seen
          .map(
            (e) => e.$1.dueDate!.subtract(
              Duration(
                minutes: (e.$1.intervalDays * Duration.minutesPerDay).round(),
              ),
            ),
          )
          .reduce((a, b) => a.isAfter(b) ? a : b);
      final due = dueOn(t);
      out.add(
        FadingTopic(
          topic: t,
          recall: avg,
          lastSeen: last,
          toReview: due > 0 ? due : seen.length,
        ),
      );
    }
    return out..sort((a, b) => a.recall.compareTo(b.recall));
  }

  /// "Ready", "Getting there", "Building".
  String get readiness => mastery >= goal
      ? 'Exam ready'
      : mastery >= 0.6
      ? 'Getting there'
      : 'Building up';
}

/// The phone's Mastery report: a ring with where you stand, your path to
/// 80% (a step a day), the cards coming up this week, what's strong, and
/// every topic. One button starts today's step.
class MasteryReportMobile extends StatelessWidget {
  const MasteryReportMobile({
    super.key,
    required this.studio,
    required this.onBack,
    required this.onTopic,
    required this.onStep,
    required this.onCards,
    this.onPlan,
    this.onReview,
    this.activity,
    this.studyDays,
    this.now,
  });

  final Studio studio;
  final VoidCallback onBack;
  final void Function(Topic topic) onTopic;
  final void Function(PathStop stop) onStep;

  /// All due cards (no topic) when there's no path left.
  final VoidCallback onCards;

  /// Opens the study plan (from "Your path").
  final VoidCallback? onPlan;

  /// Reviews a fading topic's cards.
  final void Function(Topic topic)? onReview;

  /// The last two weeks (null while loading).
  final List<DayActivity>? activity;

  /// The study plan's weekdays, if there is a plan (others show as rest).
  final Set<int>? studyDays;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final report = MasteryReport(studio, now ?? DateTime.now());
    final top = MediaQuery.paddingOf(context).top + SmHeader.clearance;
    final path = report.path;
    final due = report.dueNow;
    var i = 0;
    Widget appear(Widget child) => SmAppear(index: i++, child: child);
    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 12),
      child: Text(title, style: t.section.copyWith(fontSize: 11)),
    );

    final String? cta;
    VoidCallback? go;
    if (path.isNotEmpty) {
      cta = 'Start today’s step';
      go = () => onStep(path.first);
    } else if (due > 0) {
      cta = 'Review $due card${due == 1 ? '' : 's'}';
      go = onCards;
    } else {
      cta = null;
    }

    return Scaffold(
      backgroundColor: c.background,
      body: SmHeaderPage(
        header: SmHeader(title: 'Mastery', onBack: onBack),
        child: Stack(
          children: [
            Positioned.fill(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(22, top + 6, 22, 120),
                children: [
                  appear(_Hero(report: report)),
                  if (studio.topics.isNotEmpty) ...[
                    appear(
                      Row(
                        children: [
                          Expanded(child: section('YOUR PATH TO 80%')),
                          if (onPlan != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: SmPressable(
                                semanticLabel: 'Full plan',
                                onTap: onPlan,
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Text(
                                    'Full plan ›',
                                    style: t.small.copyWith(
                                      fontSize: 12.5,
                                      color: c.accentSoft,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    appear(
                      path.isEmpty
                          ? _AllClear(onCards: due > 0 ? onCards : null)
                          : _Path(
                              stops: path,
                              left: report.minutesToGoal,
                              more: report.toFix.length - path.length,
                              now: report.now,
                              onStep: onStep,
                            ),
                    ),
                  ],
                  appear(section('THIS WEEK')),
                  appear(
                    _ThisWeek(
                      week: activity == null
                          ? null
                          : WeekActivity(activity!, report.now),
                      today: report.now,
                      studyDays: studyDays,
                    ),
                  ),
                  if (report.fading.isNotEmpty) ...[
                    appear(section('FADING')),
                    appear(
                      _Fading(
                        topics: report.fading.take(3).toList(),
                        now: report.now,
                        onReview: onReview ?? onTopic,
                      ),
                    ),
                  ],
                  if (studio.flashcardCount > 0) ...[
                    appear(section('CARDS COMING UP')),
                    appear(
                      _Upcoming(counts: report.upcoming(), now: report.now),
                    ),
                  ],
                  if (report.learned.isNotEmpty) ...[
                    appear(section('STRONGEST')),
                    appear(
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final s in report.learned.take(6))
                            _Strong(topic: s, onTap: () => onTopic(s)),
                          if (report.learned.length > 6)
                            _Pill(
                              child: Text(
                                '+${report.learned.length - 6} more',
                                style: t.small.copyWith(fontSize: 12.5),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (studio.topics.isNotEmpty) ...[
                    appear(section('ALL TOPICS')),
                    appear(_AllTopics(topics: studio.topics, onTap: onTopic)),
                  ],
                ],
              ),
            ),
            if (cta != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _Cta(label: cta, onTap: go!),
              ),
          ],
        ),
      ),
    );
  }
}

const _green = Color(0xFF30A46C);

Color _tone(SmColors c, double m) => m >= MasteryReport.goal
    ? _green
    : m >= 0.6
    ? c.gold
    : c.accent;

/// The ring, the readiness pill, and three counts.
class _Hero extends StatelessWidget {
  const _Hero({required this.report});

  final MasteryReport report;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final m = report.mastery;
    final tone = _tone(c, m);
    final due = report.dueNow;
    Widget count(String text) =>
        _Pill(child: Text(text, style: t.body.copyWith(fontSize: 12.5)));
    return Column(
      children: [
        const SizedBox(height: 8),
        Semantics(
          label: '${(m * 100).round()} percent mastered',
          child: ExcludeSemantics(
            child: SmRing(
              value: m,
              size: 156,
              stroke: 11,
              labelSize: 34,
              caption: 'mastery',
            ),
          ),
        ),
        const SizedBox(height: 14),
        _Pill(
          color: tone,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.track_changes_rounded, size: 15, color: tone),
              const SizedBox(width: 6),
              Text(
                report.readiness,
                style: t.body.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: tone,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            count('${report.learned.length} learned'),
            count('$due card${due == 1 ? '' : 's'} due'),
            count('${report.weak.length} weak'),
          ],
        ),
      ],
    );
  }
}

/// An outline pill.
class _Pill extends StatelessWidget {
  const _Pill({required this.child, this.color});

  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color?.withValues(alpha: 0.7) ?? c.line),
      ),
      child: child,
    );
  }
}

String _dayName(int day, DateTime now) {
  if (day == 0) return 'Today';
  if (day == 1) return 'Tomorrow';
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return names[now.add(Duration(days: day)).weekday - 1];
}

/// A step a day, on a dashed line, ending at the goal.
class _Path extends StatelessWidget {
  const _Path({
    required this.stops,
    required this.left,
    required this.more,
    required this.now,
    required this.onStep,
  });

  final List<PathStop> stops;
  final int left;
  final int more;
  final DateTime now;
  final void Function(PathStop stop) onStep;

  @override
  Widget build(BuildContext context) {
    final t = SmText.of(context);
    String how(PathStop s) => switch (s.step) {
      ReportStep.cards => '${s.due} card${s.due == 1 ? '' : 's'} to review',
      ReportStep.quiz => 'Quiz',
      ReportStep.lesson => 'Lesson',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '~$left min of study to go'
          '${more > 0 ? ' · $more more topic${more == 1 ? '' : 's'} after these' : ''}',
          style: t.small.copyWith(fontSize: 12.5),
        ),
        const SizedBox(height: 12),
        for (final (i, s) in stops.indexed)
          _Stop(
            first: i == 0,
            title: '${_dayName(s.day, now)} · ${s.minutes} min',
            topic: s.topic,
            how: how(s),
            onTap: () => onStep(s),
          ),
        Row(
          children: [
            SizedBox(
              width: 22,
              child: Center(
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _green, width: 2),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '80% reached',
              style: t.body.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _green,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Stop extends StatelessWidget {
  const _Stop({
    required this.first,
    required this.title,
    required this.topic,
    required this.how,
    required this.onTap,
  });

  final bool first;
  final String title;
  final Topic topic;
  final String how;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final pct = (topic.mastery * 100).round();
    return SmPressable(
      semanticLabel: '$title, ${topic.title}, $how',
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 22,
              child: Column(
                children: [
                  const SizedBox(height: 3),
                  Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: first ? c.accent : c.background,
                      border: Border.all(
                        color: first ? c.accent : c.hint,
                        width: 2,
                      ),
                    ),
                  ),
                  Expanded(child: CustomPaint(painter: _Dashes(c.line))),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: t.small.copyWith(
                        fontSize: 11.5,
                        color: first ? c.accentSoft : c.hint,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            topic.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.title.copyWith(fontSize: 14.5),
                          ),
                        ),
                        Text(
                          '$pct%',
                          style: t.small.copyWith(
                            fontSize: 12,
                            color: _tone(c, topic.mastery),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _Bar(value: topic.mastery),
                    const SizedBox(height: 6),
                    Text(how, style: t.small.copyWith(fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 20, color: c.hint),
          ],
        ),
      ),
    );
  }
}

class _Dashes extends CustomPainter {
  _Dashes(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    final x = size.width / 2;
    for (var y = 4.0; y < size.height - 2; y += 7) {
      canvas.drawLine(Offset(x, y), Offset(x, y + 3.5), p);
    }
  }

  @override
  bool shouldRepaint(_Dashes old) => old.color != color;
}

/// A thin mastery bar that fills when it shows.
class _Bar extends StatelessWidget {
  const _Bar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
      duration: smReduceMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          height: 4,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: c.line)),
              FractionallySizedBox(
                widthFactor: v,
                heightFactor: 1,
                child: ColoredBox(color: _tone(c, value)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AllClear extends StatelessWidget {
  const _AllClear({this.onCards});

  final VoidCallback? onCards;

  @override
  Widget build(BuildContext context) {
    final t = SmText.of(context);
    return Row(
      children: [
        const Icon(Icons.verified_rounded, color: _green, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            onCards == null
                ? 'Every topic is at 80% or more.'
                : 'Every topic is at 80% or more. Review your cards to keep '
                      'it there.',
            style: t.body.copyWith(fontSize: 13.5),
          ),
        ),
      ],
    );
  }
}

/// Seven bars: cards coming back each day. Tap one for its count.
class _Upcoming extends StatefulWidget {
  const _Upcoming({required this.counts, required this.now});

  final List<int> counts;
  final DateTime now;

  @override
  State<_Upcoming> createState() => _UpcomingState();
}

class _UpcomingState extends State<_Upcoming> {
  var _picked = 0;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final counts = widget.counts;
    final most = counts.fold<int>(1, (m, n) => n > m ? n : m);
    final n = counts[_picked];
    final day = _dayName(_picked, widget.now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.centerLeft,
            children: [...previous, ?current],
          ),
          child: Text(
            n == 0 ? '$day: nothing due' : '$day: $n card${n == 1 ? '' : 's'}',
            key: ValueKey(_picked),
            style: t.small.copyWith(fontSize: 12.5, color: c.text),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 92,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var d = 0; d < counts.length; d++)
                Expanded(
                  child: SmPressable(
                    semanticLabel:
                        '${_dayName(d, widget.now)}, ${counts[d]} cards',
                    scale: 0.92,
                    onTap: () => setState(() => _picked = d),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: counts[d] / most),
                            duration: smReduceMotion(context)
                                ? Duration.zero
                                : Duration(milliseconds: 600 + d * 60),
                            curve: Curves.easeOutCubic,
                            builder: (context, v, _) => AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              height: 4 + 60 * v,
                              decoration: BoxDecoration(
                                color: d == _picked ? c.accent : c.line,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          FittedBox(
                            child: Text(
                              d == 0
                                  ? 'Today'
                                  : d == 1
                                  ? 'Tmrw'
                                  : _dayName(d, widget.now),
                              style: t.small.copyWith(
                                fontSize: 11,
                                color: d == _picked ? c.text : c.hint,
                              ),
                            ),
                          ),
                        ],
                      ),
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

class _Strong extends StatelessWidget {
  const _Strong({required this.topic, required this.onTap});

  final Topic topic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = SmText.of(context);
    return SmPressable(
      semanticLabel: topic.title,
      onTap: onTap,
      child: _Pill(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_rounded, size: 14, color: _green),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Text(
                topic.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.body.copyWith(fontSize: 12.5),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${(topic.mastery * 100).round()}%',
              style: t.small.copyWith(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every topic, weakest first, with its bar.
class _AllTopics extends StatelessWidget {
  const _AllTopics({required this.topics, required this.onTap});

  final List<Topic> topics;
  final void Function(Topic topic) onTap;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final sorted = [...topics]..sort((a, b) => a.mastery.compareTo(b.mastery));
    return Column(
      children: [
        for (final topic in sorted)
          SmPressable(
            semanticLabel: topic.title,
            onTap: () => onTap(topic),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          topic.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.body.copyWith(fontSize: 13.5),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(topic.mastery * 100).round()}%',
                        style: t.small.copyWith(fontSize: 12, color: c.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _Bar(value: topic.mastery),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Cta extends StatelessWidget {
  const _Cta({required this.label, required this.onTap});

  final String label;
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
        semanticLabel: label,
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 21,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
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

/// Monday to Sunday: a filled dot on each day studied (with how much),
/// a ring on today, dashes on the plan's days off. Tap a day for it.
class _ThisWeek extends StatefulWidget {
  const _ThisWeek({
    required this.week,
    required this.today,
    required this.studyDays,
  });

  final WeekActivity? week;
  final DateTime today;
  final Set<int>? studyDays;

  @override
  State<_ThisWeek> createState() => _ThisWeekState();
}

class _ThisWeekState extends State<_ThisWeek> {
  int? _picked;

  String _caption(WeekActivity w) {
    final p = _picked;
    if (p != null) {
      final d = w.week[p];
      final name = smWeekdays[d.date.weekday - 1];
      if (d.date.isAfter(w.today)) return '$name: still ahead';
      if (!d.active) return '$name: nothing studied';
      final parts = [
        if (d.cards > 0) '${d.cards} card${d.cards == 1 ? '' : 's'}',
        if (d.quiz > 0) '${d.quizRight} of ${d.quiz} quiz right',
      ];
      return '$name: ${parts.join(' · ')}';
    }
    if (w.total == 0) return 'Nothing yet this week. Today’s a good start.';
    final diff = w.total - w.lastTotal;
    if (w.lastTotal == 0) return 'Your first reviews since last week.';
    if (diff == 0) return 'The same as this time last week.';
    return diff > 0
        ? '$diff more than this time last week'
        : '${-diff} fewer than this time last week';
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final w = widget.week;
    final todayIndex = widget.today.weekday - 1;
    Widget pill(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: c.line),
      ),
      child: Text(text, style: t.body.copyWith(fontSize: 12.5)),
    );
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: _DayDot(
                  index: i,
                  day: w?.week[i],
                  today: i == todayIndex,
                  future: i > todayIndex,
                  rest:
                      widget.studyDays != null &&
                      !widget.studyDays!.contains(i + 1),
                  picked: _picked == i,
                  most: w == null
                      ? 1
                      : w.week.fold<int>(1, (m, d) => math.max(m, d.total)),
                  onTap: w == null
                      ? null
                      : () => setState(() => _picked = _picked == i ? null : i),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (w != null) ...[
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              pill('${w.cards} card${w.cards == 1 ? '' : 's'}'),
              if (w.accuracy != null)
                pill('${(w.accuracy! * 100).round()}% quiz right'),
              pill('${w.activeDays} day${w.activeDays == 1 ? '' : 's'}'),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Text(
              _caption(w),
              key: ValueKey(_picked),
              textAlign: TextAlign.center,
              style: t.small.copyWith(
                fontSize: 12.5,
                color: _picked == null ? c.muted : c.text,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({
    required this.index,
    required this.day,
    required this.today,
    required this.future,
    required this.rest,
    required this.picked,
    required this.most,
    required this.onTap,
  });

  final int index;
  final DayActivity? day;
  final bool today;
  final bool future;
  final bool rest;
  final bool picked;
  final int most;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final d = day;
    final on = d != null && d.active;
    final name = smWeekdays[index];
    return SmPressable(
      semanticLabel: d == null
          ? name
          : '$name, ${d.total} reviewed${today ? ', today' : ''}',
      scale: 0.9,
      onTap: onTap,
      child: Column(
        children: [
          Text(
            name.substring(0, 1),
            style: t.small.copyWith(
              fontSize: 11,
              fontWeight: today ? FontWeight.w800 : FontWeight.w600,
              color: today ? c.accentSoft : c.hint,
            ),
          ),
          const SizedBox(height: 6),
          // An outer ring for today (accent) or the picked day.
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: today
                    ? c.accentSoft
                    : picked
                    ? c.text.withValues(alpha: 0.5)
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            // Fills in, one day after another.
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: on ? 1 : 0),
              duration: smReduceMotion(context)
                  ? Duration.zero
                  : Duration(milliseconds: 380 + index * 70),
              curve: Curves.easeOutBack,
              builder: (context, v, _) => AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.lerp(
                    Colors.transparent,
                    c.accent,
                    v.clamp(0.0, 1.0),
                  ),
                  border: on
                      ? null
                      : Border.all(
                          color: future || rest
                              ? c.line.withValues(alpha: 0.6)
                              : c.line,
                          width: 1.5,
                        ),
                ),
                alignment: Alignment.center,
                child: on
                    ? Transform.scale(
                        scale: v.clamp(0.0, 1.2),
                        child: FittedBox(
                          child: Padding(
                            padding: const EdgeInsets.all(5),
                            child: Text(
                              '${d.total}',
                              style: const TextStyle(
                                fontFamily: SmFonts.heading,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      )
                    : rest && !future && !today
                    ? Icon(Icons.remove_rounded, size: 14, color: c.line)
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Learned topics slipping away: a five-step memory bar, when they were
/// last seen, and a Review pill.
class _Fading extends StatelessWidget {
  const _Fading({
    required this.topics,
    required this.now,
    required this.onReview,
  });

  final List<FadingTopic> topics;
  final DateTime now;
  final void Function(Topic topic) onReview;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final anySlipping = topics.any((f) => f.slipping);
    String seen(DateTime d) {
      final days = now.difference(d).inHours ~/ 24;
      return switch (days) {
        <= 0 => 'reviewed today',
        1 => 'last seen yesterday',
        _ => 'last seen $days days ago',
      };
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          anySlipping
              ? 'Learned, but slipping away'
              : 'Everything’s holding. Nice.',
          style: t.small.copyWith(fontSize: 12.5),
        ),
        const SizedBox(height: 8),
        for (final f in topics)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.topic.title,
                        style: t.title.copyWith(fontSize: 14),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _Memory(value: f.recall, slipping: f.slipping),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              f.slipping ? seen(f.lastSeen) : 'holding well',
                              style: t.small.copyWith(fontSize: 11.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SmPressable(
                  semanticLabel: 'Review ${f.topic.title}',
                  haptic: SmHaptics.thud,
                  onTap: () => onReview(f.topic),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: f.slipping ? c.accent : c.line),
                    ),
                    child: Text(
                      'Review ${f.toReview}',
                      style: t.body.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: f.slipping ? c.accentSoft : c.text,
                      ),
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

/// Five little bars, filled to how much is still remembered.
class _Memory extends StatelessWidget {
  const _Memory({required this.value, required this.slipping});

  final double value;
  final bool slipping;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final filled = (value * 5).round().clamp(0, 5);
    final color = slipping ? c.gold : _green;
    return Semantics(
      label: '${(value * 100).round()} percent remembered',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 5; i++)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: i < filled ? 1 : 0),
              duration: smReduceMotion(context)
                  ? Duration.zero
                  : Duration(milliseconds: 300 + i * 90),
              builder: (context, v, _) => Container(
                width: 11,
                height: 4,
                margin: const EdgeInsets.only(right: 2),
                decoration: BoxDecoration(
                  color: Color.lerp(c.line, color, v),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
