import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/data/mock/mock_data.dart';
import 'package:study_studio/src/domain/entities/studio.dart';
import 'package:study_studio/src/presentation/home/study_home_page.dart';
import 'package:study_studio/src/presentation/mobile/study_home_mobile.dart';
import 'package:study_studio/src/presentation/mobile/studio_library_page.dart';

import '../helpers/test_app.dart';

/// A phone, or a desktop, viewport for the next pump.
void viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

const phone = Size(390, 844);
const desktop = Size(1366, 900);

/// [count] studios, the first studied most recently.
List<Studio> studios(int count) {
  final now = DateTime(2026, 10, 5, 15);
  return [
    for (var i = 0; i < count; i++)
      Studio(
        id: 's$i',
        title: 'Studio $i',
        subject: 'Economics',
        createdAt: now.subtract(Duration(days: i)),
        updatedAt: now.subtract(Duration(days: i)),
        lastStudied: now.subtract(Duration(days: i)),
      ),
  ];
}

void main() {
  group('on a phone', () {
    testWidgets('shows a loading indicator', (tester) async {
      viewport(tester, phone);
      await pumpTestApp(tester, child: const StudyHomePage());
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('invites a first studio when there is none', (tester) async {
      viewport(tester, phone);
      await pumpTestApp(tester, child: const StudyHomePage());
      await tester.pumpAndSettle();
      expect(find.text('Start your first studio'), findsOneWidget);
      expect(find.text('New study studio'), findsOneWidget);
      expect(find.text('CONTINUE'), findsNothing);
    });

    testWidgets('says when the studios did not load', (tester) async {
      viewport(tester, phone);
      await pumpTestApp(
        tester,
        child: const StudyHomePage(),
        error: Exception('Test error'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't load your studios"), findsOneWidget);
    });

    testWidgets('shows what to continue, what is next, and the studios', (
      tester,
    ) async {
      viewport(tester, phone);
      final mock = buildMockStudiosStashed();
      await pumpTestApp(tester, child: const StudyHomePage(), studios: mock);
      await tester.pumpAndSettle();
      expect(find.text('New study studio'), findsOneWidget);
      expect(find.text('CONTINUE'), findsOneWidget);
      expect(find.text('UP NEXT'), findsOneWidget);
      expect(find.text('YOUR STUDIOS'), findsOneWidget);
      expect(find.text(mock.first.title), findsWidgets);
      // No desktop tab bar or theme switcher on the phone.
      expect(find.text('Cockpit'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lists three studios and links the rest', (tester) async {
      viewport(tester, phone);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudyHomeMobile(
              studios: studios(5),
              name: 'Dev Trhein',
              credits: 56085,
              now: DateTime(2026, 10, 5, 15),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Good afternoon,\nDev'), findsOneWidget);
      expect(find.text('56,085'), findsOneWidget);
      expect(find.text('View all 5'), findsOneWidget);
      // The most recent first; only three.
      expect(find.text('Studio 0'), findsWidgets);
      expect(find.text('Studio 2'), findsOneWidget);
      expect(find.text('Studio 3'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the desktop home is unchanged', (tester) async {
    viewport(tester, desktop);
    await pumpTestApp(
      tester,
      child: const StudyHomePage(),
      studios: buildMockStudiosStashed(),
    );
    await tester.pumpAndSettle();
    expect(find.text('New Study Studio'), findsOneWidget);
    expect(find.text('CONTINUE'), findsNothing);
  });

  group('the studio library', () {
    Future<void> open(WidgetTester tester, List<Studio> list) async {
      viewport(tester, phone);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StudioLibrary(studios: list)),
        ),
      );
      await tester.pumpAndSettle();
    }

    List<String> titles(WidgetTester tester) => tester
        .widgetList<StudioRow>(find.byType(StudioRow))
        .map((row) => row.studio.title)
        .toList();

    testWidgets('lists every studio, most recent first', (tester) async {
      await open(tester, studios(6));
      expect(find.text('6 studios'), findsOneWidget);
      expect(titles(tester), [for (var i = 0; i < 6; i++) 'Studio $i']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('searches and sorts', (tester) async {
      final list = [
        ...studios(2),
        Studio(
          id: 'bio',
          title: 'Biology basics',
          subject: 'Biology',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ];
      await open(tester, list);

      await tester.enterText(find.byType(TextField), 'bio');
      await tester.pumpAndSettle();
      expect(titles(tester), ['Biology basics']);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.textContaining('No studio matches'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('Name'));
      await tester.pumpAndSettle();
      expect(titles(tester), ['Biology basics', 'Studio 0', 'Studio 1']);
    });
  });
}
