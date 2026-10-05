import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/domain/entities/flashcard.dart';
import 'package:study_studio/src/presentation/mobile/flashcards_mobile.dart';

import 'home_page_test.dart' show phone, viewport;

final now = DateTime(2026, 10, 6, 9);

Flashcard card(String id, {DateTime? due}) => Flashcard(
  id: id,
  topicId: 'tcp',
  front: 'Question $id?',
  back: 'Answer $id.',
  dueDate: due,
  reps: due == null ? 0 : 2,
  intervalDays: due == null ? 0 : 3,
);

void main() {
  late List<(String, int)> grades;
  var closed = 0;

  Future<void> show(WidgetTester tester, List<Flashcard> cards) async {
    viewport(tester, phone);
    grades = [];
    closed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: FlashcardsMobile(
          cards: cards,
          topicTitles: const {'tcp': 'TCP basics'},
          now: () => now,
          onClose: () => closed++,
          onGrade: (c, g) => grades.add((c.id, g)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('flip, rate with real waits, Again comes back, done', (
    tester,
  ) async {
    await show(tester, [card('a'), card('b')]);
    expect(find.text('Question a?'), findsOne);
    expect(find.text('TCP BASICS'), findsOne);
    expect(find.text('1/2'), findsOne);

    await tester.tap(find.text('Question a?'));
    await tester.pumpAndSettle();
    expect(find.text('Answer a.'), findsOne);
    // A new card: each pill says when it comes back.
    expect(find.text('1 min'), findsOne);
    expect(find.text('10 min'), findsOne);
    expect(find.text('1 day'), findsOne);
    expect(find.text('4 days'), findsOne);

    await tester.tap(find.text('Again'));
    await tester.pumpAndSettle();
    expect(grades, [('a', 0)]);
    expect(find.text('Question b?'), findsOne);

    await tester.tap(find.text('Question b?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();

    // "a" is back.
    expect(find.text('Question a?'), findsOne);
    await tester.tap(find.text('Question a?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Easy'));
    await tester.pumpAndSettle();

    expect(grades, [('a', 0), ('b', 2), ('a', 3)]);
    expect(find.text('Deck done'), findsOne);
    expect(find.text('2 cards · 1 came back'), findsOne);
    expect(find.text('Next review in 1 day · 1 card'), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a swipe right after flipping is Good', (tester) async {
    await show(tester, [card('a')]);
    await tester.tap(find.text('Question a?'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Answer a.'), const Offset(260, 0));
    await tester.pumpAndSettle();
    expect(grades, [('a', 2)]);
    expect(find.text('Deck done'), findsOne);
  });

  testWidgets('nothing due: caught up, or study anyway', (tester) async {
    await show(tester, [
      card('a', due: now.add(const Duration(days: 2))),
      card('b', due: now.add(const Duration(days: 9))),
    ]);
    expect(find.text('All caught up'), findsOne);
    expect(find.text('Next review in 2 days · 1 card'), findsOne);
    await tester.tap(find.text('Study anyway'));
    await tester.pumpAndSettle();
    expect(find.text('Question a?'), findsOne);
    expect(find.text('1/2'), findsOne);
  });
}
