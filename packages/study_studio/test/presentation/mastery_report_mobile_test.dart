import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/domain/activity.dart';
import 'package:study_studio/src/domain/entities/flashcard.dart';
import 'package:study_studio/src/domain/entities/studio.dart';
import 'package:study_studio/src/domain/entities/topic.dart';
import 'package:study_studio/src/presentation/mobile/mastery_report_mobile.dart';

import 'home_page_test.dart' show phone, viewport;

final now = DateTime(2026, 10, 7, 9); // a Wednesday

Topic topic(
  String id,
  String title,
  double mastery, {
  int importance = 3,
  int minutes = 20,
  List<Flashcard> cards = const [],
}) => Topic(
  id: id,
  studioId: 's1',
  title: title,
  subject: '',
  definition: '',
  simpleExplanation: '',
  detailedExplanation: '',
  whyItMatters: '',
  mastery: mastery,
  importance: importance,
  estimatedStudyTimeMinutes: minutes,
  flashcards: cards,
);

Flashcard card(String topicId, int n, DateTime? due) => Flashcard(
  id: '$topicId$n',
  topicId: topicId,
  front: 'f',
  back: 'b',
  dueDate: due,
);

final studio = Studio(
  id: 's1',
  title: 'Networks',
  subject: '',
  createdAt: now,
  updatedAt: now,
  topics: [
    topic('osi', 'OSI layers', 0.94),
    topic('tcp', 'TCP handshake', 0.88),
    topic(
      'cc',
      'Congestion control',
      0.31,
      importance: 5,
      cards: [
        card('cc', 1, null),
        card('cc', 2, now.subtract(const Duration(hours: 1))),
        card('cc', 3, now.add(const Duration(days: 1))),
      ],
    ),
    topic('sub', 'Subnetting', 0.44, importance: 4),
    topic('nat', 'NAT', 0.66, importance: 2),
    topic('dns', 'DNS', 0.72, importance: 1),
  ],
);

void main() {
  group('the report', () {
    final r = MasteryReport(studio, now);

    test('counts', () {
      expect(r.learned.map((t) => t.id), ['osi', 'tcp']);
      expect(r.weak.map((t) => t.id), ['cc', 'sub']);
      expect(r.dueNow, 2);
      expect(r.upcoming(), [2, 1, 0, 0, 0, 0, 0]);
    });

    test('the path: most important and least known first, a day each', () {
      final path = r.path;
      expect(path.map((s) => s.topic.id), ['cc', 'sub', 'nat']);
      expect(path.map((s) => s.day), [0, 1, 2]);
      expect(path.first.step, ReportStep.cards);
      expect(path[1].step, ReportStep.lesson);
      expect(r.toFix, hasLength(4));
    });
  });

  testWidgets('a phone report: ring, path, cards, topics', (tester) async {
    viewport(tester, phone);
    final steps = <PathStop>[];
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: MasteryReportMobile(
          studio: studio,
          now: now,
          onBack: () {},
          onTopic: (t) => opened.add(t.id),
          onStep: steps.add,
          onCards: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Getting there'), findsOne);
    expect(find.text('2 learned'), findsOne);
    expect(find.text('2 cards due'), findsOne);
    expect(find.text('Today · 15 min'), findsOne);
    expect(find.text('2 cards to review'), findsOne);

    await tester.tap(find.text('Start today’s step'));
    expect(steps.single.topic.id, 'cc');

    await tester.scrollUntilVisible(find.text('Tmrw'), 200);
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tmrw'));
    await tester.pumpAndSettle();
    expect(find.text('Tomorrow: 1 card'), findsOne);
    await tester.tap(find.text('Today').last);
    await tester.pumpAndSettle();
    expect(find.text('Today: 2 cards'), findsOne);

    await tester.scrollUntilVisible(find.text('DNS'), 200);
    await tester.tap(find.text('DNS'));
    expect(opened, ['dns']);
    expect(tester.takeException(), isNull);
  });

  group('this week and fading', () {
    test('the week: Monday on, compared with last week so far', () {
      // now is Wednesday the 7th: Mon 5, Tue 6, Wed 7.
      final w = WeekActivity([
        DayActivity(date: DateTime(2026, 9, 28), cards: 10), // last Mon
        DayActivity(date: DateTime(2026, 10, 2), cards: 99), // last Fri: later
        DayActivity(date: DateTime(2026, 10, 5), cards: 20, quiz: 4, quizRight: 3),
        DayActivity(date: DateTime(2026, 10, 7), cards: 5),
      ], now);
      expect(w.week.first.date, DateTime(2026, 10, 5));
      expect(w.cards, 25);
      expect(w.accuracy, 0.75);
      expect(w.activeDays, 2);
      expect(w.lastTotal, 10);
    });

    test('recall: 90% on the due day, less after, none unreviewed', () {
      final c = Flashcard(
        id: 'x',
        topicId: 't',
        front: 'f',
        back: 'b',
        reps: 3,
        intervalDays: 4,
        dueDate: now,
      );
      expect(MasteryReport.recall(c, now), closeTo(0.9, 0.001));
      expect(
        MasteryReport.recall(c, now.add(const Duration(days: 4)))!,
        closeTo(0.81, 0.001),
      );
      expect(MasteryReport.recall(card('t', 1, null), now), isNull);
    });
  });

  testWidgets('the week and what is fading, with Review', (tester) async {
    viewport(tester, const Size(390, 1600));
    final reviewed = <String>[];
    final faded = Studio(
      id: 's1',
      title: 'Networks',
      subject: '',
      createdAt: now,
      updatedAt: now,
      topics: [
        topic('sub', 'Subnetting', 0.5, cards: [
          Flashcard(
            id: 's1',
            topicId: 'sub',
            front: 'f',
            back: 'b',
            reps: 2,
            intervalDays: 1,
            dueDate: now.subtract(const Duration(days: 8)),
          ),
        ]),
        topic('dns', 'DNS', 0.9, cards: [
          Flashcard(
            id: 'd1',
            topicId: 'dns',
            front: 'f',
            back: 'b',
            reps: 4,
            intervalDays: 20,
            dueDate: now.add(const Duration(days: 15)),
          ),
        ]),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: MasteryReportMobile(
          studio: faded,
          now: now,
          onBack: () {},
          onTopic: (_) {},
          onStep: (_) {},
          onCards: () {},
          onReview: (t) => reviewed.add(t.id),
          studyDays: const {1, 2, 3, 4, 5},
          activity: [
            DayActivity(date: DateTime(2026, 10, 6), cards: 48, quiz: 2, quizRight: 1),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('THIS WEEK'), findsOne);
    expect(find.text('48 cards'), findsOne);
    expect(find.text('50% quiz right'), findsOne);
    expect(find.text('1 day'), findsOne);
    expect(find.text('Your first reviews since last week.'), findsOne);
    await tester.tap(find.text('50').first);
    await tester.pumpAndSettle();
    expect(find.text('Tue: 48 cards · 1 of 2 quiz right'), findsOne);

    expect(find.text('FADING'), findsOne);
    expect(find.text('Learned, but slipping away'), findsOne);
    expect(find.text('holding well'), findsOne);
    await tester.tap(find.text('Review 1').first);
    expect(reviewed, ['sub']);
    expect(tester.takeException(), isNull);
  });
}
