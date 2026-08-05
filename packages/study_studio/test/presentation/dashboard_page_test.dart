import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/data/mock/mock_data.dart';
import 'package:study_studio/src/presentation/dashboard/dashboard_page.dart';

import '../helpers/test_app.dart';

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

    expect(find.textContaining('Error:'), findsOneWidget);
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
    expect(find.text('Choose How You Want to Learn'), findsOneWidget);
    expect(find.text('Continue Where You Left Off'), findsNothing);
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

    expect(find.text(studio.title), findsOneWidget);
    expect(find.text('Choose How You Want to Learn'), findsOneWidget);
    expect(find.text('Welcome back 👋'), findsOneWidget);
    expect(find.text('Continue Learning'), findsOneWidget);
    expect(find.text('Ask AI'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}