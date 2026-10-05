import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_studio/src/data/api/upload_api.dart';
import 'package:study_studio/src/domain/entities/studio.dart';
import 'package:study_studio/src/domain/entities/topic.dart';
import 'package:study_studio/src/presentation/mobile/studio_main_mobile.dart';

import 'home_page_test.dart' show phone, viewport;

Topic topic(String id, double mastery) => Topic(
  id: id,
  studioId: 's1',
  title: 'Topic $id',
  subject: 'Networks',
  definition: '',
  simpleExplanation: '',
  detailedExplanation: '',
  whyItMatters: '',
  mastery: mastery,
);

Studio studio(List<Topic> topics) => Studio(
  id: 's1',
  title: 'Networks ch4',
  subject: 'Networks',
  createdAt: DateTime(2026, 10, 1),
  updatedAt: DateTime(2026, 10, 1),
  topics: topics,
);

List<StudyMode> modes(List<String> tapped) => [
  for (final title in [
    'Teach me',
    'Quiz me',
    'Lightning recall',
    'Flashcards',
    'Scenarios',
    'Visualize',
  ])
    StudyMode(
      icon: Icons.school_rounded,
      color: Colors.red,
      title: title,
      blurb: 'About $title',
      count: '3 things',
      onTap: () => tapped.add(title),
    ),
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<List<String>> show(
    WidgetTester tester,
    Studio s, {
    BuildSnapshot? build,
  }) async {
    viewport(tester, phone);
    final tapped = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: StudioMainMobile(
          studio: s,
          modes: modes(tapped),
          build: build,
          onMenu: () => tapped.add('menu'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tapped;
  }

  testWidgets('modes, topics weakest first, and Continue', (tester) async {
    final tapped = await show(
      tester,
      studio([topic('a', 0.9), topic('b', 0.1), topic('c', 0.5)]),
    );
    expect(find.text('Networks ch4'), findsOne);
    expect(find.text('How do you want\nto learn today?'), findsOne);
    expect(find.text('Teach me'), findsOne);
    expect(find.text('Continue · Topic b'), findsOne);
    expect(find.text('50% overall'), findsOne);
    final b = tester.getTopLeft(find.text('Topic b')).dy;
    final a = tester.getTopLeft(find.text('Topic a')).dy;
    expect(b, lessThan(a));
    await tester.tap(find.text('Teach me'));
    expect(tapped, ['Teach me']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the pill switches the view and remembers it', (tester) async {
    await show(tester, studio([topic('a', 0.4)]));
    // The carousel shows the first cards only.
    expect(find.text('Visualize').hitTestable(), findsNothing);

    await tester.tap(find.bySemanticsLabel('Grid'));
    await tester.pumpAndSettle();
    expect(find.text('Visualize').hitTestable(), findsOne);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(StudioMainMobile.viewKey), 'grid');

    await tester.tap(find.bySemanticsLabel('List'));
    await tester.pumpAndSettle();
    expect(find.text('About Visualize'), findsOne);
    expect(prefs.getString(StudioMainMobile.viewKey), 'list');
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens in the view picked last time', (tester) async {
    SharedPreferences.setMockInitialValues({StudioMainMobile.viewKey: 'list'});
    await show(tester, studio([topic('a', 0.4)]));
    expect(find.text('About Visualize'), findsOne);
  });

  testWidgets('no topics yet: a note, no Continue; a build shows', (
    tester,
  ) async {
    await show(
      tester,
      studio(const []),
      build: const BuildSnapshot(
        status: 'generating',
        stage: '',
        lessonsDone: 3,
        lessonsTotal: 8,
        progressPct: 0.46,
      ),
    );
    expect(
      find.text('Topics appear here as your studio finishes building.'),
      findsOne,
    );
    expect(find.textContaining('Continue'), findsNothing);
    expect(find.text('Building lessons (3 of 8)…'), findsOne);
    expect(find.text('46%'), findsOne);
  });
}
