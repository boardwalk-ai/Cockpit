import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/data/mock/mock_data.dart';
import 'package:study_studio/src/domain/entities/studio.dart';
import 'package:study_studio/src/presentation/home/study_home_page.dart';
import 'package:study_studio/src/presentation/mobile/mobile_header.dart';
import 'package:study_studio/src/presentation/mobile/studio_library_page.dart';
import 'package:study_studio/src/presentation/mobile/study_greeting.dart';
import 'package:study_studio/src/presentation/mobile/study_home_mobile.dart';

import '../helpers/test_app.dart';

/// A phone, or a desktop, viewport for the next pump.
void viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // The shines loop forever; with reduced motion they stay still, so the
  // tests can settle (and that path is covered too).
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
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
      expect(find.text('YOUR STUDIOS'), findsNothing);
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
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('shows the studio to continue, what is next, and the rest', (
      tester,
    ) async {
      viewport(tester, phone);
      final mock = buildMockStudiosStashed();
      await pumpTestApp(tester, child: const StudyHomePage(), studios: mock);
      await tester.pumpAndSettle();
      expect(find.text('Pick up where you left off'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('New'), findsOneWidget);
      expect(find.text('UP NEXT'), findsOneWidget);
      expect(find.text('YOUR STUDIOS'), findsOneWidget);
      expect(find.text('View all ${mock.length}'), findsOneWidget);
      // No desktop tab bar or theme switcher on the phone.
      expect(find.text('Cockpit'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('greets, rings the latest studio, lists two more', (
      tester,
    ) async {
      viewport(tester, phone);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudyHomeMobile(
              studios: studios(5),
              name: 'Dev Trhein',
              credits: 56085,
              now: DateTime(2026, 10, 5, 15),
              greetingSeed: 1,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          StudyGreetings.pick(DateTime(2026, 10, 5, 15), 'Dev Trhein', seed: 1),
        ),
        findsOneWidget,
      );
      expect(find.text('56,085'), findsOneWidget);
      // GhostWriter's floating header: Home, the wordmark, the credits.
      expect(find.byIcon(Icons.home_outlined), findsOneWidget);
      expect(find.byType(SmHeader), findsOneWidget);
      // The most recent in the ring, the next two listed, not again.
      expect(find.text('Studio 0'), findsOneWidget);
      expect(find.text('mastered'), findsOneWidget);
      expect(find.text('Studio 1'), findsOneWidget);
      expect(find.text('Studio 3'), findsOneWidget);
      expect(find.text('Studio 4'), findsNothing);
      // No topics anywhere: nothing to suggest.
      expect(find.text('UP NEXT'), findsNothing);
      // Everything fits on the screen, under the header.
      expect(tester.getCenter(find.text('View all 5')).dy, lessThan(844));
      expect(
        tester.getTopLeft(find.text('Pick up where you left off')).dy,
        greaterThan(tester.getBottomLeft(find.byType(SmHeader)).dy),
      );
      expect(tester.takeException(), isNull);
    });
  });

  test('greetings fit the time of day and the name', () {
    final night = StudyGreetings.choices(DateTime(2026, 1, 1, 23), null);
    expect(night, contains('Hey night owl'));
    expect(night.any((g) => g.contains('{name}')), isFalse);
    final morning = StudyGreetings.choices(DateTime(2026, 1, 1, 8), 'Dev T');
    expect(morning, contains('Morning, Dev. Fresh mind, fresh notes'));
    expect(morning, isNot(contains('Hey night owl')));
    // The same seed, the same line.
    expect(
      StudyGreetings.pick(DateTime(2026, 1, 1, 8), 'Dev', seed: 7),
      StudyGreetings.pick(DateTime(2026, 1, 1, 8), 'Dev', seed: 7),
    );
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
    expect(find.text('Pick up where you left off'), findsNothing);
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
