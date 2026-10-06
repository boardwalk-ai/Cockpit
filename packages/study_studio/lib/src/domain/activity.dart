/// One local day of study: cards reviewed, quiz answers, right answers.
class DayActivity {
  const DayActivity({
    required this.date,
    this.cards = 0,
    this.quiz = 0,
    this.quizRight = 0,
  });

  final DateTime date;
  final int cards;
  final int quiz;
  final int quizRight;

  int get total => cards + quiz;
  bool get active => total > 0;

  static DayActivity? fromJson(Object? j) {
    if (j is! Map) return null;
    final d = DateTime.tryParse('${j['date']}');
    if (d == null) return null;
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return DayActivity(
      date: DateTime(d.year, d.month, d.day),
      cards: n('cards'),
      quiz: n('quiz'),
      quizRight: n('quizRight'),
    );
  }
}

/// Two weeks of [DayActivity], oldest first, read as this week (Monday
/// on) and the same days of last week.
class WeekActivity {
  WeekActivity(List<DayActivity> days, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final byDay = {for (final d in days) d.date: d};
    DayActivity at(DateTime d) => byDay[d] ?? DayActivity(date: d);
    week = [for (var i = 0; i < 7; i++) at(monday.add(Duration(days: i)))];
    // Last week, up to the same weekday, so the two compare fairly.
    lastWeek = [
      for (var i = 0; i < today.weekday; i++)
        at(monday.subtract(Duration(days: 7 - i))),
    ];
    this.today = today;
  }

  late final List<DayActivity> week;
  late final List<DayActivity> lastWeek;
  late final DateTime today;

  List<DayActivity> get soFar => [
    for (final d in week)
      if (!d.date.isAfter(today)) d,
  ];

  int get cards => soFar.fold(0, (n, d) => n + d.cards);
  int get quiz => soFar.fold(0, (n, d) => n + d.quiz);
  int get quizRight => soFar.fold(0, (n, d) => n + d.quizRight);
  int get activeDays => soFar.where((d) => d.active).length;
  int get lastCards => lastWeek.fold(0, (n, d) => n + d.cards);
  int get lastTotal => lastWeek.fold(0, (n, d) => n + d.total);
  int get total => cards + quiz;

  /// Quiz answers right this week (null with none).
  double? get accuracy => quiz == 0 ? null : quizRight / quiz;
}
