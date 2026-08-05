import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/data/mock/mock_data.dart';
import 'package:study_studio/src/presentation/flashcards/flashcards_page.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('shows loading indicator', (tester) async {
    await pumpTestApp(
      tester,
      child: const FlashcardsPage(studioId: 'bio'),
      delay: Duration.zero,
    );

    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows error state', (tester) async {
    await pumpTestApp(
      tester,
      child: const FlashcardsPage(studioId: 'bio'),
      error: Exception('Test error'),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('Error:'), findsOneWidget);
  });

  testWidgets('shows empty flashcards state', (tester) async {
    final original = buildMockStudiosStashed().first;
    final emptyStudio = original.copyWith(topics: const []);

    await pumpTestApp(
      tester,
      child: FlashcardsPage(studioId: emptyStudio.id),
      studios: [emptyStudio],
    );

    await tester.pumpAndSettle();

    expect(find.text('No flashcards'), findsOneWidget);
    expect(
      find.text('This selection has no cards yet.'),
      findsOneWidget,
    );
  });

  testWidgets('shows flashcard data', (tester) async {
    final studios = buildMockStudiosStashed();
    final studio = studios.first;

    await pumpTestApp(
      tester,
      child: FlashcardsPage(studioId: studio.id),
      studios: studios,
    );

    await tester.pumpAndSettle();

    expect(find.text('Flashcards'), findsOneWidget);
    expect(find.textContaining('Card 1 of'), findsOneWidget);
    expect(find.text('QUESTION'), findsOneWidget);
    expect(find.text('Show Answer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}