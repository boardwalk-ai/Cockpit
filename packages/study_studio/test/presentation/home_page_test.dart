import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/data/mock/mock_data.dart';
import 'package:study_studio/src/presentation/home/study_home_page.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('shows loading indicator', (tester) async {
    await pumpTestApp(
      tester,
      child: const StudyHomePage(),
      delay: Duration.zero,
    );

    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows empty state', (tester) async {
    await pumpTestApp(
      tester,
      child: const StudyHomePage(),
      studios: const [],
    );

    await tester.pumpAndSettle();

    expect(
      find.text('No studios yet — build your first one above.'),
      findsOneWidget,
    );
  });

  testWidgets('shows error state', (tester) async {
    await pumpTestApp(
      tester,
      child: const StudyHomePage(),
      error: Exception('Test error'),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('Error:'), findsOneWidget);
  });

  testWidgets('shows studio data', (tester) async {
    final studios = buildMockStudiosStashed();

    await pumpTestApp(
      tester,
      child: const StudyHomePage(),
      studios: studios,
    );

    await tester.pumpAndSettle();

    expect(find.text('Study Studio'), findsWidgets);
    expect(find.text('New Study Studio'), findsOneWidget);
    expect(find.text(studios.first.title), findsWidgets);
  });
}