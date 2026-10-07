import 'dart:convert';
import 'dart:math' as math;

import 'card_schedule.dart';
import 'entities/studio.dart';
import 'entities/topic.dart';

/// A day with no time in it.
DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// Whole days from [a] to [b] (calendar days, not 24-hour spans).
int daysBetween(DateTime a, DateTime b) =>
    // In UTC, so daylight saving's 23- and 25-hour days don't count wrong.
    DateTime.utc(
      b.year,
      b.month,
      b.day,
    ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

String dayKey(DateTime t) =>
    '${t.year}-${t.month.toString().padLeft(2, '0')}-'
    '${t.day.toString().padLeft(2, '0')}';

enum PlanMode { exam, pace }

/// How the user wants to study: for an exam on a date, or at their own
/// pace; how many minutes a day; on which weekdays (1 = Monday); and when
/// to be reminded on those days (minute of the day, null = no reminder).
class PlanSettings {
  const PlanSettings({
    this.mode = PlanMode.pace,
    this.exam,
    this.minutes = 30,
    this.days = const {1, 2, 3, 4, 5},
    this.remind = defaultRemind,
  });

  final PlanMode mode;
  final DateTime? exam;
  final int minutes;
  final Set<int> days;
  final int? remind;

  static const minuteChoices = [15, 30, 45, 60];

  /// 7 PM.
  static const defaultRemind = 19 * 60;

  /// Reminder times offered: 7 AM, noon, 7 PM, 9 PM.
  static const remindChoices = [7 * 60, 12 * 60, 19 * 60, 21 * 60];

  PlanSettings copyWith({
    PlanMode? mode,
    DateTime? exam,
    int? minutes,
    Set<int>? days,
    int? remind,
    bool remindOff = false,
  }) => PlanSettings(
    mode: mode ?? this.mode,
    exam: exam ?? this.exam,
    minutes: minutes ?? this.minutes,
    days: days ?? this.days,
    remind: remindOff ? null : (remind ?? this.remind),
  );

  /// The plan itself, without the reminder: what today's steps are kept
  /// against (changing the reminder doesn't re-plan the day).
  String planKey() => jsonEncode({
    'mode': mode.name,
    if (exam != null) 'exam': dayKey(exam!),
    'minutes': minutes,
    'days': days.toList()..sort(),
  });

  String encode() => jsonEncode({
    ...jsonDecode(planKey()) as Map<String, dynamic>,
    'remind': remind,
  });

  /// For the server, which sends the reminders. [tzMinutes] is the phone's
  /// offset from UTC.
  Map<String, dynamic> toApi(int tzMinutes) => {
    'mode': mode.name,
    if (exam != null) 'exam': dayKey(exam!),
    'minutes': minutes,
    'days': days.toList()..sort(),
    'remind': remind,
    'tzMinutes': tzMinutes,
  };

  static PlanSettings? decode(String? raw) {
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final exam = DateTime.tryParse('${j['exam'] ?? ''}');
      final days = {
        for (final d in (j['days'] as List? ?? const []))
          if (d is int && d >= 1 && d <= 7) d,
      };
      return PlanSettings(
        mode: j['mode'] == 'exam' && exam != null
            ? PlanMode.exam
            : PlanMode.pace,
        exam: exam,
        minutes: (j['minutes'] as num?)?.toInt().clamp(5, 240) ?? 30,
        days: days.isEmpty ? const {1, 2, 3, 4, 5} : days,
        // Plans saved before reminders existed get the usual 7 PM.
        remind: j.containsKey('remind')
            ? switch (j['remind']) {
                final num m when m >= 0 && m < 1440 => m.toInt(),
                _ => null,
              }
            : defaultRemind,
      );
    } on Object {
      return null;
    }
  }
}

enum StepKind { review, lesson, cards, quiz }

/// One thing to do on a day: due cards across the studio, or a topic's
/// lesson, cards or quiz.
class PlanStep {
  const PlanStep({
    required this.kind,
    required this.minutes,
    this.topic,
    this.count = 0,
  });

  final StepKind kind;
  final Topic? topic;
  final int minutes;

  /// Cards or questions in it.
  final int count;

  String get key => '${kind.name}:${topic?.id ?? '*'}';

  String get label => switch (kind) {
    StepKind.review => 'Review $count due card${count == 1 ? '' : 's'}',
    StepKind.lesson => 'Lesson',
    StepKind.cards => 'Flashcards · $count',
    StepKind.quiz => 'Quiz · $count question${count == 1 ? '' : 's'}',
  };

  /// "Lesson", "Cards 8", "Quiz 5": for a pill.
  String get short => switch (kind) {
    StepKind.review => 'Review $count',
    StepKind.lesson => 'Lesson',
    StepKind.cards => 'Cards $count',
    StepKind.quiz => 'Quiz $count',
  };

  Map<String, Object?> toJson() => {
    'k': kind.name,
    't': topic?.id,
    'm': minutes,
    'n': count,
  };

  static PlanStep? fromJson(Object? j, Map<String, Topic> topics) {
    if (j is! Map) return null;
    final kind = StepKind.values.where((k) => k.name == j['k']).firstOrNull;
    if (kind == null) return null;
    final id = j['t'];
    final topic = id == null ? null : topics[id];
    if (id != null && topic == null) return null;
    return PlanStep(
      kind: kind,
      topic: topic,
      minutes: (j['m'] as num?)?.toInt() ?? 5,
      count: (j['n'] as num?)?.toInt() ?? 0,
    );
  }
}

class PlanDay {
  const PlanDay(this.date, this.steps, {this.studyDay = true});

  final DateTime date;
  final List<PlanStep> steps;

  /// A weekday the user studies on.
  final bool studyDay;

  bool get rest => steps.isEmpty;
  int get minutes => steps.fold(0, (n, s) => n + s.minutes);

  /// The topics the day works on, in order.
  List<Topic> get topics {
    final seen = <String>{};
    return [
      for (final s in steps)
        if (s.topic != null && seen.add(s.topic!.id)) s.topic!,
    ];
  }
}

/// The plan: from today, a day at a time, until every topic is at the goal
/// (or the exam). Each day gets the cards coming due, then the next topics'
/// lesson, cards and quiz, as far as its minutes go.
class StudyPlan {
  StudyPlan._({
    required this.settings,
    required this.days,
    required this.finish,
    required this.left,
    required this.needed,
  });

  final PlanSettings settings;
  final List<PlanDay> days;

  /// The day the last topic is reached (null if it doesn't fit before the
  /// exam).
  final DateTime? finish;

  /// Minutes of topic work that don't fit before the exam.
  final int left;

  /// For an exam that doesn't fit: the minutes a day it would take.
  final int needed;

  static const goal = 0.8;
  static const horizon = 120;

  bool get tight => left > 0;
  PlanDay? get today => days.isEmpty ? null : days.first;

  int? daysToExam(DateTime now) =>
      settings.mode == PlanMode.exam && settings.exam != null
      ? daysBetween(now, settings.exam!)
      : null;

  /// The work for one topic, most-needed first.
  static List<PlanStep> stepsFor(Topic t) {
    final steps = <PlanStep>[];
    if (t.mastery < 0.5 || (t.flashcards.isEmpty && t.quizQuestions.isEmpty)) {
      final full = t.estimatedStudyTimeMinutes <= 0
          ? 10
          : t.estimatedStudyTimeMinutes;
      final share = ((goal - t.mastery) / goal).clamp(0.4, 1.0);
      steps.add(
        PlanStep(
          kind: StepKind.lesson,
          topic: t,
          minutes: math.max(5, (full * share / 5).round() * 5),
        ),
      );
    }
    if (t.flashcards.isNotEmpty) {
      final n = t.flashcards.length;
      steps.add(
        PlanStep(
          kind: StepKind.cards,
          topic: t,
          count: n,
          minutes: (n / 2).ceil().clamp(3, 10),
        ),
      );
    }
    if (t.quizQuestions.isNotEmpty) {
      final n = math.min(t.quizQuestions.length, 10);
      steps.add(
        PlanStep(
          kind: StepKind.quiz,
          topic: t,
          count: n,
          minutes: n.clamp(3, 10),
        ),
      );
    }
    return steps;
  }

  /// Cards coming due on each of the next [n] days (today: due now).
  static List<int> dueByDay(Studio studio, DateTime now, int n) {
    final today = dayOf(now);
    final counts = List.filled(n, 0);
    for (final t in studio.topics) {
      for (final c in t.flashcards) {
        final d = c.dueDate == null || CardSchedule.isDue(c, now)
            ? 0
            : daysBetween(today, c.dueDate!);
        if (d >= 0 && d < n) counts[d]++;
      }
    }
    return counts;
  }

  factory StudyPlan.build(
    Studio studio,
    PlanSettings settings,
    DateTime now, {
    List<PlanStep>? todayFixed,
  }) {
    final today = dayOf(now);
    double weight(Topic t) => t.importance.clamp(1, 5) * (1 - t.mastery);
    final toFix = [
      for (final t in studio.topics)
        if (t.mastery < goal) t,
    ]..sort((a, b) => weight(b).compareTo(weight(a)));
    final queue = [for (final t in toFix) ...stepsFor(t)];
    // Today's steps, if already set, come off the queue.
    if (todayFixed != null) {
      final fixed = {for (final s in todayFixed) s.key};
      queue.removeWhere((s) => fixed.contains(s.key));
    }

    final exam = settings.mode == PlanMode.exam && settings.exam != null
        ? dayOf(settings.exam!)
        : null;
    final span = exam == null
        ? horizon
        : math.max(0, math.min(horizon, daysBetween(today, exam)));
    final due = dueByDay(studio, now, math.max(span, 1));

    final practiceSteps = [
      for (final t in (toFix.isEmpty ? studio.topics : toFix))
        for (final s in stepsFor(t))
          if (s.kind != StepKind.lesson) s,
    ];
    var practice = false;
    final days = <PlanDay>[];
    DateTime? finish;
    var carried = 0; // due cards waiting for the next study day
    for (var i = 0; i < span || (i == 0 && span == 0); i++) {
      final date = today.add(Duration(days: i));
      if (exam != null && !date.isBefore(exam)) break;
      final studyDay = settings.days.contains(date.weekday);
      carried += i < due.length ? due[i] : 0;
      if (i == 0 && todayFixed != null) {
        days.add(PlanDay(date, todayFixed, studyDay: studyDay));
        carried = 0;
        continue;
      }
      if (!studyDay) {
        days.add(PlanDay(date, const [], studyDay: false));
        continue;
      }
      final steps = <PlanStep>[];
      var budget = settings.minutes;
      if (carried > 0) {
        final m = (carried / 2).ceil().clamp(3, 10);
        steps.add(PlanStep(kind: StepKind.review, count: carried, minutes: m));
        budget -= m;
        carried = 0;
      }
      // Before an exam, days after the last topic go to practice: cards
      // and quizzes again, weakest first.
      if (queue.isEmpty && exam != null) {
        practice = true;
        queue.addAll(practiceSteps);
      }
      var topicWork = false;
      while (queue.isNotEmpty &&
          (queue.first.minutes <= budget || !topicWork)) {
        final s = queue.removeAt(0);
        steps.add(s);
        budget -= s.minutes;
        topicWork = true;
      }
      if (topicWork && queue.isEmpty && !practice) finish ??= date;
      days.add(PlanDay(date, steps));
      if (queue.isEmpty && exam == null && i > 7) break;
    }

    final left = practice ? 0 : queue.fold(0, (n, s) => n + s.minutes);
    var needed = 0;
    if (left > 0 && exam != null) {
      final studyDays = days.where((d) => d.studyDay).length;
      final total =
          left +
          days.fold<int>(
            0,
            (n, d) => n + d.steps.fold<int>(0, (m, s) => m + s.minutes),
          );
      needed = studyDays == 0 ? total : (total / studyDays / 5).ceil() * 5;
    }
    if (queue.isEmpty && finish == null && toFix.isEmpty) finish = today;
    return StudyPlan._(
      settings: settings,
      days: days,
      finish: queue.isEmpty || practice ? finish : null,
      left: left,
      needed: needed,
    );
  }
}

/// Study days in a row with something done, back from today (today counts
/// once done; days off don't break it).
int planStreak(Set<String> doneDays, Set<int> studyDays, DateTime now) {
  var day = dayOf(now);
  if (!doneDays.contains(dayKey(day))) {
    day = day.subtract(const Duration(days: 1));
  }
  var n = 0;
  for (var i = 0; i < 400; i++) {
    final done = doneDays.contains(dayKey(day));
    if (done) {
      n++;
    } else if (studyDays.contains(day.weekday)) {
      break;
    }
    day = day.subtract(const Duration(days: 1));
  }
  return n;
}
