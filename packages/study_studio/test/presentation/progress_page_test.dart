import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/data/mock/mock_data.dart';
import 'package:study_studio/src/presentation/progress/progress_page.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('shows loading indicator', (tester) async {
    await pumpTestApp(
      tester,
      child: const ProgressPage(studioId: 'bio'),
      delay: Duration.zero,
    );

    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows error state', (tester) async {
    await pumpTestApp(
      tester,
      child: const ProgressPage(studioId: 'bio'),
      error: Exception('Test error'),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('Error:'), findsOneWidget);
  });

  testWidgets('shows empty progress state', (tester) async {
    final original = buildMockStudiosStashed().first;
    final emptyStudio = original.copyWith(topics: const []);

    await pumpTestApp(
      tester,
      child: ProgressPage(studioId: emptyStudio.id),
      studios: [emptyStudio],
    );

    await tester.pumpAndSettle();

    expect(find.text('Progress'), findsOneWidget);
    expect(find.text('Overall mastery'), findsOneWidget);
    expect(find.text('By topic (weakest first)'), findsOneWidget);
    expect(find.text('0'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows mastery report data', (tester) async {
    final studios = buildMockStudiosStashed();
    final studio = studios.first;

    await pumpTestApp(
      tester,
      child: ProgressPage(studioId: studio.id),
      studios: studios,
    );

    await tester.pumpAndSettle();

    expect(find.text('Progress'), findsOneWidget);
    expect(find.text('Overall mastery'), findsOneWidget);
    expect(find.text('By topic (weakest first)'), findsOneWidget);
    expect(find.text(studio.topics.first.title), findsWidgets);
    expect(find.text('Topics'), findsOneWidget);
    expect(find.text('Weak'), findsWidgets);
    expect(find.text('Strong'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}