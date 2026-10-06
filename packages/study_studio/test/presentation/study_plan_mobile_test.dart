import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_studio/src/domain/entities/flashcard.dart';
import 'package:study_studio/src/domain/entities/quiz_question.dart';
import 'package:study_studio/src/domain/entities/studio.dart';
import 'package:study_studio/src/domain/entities/topic.dart';
import 'package:study_studio/src/domain/study_plan.dart';
import 'package:study_studio/src/presentation/mobile/study_plan_mobile.dart';

import 'home_page_test.dart' show phone, viewport;

final now = DateTime(2026, 10, 7, 9); // a Wednesday

Topic topic(
  String id,
  String title,
  double mastery, {
  int importance = 3,
  int minutes = 20,
  int cards = 0,
  int quiz = 0,
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
  flashcards: [
    for (var i = 0; i < cards; i++)
      Flashcard(id: '$id$i', topicId: id, front: 'f', back: 'b'),
  ],
  quizQuestions: [
    for (var i = 0; i < quiz; i++)
      QuizQuestion(
        id: '$id-q$i',
        topicId: id,
        type: QuizType.shortAnswer,
        question: 'q',
        answer: 'a',
        explanation: '',
      ),
  ],
);

final studio = Studio(
  id: 's1',
  title: 'Networks',
  subject: '',
  createdAt: now,
  updatedAt: now,
  topics: [
    topic('osi', 'OSI layers', 0.94, cards: 2),
    topic('cc', 'Congestion control', 0.3, importance: 5, cards: 8, quiz: 5),
    topic('sub', 'Subnetting', 0.44, importance: 4, quiz: 4),
    topic('nat', 'NAT', 0.66, importance: 2, cards: 6),
  ],
);

void main() {
  group('the plan', () {
    test('steps per topic: lesson when weak, then cards and quiz', () {
      final cc = StudyPlan.stepsFor(studio.topics[1]);
      expect(cc.map((s) => s.kind), [
        StepKind.lesson,
        StepKind.cards,
        StepKind.quiz,
      ]);
      expect(cc.first.minutes, 15);
      // Known well enough: no lesson, straight to the cards.
      expect(StudyPlan.stepsFor(studio.topics[3]).single.kind, StepKind.cards);
    });

    test('own pace: due cards first, topics by need, days off skipped', () {
      final plan = StudyPlan.build(
        studio,
        const PlanSettings(minutes: 30, days: {1, 2, 3, 4, 5}),
        now,
      );
      final today = plan.today!;
      expect(today.steps.first.kind, StepKind.review);
      expect(today.steps.first.count, 16); // every new card
      expect(today.topics.first.id, 'cc');
      // Saturday and Sunday are rest days.
      final sat = plan.days.firstWhere((d) => d.date.weekday == 6);
      expect(sat.rest, isTrue);
      expect(plan.finish, isNotNull);
      expect(plan.tight, isFalse);
    });

    test('an exam too close: what is left, and the minutes it needs', () {
      final plan = StudyPlan.build(
        studio,
        PlanSettings(
          mode: PlanMode.exam,
          exam: now.add(const Duration(days: 2)),
          minutes: 15,
          days: const {1, 2, 3, 4, 5, 6, 7},
        ),
        now,
      );
      expect(plan.days, hasLength(2));
      expect(plan.tight, isTrue);
      expect(plan.needed, greaterThan(15));
      expect(plan.daysToExam(now), 2);
    });

    test('settings survive a round trip; junk gives null', () {
      final s = PlanSettings(
        mode: PlanMode.exam,
        exam: DateTime(2026, 10, 24),
        minutes: 45,
        days: const {1, 3, 5},
      );
      final back = PlanSettings.decode(s.encode())!;
      expect(back.mode, PlanMode.exam);
      expect(back.exam, DateTime(2026, 10, 24));
      expect(back.minutes, 45);
      expect(back.days, {1, 3, 5});
      expect(PlanSettings.decode('nope'), isNull);
    });

    test('streak: done study days in a row, days off skipped', () {
      // Wed (today, done), Tue done, Mon done, Sun/Sat off, Fri missed.
      final done = {'2026-10-07', '2026-10-06', '2026-10-05'};
      expect(planStreak(done, {1, 2, 3, 4, 5}, now), 3);
      // Today not done yet: it counts from yesterday.
      expect(planStreak({'2026-10-06'}, {1, 2, 3, 4, 5}, now), 1);
      expect(planStreak({}, {1, 2, 3, 4, 5}, now), 0);
    });
  });

  testWidgets('set up a plan, tick a step, open one', (tester) async {
    SharedPreferences.setMockInitialValues({});
    viewport(tester, phone);
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: StudyPlanMobile(
          studio: studio,
          now: now,
          onBack: () {},
          onStep: (s) => opened.add(s.key),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // First time: the setup sheet.
    expect(find.text('How do you want to study?'), findsOne);
    await tester.tap(find.text('For an exam'));
    await tester.pumpAndSettle();
    expect(find.textContaining('October', findRichText: true), findsOne);
    expect(find.text('Pick your exam day'), findsOne);
    await tester.tap(find.text('2 weeks'));
    await tester.pumpAndSettle();
    expect(find.text('days to go · Wed, Oct 21'), findsOne);
    await tester.tap(find.text('At my own pace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make my plan'));
    await tester.pumpAndSettle();

    expect(find.text('Start a streak'), findsOne);
    expect(find.text('30 min/day'), findsOne);
    expect(find.text('Review 16 due cards'), findsOne);
    expect(find.text('COMING UP'), findsOne);

    await tester.tap(find.bySemanticsLabel('Mark done').first);
    await tester.pumpAndSettle();
    expect(find.text('1-day streak'), findsOne);

    await tester.tap(find.text('Lesson').first);
    await tester.pumpAndSettle();
    expect(opened, ['lesson:cc']);

    // Kept: a second open goes straight to the plan.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: StudyPlanMobile(
          studio: studio,
          now: now,
          onBack: () {},
          onStep: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('How do you want to study?'), findsNothing);
    expect(find.text('1-day streak'), findsOne);
    expect(tester.takeException(), isNull);
  });
}
