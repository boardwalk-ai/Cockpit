import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/domain/entities/scenario.dart';
import 'package:study_studio/src/presentation/mobile/scenario_mobile.dart';

import 'home_page_test.dart' show phone, viewport;

const offline = Scenario(
  id: 'sc1',
  studioId: 's1',
  title: 'The office that went offline',
  problem: 'Nobody on the third floor can open a website, but printing works.',
  question: 'Where is the fault most likely?',
  correctOptionId: 'b',
  skills: ['Ruling layers out'],
  clues: [
    ScenarioClue(id: 'c1', label: 'Printing', detail: 'Works fine.'),
    ScenarioClue(id: 'c2', label: 'Gateway', detail: 'Does not answer.'),
  ],
  options: [
    ScenarioOption(id: 'a', label: 'Replace the cables'),
    ScenarioOption(id: 'b', label: 'Check the default gateway'),
  ],
  reasoning: 'Layers 1 and 2 work; the floor cannot leave its network.',
  outcomeLabel: 'Likely issue: Layer 3',
  relatedTopics: ['OSI model'],
);

void main() {
  late List<bool> decided;
  late List<String> lessons;
  var another = 0;

  Future<void> show(WidgetTester tester) async {
    viewport(tester, phone);
    decided = [];
    lessons = [];
    another = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ScenarioMobile(
          scenario: offline,
          number: 1,
          total: 3,
          onBack: () {},
          onAnother: () => another++,
          onLesson: lessons.add,
          onDecided: decided.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> next(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('brief, investigate, decide, outcome', (tester) async {
    await show(tester);
    expect(find.text('Scenario 1 of 3'), findsOne);
    expect(find.text('Intermediate'), findsOne);
    expect(find.text('Where is the fault most likely?'), findsOne);

    // Clues can't be turned before the brief is done.
    await tester.tap(find.text('Gateway'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Does not answer.'), findsNothing);

    await next(tester, 'Start investigating');
    expect(find.text('Turn over a clue first'), findsOne);
    await tester.tap(find.text('Gateway'));
    await tester.pumpAndSettle();
    expect(find.text('Does not answer.'), findsOne);
    expect(find.text('1 of 2 found'), findsOne);

    await next(tester, 'Make your call');
    expect(find.text('Choose an action'), findsOne);
    await tester.tap(find.text('Replace the cables'));
    await tester.pumpAndSettle();
    await next(tester, 'Lock in');
    expect(decided, [false]);
    expect(find.text('Not the best first move'), findsOne);
    expect(find.text('Likely issue: Layer 3'), findsOne);

    await tester.scrollUntilVisible(find.text('OSI model'), 200);
    await tester.tap(find.text('OSI model'));
    expect(lessons, ['OSI model']);
    await next(tester, 'Try another');
    expect(another, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the right call', (tester) async {
    await show(tester);
    await next(tester, 'Start investigating');
    await tester.tap(find.text('Printing'));
    await tester.pumpAndSettle();
    await next(tester, 'Make your call');
    await tester.tap(find.text('Check the default gateway'));
    await tester.pumpAndSettle();
    await next(tester, 'Lock in');
    expect(decided, [true]);
    expect(find.text('Good call'), findsOne);
  });
}
