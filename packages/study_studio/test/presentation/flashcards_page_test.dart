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

    expect(find.text('Couldn’t load the cards'), findsOneWidget);
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

    expect(find.text('No flashcards yet'), findsOneWidget);
    expect(
      find.text('Cards appear as your studio finishes building.'),
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

    // The phone's deck: the first card's question, counted.
    final first = studio.topics.expand((t) => t.flashcards).first;
    expect(find.text(first.front), findsOneWidget);
    expect(find.textContaining('1/'), findsOneWidget);
    expect(find.text('Tap the card to see the answer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}