import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/card_schedule.dart';
import '../../domain/entities/studio.dart';
import '../../domain/entities/topic.dart';
import '../../domain/study_plan.dart';
import 'mobile_header.dart';
import 'mobile_motion.dart';
import 'mobile_style.dart';
import 'sm_calendar.dart';

const _green = Color(0xFF30A46C);

/// The phone's study plan: for an exam or at your own pace, so many
/// minutes on chosen days. Today is a checklist (lesson, cards, quiz) with
/// a ring of minutes done; below, the days coming up to the exam or to
/// every topic at 80%. Kept on the phone, per studio.
class StudyPlanMobile extends StatefulWidget {
  const StudyPlanMobile({
    super.key,
    required this.studio,
    required this.onBack,
    required this.onStep,
    this.now,
  });

  final Studio studio;
  final VoidCallback onBack;
  final void Function(PlanStep step) onStep;
  final DateTime? now;

  @override
  State<StudyPlanMobile> createState() => _StudyPlanMobileState();
}

class _StudyPlanMobileState extends State<StudyPlanMobile> {
  SharedPreferences? _prefs;
  PlanSettings? _settings;
  StudyPlan? _plan;

  /// Day key → steps done that day.
  var _done = <String, Set<String>>{};
  var _asked = false;

  DateTime get _now => widget.now ?? DateTime.now();
  String get _id => widget.studio.id;
  String get _today => dayKey(_now);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(StudyPlanMobile old) {
    super.didUpdateWidget(old);
    if (old.studio != widget.studio && _settings != null) _rebuild();
  }

  Future<void> _load() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } on Object {
      prefs = null;
    }
    if (!mounted) return;
    _prefs = prefs;
    _settings = PlanSettings.decode(prefs?.getString('study.plan.$_id'));
    try {
      final raw = jsonDecode(prefs?.getString('study.plan.done.$_id') ?? '{}');
      _done = {
        for (final e in (raw as Map<String, dynamic>).entries)
          e.key: {for (final k in e.value as List) '$k'},
      };
    } on Object {
      _done = {};
    }
    if (_settings != null) {
      _rebuild();
    } else {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_asked) _setup();
      });
    }
  }

  /// Today's steps stay as they were planned this morning; the rest of
  /// the plan follows the studio as it is now.
  void _rebuild() {
    final settings = _settings!;
    final topics = {for (final t in widget.studio.topics) t.id: t};
    List<PlanStep>? fixed;
    try {
      final raw = jsonDecode(_prefs?.getString('study.plan.today.$_id') ?? '');
      if (raw is Map &&
          raw['date'] == _today &&
          raw['set'] == settings.encode()) {
        fixed = [
          for (final j in raw['steps'] as List) ?PlanStep.fromJson(j, topics),
        ];
      }
    } on Object {
      fixed = null;
    }
    final plan = StudyPlan.build(
      widget.studio,
      settings,
      _now,
      todayFixed: fixed,
    );
    if (fixed == null && plan.today != null) {
      _save(
        'study.plan.today.$_id',
        jsonEncode({
          'date': _today,
          'set': settings.encode(),
          'steps': [for (final s in plan.today!.steps) s.toJson()],
        }),
      );
    }
    setState(() => _plan = plan);
  }

  void _save(String key, String value) {
    try {
      _prefs?.setString(key, value);
    } on Object {
      // A plan that isn't kept still works for now.
    }
  }

  void _saveDone() {
    // The last two months are enough for the streak.
    final cut = dayKey(_now.subtract(const Duration(days: 62)));
    _done.removeWhere((k, v) => k.compareTo(cut) < 0 || v.isEmpty);
    _save(
      'study.plan.done.$_id',
      jsonEncode({for (final e in _done.entries) e.key: e.value.toList()}),
    );
  }

  /// Done: ticked, or (cards) nothing left due.
  bool _isDone(PlanStep s) {
    if (_done[_today]?.contains(s.key) ?? false) return true;
    final now = _now;
    int due(Topic t) =>
        t.flashcards.where((c) => CardSchedule.isDue(c, now)).length;
    return switch (s.kind) {
      StepKind.review => widget.studio.topics.every((t) => due(_fresh(t)) == 0),
      StepKind.cards => s.topic != null && due(_fresh(s.topic!)) == 0,
      _ => false,
    };
  }

  /// The topic as the studio has it now (the step may hold an older copy).
  Topic _fresh(Topic t) =>
      widget.studio.topics.where((x) => x.id == t.id).firstOrNull ?? t;

  void _toggle(PlanStep s, {bool? to}) {
    final today = _plan?.today?.steps ?? const [];
    final wasAll = today.isNotEmpty && today.every(_isDone);
    final set = _done.putIfAbsent(_today, () => <String>{});
    final on = to ?? !set.contains(s.key);
    setState(() => on ? set.add(s.key) : set.remove(s.key));
    _saveDone();
    final all = today.isNotEmpty && today.every(_isDone);
    if (all && !wasAll) {
      SmHaptics.done();
    } else {
      SmHaptics.select();
    }
  }

  void _open(PlanStep s) {
    _toggle(s, to: true);
    widget.onStep(s);
  }

  Future<void> _setup() async {
    _asked = true;
    final picked = await showModalBottomSheet<PlanSettings>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SetupSheet(
        start: _settings ?? const PlanSettings(),
        today: dayOf(_now),
      ),
    );
    if (picked == null || !mounted) return;
    _settings = picked;
    _save('study.plan.$_id', picked.encode());
    _rebuild();
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final top = MediaQuery.paddingOf(context).top + SmHeader.clearance;
    final plan = _plan;
    final today = plan?.today;
    final next = today?.steps.where((s) => !_isDone(s)).firstOrNull;
    return Scaffold(
      backgroundColor: c.background,
      body: SmHeaderPage(
        header: SmHeader(
          title: 'Study plan',
          onBack: widget.onBack,
          trailing: SmPressable(
            semanticLabel: 'Plan settings',
            haptic: SmHaptics.tap,
            scale: 0.9,
            onTap: _setup,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.tune_rounded, color: c.text, size: 21),
            ),
          ),
        ),
        child: plan == null
            ? _NoPlan(
                loading: _prefs == null && _settings == null && !_asked,
                onSetup: _setup,
              )
            : Stack(
                children: [
                  Positioned.fill(
                    child: _PlanView(
                      key: ValueKey(_settings!.encode()),
                      plan: plan,
                      now: _now,
                      top: top,
                      streak: planStreak(
                        {
                          for (final e in _done.entries)
                            if (e.value.isNotEmpty) e.key,
                        },
                        plan.settings.days,
                        _now,
                      ),
                      isDone: _isDone,
                      onToggle: _toggle,
                      onOpen: _open,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      child: next == null
                          ? const SizedBox.shrink()
                          : _Cta(
                              key: ValueKey(next.key),
                              label: next.topic == null
                                  ? 'Continue · Review'
                                  : 'Continue · ${switch (next.kind) {
                                      StepKind.lesson => 'Lesson',
                                      StepKind.cards => 'Flashcards',
                                      StepKind.quiz => 'Quiz',
                                      StepKind.review => 'Review',
                                    }}',
                              onTap: () => _open(next),
                            ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _NoPlan extends StatelessWidget {
  const _NoPlan({required this.loading, required this.onSetup});

  final bool loading;
  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    if (loading) return const SizedBox.shrink();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SmAppear(
              index: 0,
              child: Icon(
                Icons.calendar_month_rounded,
                size: 44,
                color: c.accentSoft,
              ),
            ),
            const SizedBox(height: 14),
            SmAppear(
              index: 1,
              child: Text(
                'Make a plan',
                style: t.greeting.copyWith(fontSize: 21),
              ),
            ),
            const SizedBox(height: 6),
            SmAppear(
              index: 2,
              child: Text(
                'For an exam, or at your own pace.',
                style: t.small.copyWith(fontSize: 13),
              ),
            ),
            const SizedBox(height: 20),
            SmAppear(
              index: 3,
              child: _Button(label: 'Set it up', onTap: onSetup),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanView extends StatelessWidget {
  const _PlanView({
    super.key,
    required this.plan,
    required this.now,
    required this.top,
    required this.streak,
    required this.isDone,
    required this.onToggle,
    required this.onOpen,
  });

  final StudyPlan plan;
  final DateTime now;
  final double top;
  final int streak;
  final bool Function(PlanStep step) isDone;
  final void Function(PlanStep step) onToggle;
  final void Function(PlanStep step) onOpen;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final s = plan.settings;
    final today = plan.today;
    final steps = today?.steps ?? const <PlanStep>[];
    final doneMin = steps.where(isDone).fold(0, (n, x) => n + x.minutes);
    final planned = steps.fold(0, (n, x) => n + x.minutes);
    final allDone = steps.isNotEmpty && steps.every(isDone);
    final toExam = plan.daysToExam(now);
    final examPassed = toExam != null && toExam < 0;
    var i = 0;
    Widget appear(Widget child) => SmAppear(index: i++, child: child);
    Widget pill(Widget child, {Color? color}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color?.withValues(alpha: 0.7) ?? c.line),
      ),
      child: DefaultTextStyle.merge(
        style: t.body.copyWith(fontSize: 12.5, color: color ?? c.text),
        child: child,
      ),
    );
    Widget iconText(IconData icon, String text, Color color) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Flexible(child: Text(text)),
      ],
    );

    final topicNames = today?.topics.map((x) => x.title).join(' · ') ?? '';
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(22, top + 4, 22, 120),
      children: [
        appear(
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              if (s.mode == PlanMode.exam && s.exam != null)
                pill(
                  iconText(
                    Icons.flag_rounded,
                    examPassed
                        ? 'Exam passed · set a new date'
                        : 'Exam ${smDate(s.exam!)} · '
                              '$toExam day${toExam == 1 ? '' : 's'}',
                    c.accentSoft,
                  ),
                )
              else
                pill(
                  iconText(
                    Icons.local_fire_department_rounded,
                    streak == 0 ? 'Start a streak' : '$streak-day streak',
                    c.gold,
                  ),
                ),
              pill(Text('${s.minutes} min/day')),
              if (plan.tight)
                pill(Text('Needs ~${plan.needed} min/day'), color: c.gold),
            ],
          ),
        ),
        const SizedBox(height: 18),
        appear(
          Center(
            child: today == null || today.rest
                ? _DayOff(rest: today?.studyDay == false)
                : Semantics(
                    label: '$doneMin of $planned minutes done today',
                    child: ExcludeSemantics(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SmRing(
                            value: planned == 0 ? 0 : doneMin / planned,
                            size: 128,
                            stroke: 9,
                            label: '$doneMin',
                            labelSize: 28,
                            caption: 'of $planned min',
                          ),
                          if (allDone)
                            Positioned(bottom: 0, child: _Badge(colors: c)),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
        if (steps.isNotEmpty) ...[
          const SizedBox(height: 22),
          appear(
            Text(
              topicNames.isEmpty
                  ? 'TODAY'
                  : 'TODAY · ${topicNames.toUpperCase()}',
              maxLines: 2,
              style: t.section.copyWith(fontSize: 11),
            ),
          ),
          const SizedBox(height: 8),
          for (final step in steps)
            appear(
              _StepRow(
                step: step,
                done: isDone(step),
                onToggle: () => onToggle(step),
                onOpen: () => onOpen(step),
              ),
            ),
          if (allDone)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Today’s done. See you tomorrow.',
                textAlign: TextAlign.center,
                style: t.small.copyWith(fontSize: 13, color: _green),
              ),
            ),
        ],
        const SizedBox(height: 26),
        appear(Text('COMING UP', style: t.section.copyWith(fontSize: 11))),
        const SizedBox(height: 12),
        appear(_Upcoming(plan: plan, now: now)),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.colors});

  final SmColors colors;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 420),
    curve: Curves.easeOutBack,
    builder: (context, v, child) => Transform.scale(scale: v, child: child),
    child: Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _green,
        border: Border.all(color: colors.background, width: 3),
      ),
      child: const Icon(Icons.check_rounded, color: Colors.white, size: 16),
    ),
  );
}

class _DayOff extends StatelessWidget {
  const _DayOff({required this.rest});

  final bool rest;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return Column(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: c.line, width: 2),
          ),
          child: Icon(Icons.wb_sunny_outlined, color: c.gold, size: 34),
        ),
        const SizedBox(height: 10),
        Text(rest ? 'Day off' : 'Nothing planned today', style: t.title),
        const SizedBox(height: 2),
        Text(
          rest ? 'Rest is part of the plan.' : 'Every topic is on track.',
          style: t.small.copyWith(fontSize: 12.5),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.done,
    required this.onToggle,
    required this.onOpen,
  });

  final PlanStep step;
  final bool done;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final icon = switch (step.kind) {
      StepKind.review => Icons.replay_rounded,
      StepKind.lesson => Icons.menu_book_rounded,
      StepKind.cards => Icons.style_rounded,
      StepKind.quiz => Icons.help_rounded,
    };
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          // The check: tap to tick by hand.
          Semantics(
            checked: done,
            label: done ? 'Done' : 'Mark done',
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? c.accent : Colors.transparent,
                    border: Border.all(
                      color: done ? c.accent : c.hint,
                      width: 1.6,
                    ),
                  ),
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutBack,
                    scale: done ? 1 : 0,
                    child: const Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: SmPressable(
              semanticLabel: step.topic == null
                  ? step.label
                  : '${step.label}, ${step.topic!.title}',
              haptic: SmHaptics.thud,
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Icon(icon, size: 17, color: done ? c.hint : c.muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: t.body.copyWith(
                          fontSize: 14.5,
                          color: done ? c.hint : c.text,
                          decoration: done ? TextDecoration.lineThrough : null,
                          decorationColor: c.hint,
                          fontWeight: done ? FontWeight.w400 : FontWeight.w500,
                        ),
                        child: Text(step.label),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${step.minutes} min',
                      style: t.small.copyWith(fontSize: 12.5),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 18, color: c.hint),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The next days on a dashed line: a date tile, the day's topics and
/// steps; days off folded together; the exam (or the finish) at the end.
class _Upcoming extends StatelessWidget {
  const _Upcoming({required this.plan, required this.now});

  final StudyPlan plan;
  final DateTime now;

  static const shown = 6;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final rows = <Widget>[];
    final later = plan.days.skip(1).toList();
    var studyShown = 0;
    var k = 0;
    while (k < later.length && studyShown < shown) {
      final d = later[k];
      if (!d.studyDay) {
        var end = k;
        while (end + 1 < later.length && !later[end + 1].studyDay) {
          end++;
        }
        final last = later[end].date;
        rows.add(
          _Line(
            badge: SmDateBadge(date: d.date, muted: true),
            child: Text(
              end == k ? 'Rest' : 'Rest · until ${smDate(last)}',
              style: t.small.copyWith(fontSize: 12.5),
            ),
          ),
        );
        k = end + 1;
        continue;
      }
      studyShown++;
      if (d.rest) {
        rows.add(
          _Line(
            badge: SmDateBadge(date: d.date, muted: true),
            child: Text(
              'Free · nothing due',
              style: t.small.copyWith(fontSize: 12.5),
            ),
          ),
        );
        k++;
        continue;
      }
      final names = d.topics.map((x) => x.title).join(', ');
      rows.add(
        _Line(
          badge: SmDateBadge(date: d.date),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      names.isEmpty ? 'Review' : names,
                      style: t.title.copyWith(fontSize: 14),
                    ),
                  ),
                  Text(
                    '${d.minutes} min',
                    style: t.small.copyWith(fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  for (final s in d.steps)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: c.line),
                      ),
                      child: Text(
                        s.short,
                        style: t.small.copyWith(fontSize: 11.5, color: c.text),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
      k++;
    }

    final s = plan.settings;
    final Widget end;
    if (s.mode == PlanMode.exam && s.exam != null) {
      end = _Line(
        last: true,
        badge: SmDateBadge(
          date: s.exam!,
          highlight: true,
          icon: Icons.flag_rounded,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Exam day', style: t.title.copyWith(fontSize: 14)),
            const SizedBox(height: 2),
            Text(
              plan.tight
                  ? '${plan.left} min of study don’t fit yet'
                  : plan.finish == null
                  ? 'Keep reviewing until then'
                  : 'Every topic covered by ${smDate(plan.finish!)}',
              style: t.small.copyWith(
                fontSize: 12.5,
                color: plan.tight ? c.gold : c.muted,
              ),
            ),
          ],
        ),
      );
    } else {
      final f = plan.finish;
      end = _Line(
        last: true,
        badge: f == null
            ? SmDateBadge(date: now, muted: true, icon: Icons.more_horiz)
            : SmDateBadge(date: f, icon: Icons.flag_rounded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              f == null
                  ? 'Further than four months away'
                  : 'All topics at 80% around ${smDate(f)}',
              style: t.title.copyWith(
                fontSize: 14,
                color: f == null ? c.text : _green,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'At ${s.minutes} min, ${s.days.length} day${s.days.length == 1 ? '' : 's'} a week · a guess from lesson times',
              style: t.small.copyWith(fontSize: 12),
            ),
          ],
        ),
      );
    }
    return Column(children: [...rows, end]);
  }
}

/// A row on the timeline: the date tile on a dashed line, then [child].
class _Line extends StatelessWidget {
  const _Line({required this.badge, required this.child, this.last = false});

  final Widget badge;
  final Widget child;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              badge,
              if (!last)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: CustomPaint(
                      size: const Size(2, double.infinity),
                      painter: _Dashes(c.line),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 4, bottom: last ? 0 : 16),
              child: child,
            ),
          ),
        ],
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
    for (var y = 0.0; y < size.height; y += 7) {
      canvas.drawLine(Offset(x, y), Offset(x, y + 3.5), p);
    }
  }

  @override
  bool shouldRepaint(_Dashes old) => old.color != color;
}

class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    return SmPressable(
      semanticLabel: label,
      haptic: SmHaptics.thud,
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 28),
        decoration: BoxDecoration(
          color: enabled ? c.accent : c.line,
          borderRadius: BorderRadius.circular(999),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: c.accent.withValues(alpha: 0.3),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: SmFonts.heading,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: enabled ? Colors.white : c.hint,
          ),
        ),
      ),
    );
  }
}

class _Cta extends StatelessWidget {
  const _Cta({super.key, required this.label, required this.onTap});

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
      child: _Button(label: label, onTap: onTap),
    );
  }
}

/// How to study: exam (with the calendar) or own pace; minutes; days.
class _SetupSheet extends StatefulWidget {
  const _SetupSheet({required this.start, required this.today});

  final PlanSettings start;
  final DateTime today;

  @override
  State<_SetupSheet> createState() => _SetupSheetState();
}

class _SetupSheetState extends State<_SetupSheet> {
  late var _s = widget.start;

  bool get _ready =>
      _s.days.isNotEmpty &&
      (_s.mode == PlanMode.pace ||
          (_s.exam != null && _s.exam!.isAfter(widget.today)));

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget section(String s) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(s, style: t.section.copyWith(fontSize: 10.5)),
    );
    Widget option(PlanMode mode, IconData icon, String title, String blurb) {
      final on = _s.mode == mode;
      return Expanded(
        child: SmPressable(
          semanticLabel: title,
          onTap: () => setState(() => _s = _s.copyWith(mode: mode)),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: on ? c.accent : c.line,
                width: on ? 1.6 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: on ? c.accentSoft : c.muted),
                const SizedBox(height: 8),
                Text(title, style: t.title.copyWith(fontSize: 14)),
                const SizedBox(height: 2),
                Text(blurb, style: t.small.copyWith(fontSize: 11.5)),
              ],
            ),
          ),
        ),
      );
    }

    Widget chip(String label, bool on, VoidCallback onTap, {double? width}) =>
        SmPressable(
          semanticLabel: label,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: width,
            height: 36,
            padding: width == null
                ? const EdgeInsets.symmetric(horizontal: 16)
                : EdgeInsets.zero,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              color: on ? c.accent : Colors.transparent,
              border: Border.all(color: on ? c.accent : c.line),
            ),
            child: Text(
              label,
              style: t.body.copyWith(
                fontSize: 13,
                fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                color: on ? Colors.white : c.text,
              ),
            ),
          ),
        );

    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 40),
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF2A2B2B) : Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: c.line),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: c.line,
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
                Text(
                  'How do you want to study?',
                  style: t.greeting.copyWith(fontSize: 19),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    option(
                      PlanMode.exam,
                      Icons.flag_rounded,
                      'For an exam',
                      'Fit it all in by the day',
                    ),
                    const SizedBox(width: 8),
                    option(
                      PlanMode.pace,
                      Icons.spa_rounded,
                      'At my own pace',
                      'A steady habit, no deadline',
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _s.mode == PlanMode.exam
                      ? Padding(
                          padding: const EdgeInsets.only(top: 18),
                          child: SmCalendar(
                            today: widget.today,
                            selected: _s.exam,
                            studyDays: _s.days,
                            onSelected: (d) =>
                                setState(() => _s = _s.copyWith(exam: d)),
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                section('MINUTES A DAY'),
                Row(
                  children: [
                    for (final m in PlanSettings.minuteChoices) ...[
                      Expanded(
                        child: chip(
                          '$m',
                          _s.minutes == m,
                          () => setState(() => _s = _s.copyWith(minutes: m)),
                        ),
                      ),
                      if (m != PlanSettings.minuteChoices.last)
                        const SizedBox(width: 6),
                    ],
                  ],
                ),
                section('STUDY DAYS'),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var w = 1; w <= 7; w++)
                      chip(
                        smWeekdays[w - 1].substring(0, 1),
                        _s.days.contains(w),
                        () => setState(() {
                          final days = {..._s.days};
                          days.contains(w) ? days.remove(w) : days.add(w);
                          _s = _s.copyWith(days: days);
                        }),
                        width: 38,
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                _Button(
                  label: 'Make my plan',
                  enabled: _ready,
                  onTap: () => Navigator.of(context).pop(_s),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
