import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/data/mock/mock_data.dart';
import 'package:study_studio/src/presentation/quiz_me/quiz_me_page.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('shows loading indicator', (tester) async {
    await pumpTestApp(
      tester,
      child: const QuizMePage(studioId: 'bio'),
      delay: Duration.zero,
    );

    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows error state', (tester) async {
    await pumpTestApp(
      tester,
      child: const QuizMePage(studioId: 'bio'),
      error: Exception('Test error'),
    );

    await tester.pumpAndSettle();

    expect(find.text('Couldn’t load the quiz'), findsOneWidget);
  });

  testWidgets('shows empty quiz state', (tester) async {
    final original = buildMockStudiosStashed().first;
    final emptyStudio = original.copyWith(topics: const []);

    await pumpTestApp(
      tester,
      child: QuizMePage(studioId: emptyStudio.id),
      studios: [emptyStudio],
    );

    await tester.pumpAndSettle();

    expect(find.text('No questions here yet'), findsOneWidget);
  });

  testWidgets('shows quiz data', (tester) async {
    final studios = buildMockStudiosStashed();
    final studio = studios.first;

    await pumpTestApp(
      tester,
      child: QuizMePage(studioId: studio.id, seed: 3),
      studios: studios,
    );

    await tester.pumpAndSettle();

    // The phone's quiz: the round's first question, counted.
    final first = pickQuizRound([
      for (final t in studio.topics) (t.mastery, t.quizQuestions),
    ], seed: 3).first;
    expect(find.text(first.question), findsWidgets);
    expect(find.textContaining('1/'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}