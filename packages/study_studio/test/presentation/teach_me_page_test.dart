import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/data/mock/mock_data.dart';
import 'package:study_studio/src/presentation/teach_me/teach_me_page.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('shows loading indicator', (tester) async {
    await pumpTestApp(
      tester,
      child: const TeachMePage(
        studioId: 'bio',
        topicId: 'cell',
      ),
      delay: Duration.zero,
    );

    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows error state', (tester) async {
    await pumpTestApp(
      tester,
      child: const TeachMePage(
        studioId: 'bio',
        topicId: 'cell',
      ),
      error: Exception('Test error'),
    );

    await tester.pumpAndSettle();

    expect(find.text('Couldn’t open this lesson'), findsOneWidget);
  });

  testWidgets('shows topic not found', (tester) async {
    final studio = buildMockStudiosStashed().first;

    await pumpTestApp(
      tester,
      child: TeachMePage(
        studioId: studio.id,
        topicId: 'does-not-exist',
      ),
      studios: [studio],
    );

    await tester.pumpAndSettle();

    expect(find.text('This topic is gone'), findsOneWidget);
  });

  testWidgets('shows lesson data', (tester) async {
    final studio = buildMockStudiosStashed().first;
    final topic = studio.topics.first;

    await pumpTestApp(
      tester,
      child: TeachMePage(
        studioId: studio.id,
        topicId: topic.id,
      ),
      studios: [studio],
    );

    await tester.pumpAndSettle();

    expect(find.text(topic.title), findsWidgets);
    // The phone's lesson page.
    expect(find.text('Got it · Next topic'), findsOneWidget);
    expect(find.text('Aa'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}