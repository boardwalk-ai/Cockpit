import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_studio/src/data/mock/mock_data.dart';
import 'package:study_studio/src/presentation/dashboard/dashboard_page.dart';
import 'package:study_studio/src/presentation/lightning_recall/lightning_recall_page.dart';

import '../helpers/test_app.dart';
import 'lightning_mobile_test.dart' show FakeVoice;

void main() {
  testWidgets('shows loading indicator', (tester) async {
    await pumpTestApp(
      tester,
      child: const DashboardPage(studioId: 'bio'),
      delay: Duration.zero,
    );

    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows error state', (tester) async {
    await pumpTestApp(
      tester,
      child: const DashboardPage(studioId: 'bio'),
      error: Exception('Test error'),
    );

    await tester.pumpAndSettle();

    expect(find.text('Couldn’t open this studio'), findsOneWidget);
  });

  testWidgets('shows empty studio state', (tester) async {
    final original = buildMockStudiosStashed().first;
    final emptyStudio = original.copyWith(topics: const []);

    await pumpTestApp(
      tester,
      child: DashboardPage(studioId: emptyStudio.id),
      studios: [emptyStudio],
    );

    await tester.pumpAndSettle();

    expect(find.text(emptyStudio.title), findsOneWidget);
    expect(find.text('How do you want\nto learn today?'), findsOneWidget);
    expect(
      find.text('Topics appear here as your studio finishes building.'),
      findsOneWidget,
    );
    expect(find.textContaining('Continue'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows dashboard data', (tester) async {
    final studios = buildMockStudiosStashed();
    final studio = studios.first;

    await pumpTestApp(
      tester,
      child: DashboardPage(studioId: studio.id),
      studios: studios,
    );

    await tester.pumpAndSettle();

    // The phone's studio page: modes, topics, Continue, Ask AI.
    expect(find.text(studio.title), findsOneWidget);
    expect(find.text('Teach me'), findsOneWidget);
    expect(find.text('TOPICS'), findsOneWidget);
    expect(find.textContaining('Continue · '), findsOneWidget);
    expect(find.bySemanticsLabel('Ask AI'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('voices the first Lightning recall question ahead', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final studios = buildMockStudiosStashed();
    final studio = studios.first;
    final voice = FakeVoice();
    await pumpTestApp(
      tester,
      child: DashboardPage(studioId: studio.id),
      studios: studios,
      voice: voice,
    );
    await tester.pumpAndSettle();
    expect(voice.warmed, [recallItems(studio).first.question]);
  });
}
