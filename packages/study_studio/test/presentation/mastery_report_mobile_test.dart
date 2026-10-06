import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    expect(find.text('Today: 2 cards'), findsOne);

    await tester.tap(find.text('Start today’s step'));
    expect(steps.single.topic.id, 'cc');

    await tester.scrollUntilVisible(find.text('Tmrw'), 200);
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tmrw'));
    await tester.pumpAndSettle();
    expect(find.text('Tomorrow: 1 card'), findsOne);

    await tester.scrollUntilVisible(find.text('DNS'), 200);
    await tester.tap(find.text('DNS'));
    expect(opened, ['dns']);
    expect(tester.takeException(), isNull);
  });
}
