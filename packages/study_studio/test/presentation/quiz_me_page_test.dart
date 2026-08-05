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

    expect(find.textContaining('Error:'), findsOneWidget);
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

    expect(find.text('No quiz questions'), findsOneWidget);
    expect(
      find.text('This selection has no questions yet.'),
      findsOneWidget,
    );
  });

  testWidgets('shows quiz data', (tester) async {
    final studios = buildMockStudiosStashed();
    final studio = studios.first;

    await pumpTestApp(
      tester,
      child: QuizMePage(studioId: studio.id),
      studios: studios,
    );

    await tester.pumpAndSettle();

    expect(find.text(studio.title), findsOneWidget);
    expect(find.text('Quiz Ready'), findsOneWidget);
    expect(find.textContaining('Question 1 of'), findsOneWidget);
    expect(find.text('Quiz Ready'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}