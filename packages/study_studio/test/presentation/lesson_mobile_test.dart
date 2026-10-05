import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_studio/src/domain/entities/quiz_question.dart';
import 'package:study_studio/src/domain/entities/source.dart';
import 'package:study_studio/src/domain/entities/topic.dart';
import 'package:study_studio/src/presentation/mobile/lesson_mobile.dart';

import 'home_page_test.dart' show phone, viewport;

const full = Topic(
  id: 't1',
  studioId: 's1',
  title: 'TCP congestion control',
  subject: 'Networks',
  definition: 'TCP slows down when the network is crowded.',
  simpleExplanation: 'Like a careful driver.\n\nLost packets are brake lights.',
  detailedExplanation: 'ssthresh remembers where trouble began.',
  whyItMatters: 'It saved the internet in 1986.',
  examples: ['A video blurs, then recovers.'],
  commonMistakes: ['Flow control is the same thing.'],
  memoryHooks: ['Double, then add one.'],
  sources: [SourceReference(fileName: 'ch4.pdf', snippet: '', page: 12)],
  quizQuestions: [
    QuizQuestion(
      id: 'q1',
      topicId: 't1',
      type: QuizType.multipleChoice,
      question: 'Three duplicate ACKs?',
      choices: ['Drops to one', 'Halves'],
      answer: 'Halves',
      explanation: 'Fast recovery.',
    ),
  ],
  importance: 5,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<Map<String, Object>> show(WidgetTester tester, Topic topic) async {
    viewport(tester, phone);
    final calls = <String, Object>{};
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: LessonMobile(
          topic: topic,
          studioTitle: 'Networks ch4',
          number: 3,
          total: 8,
          onBack: () => calls['back'] = true,
          onAsk: () => calls['ask'] = true,
          onDone: () => calls['done'] = true,
          onAnswer: (right) => calls['answer'] = right,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return calls;
  }

  testWidgets('every part of a full lesson, in order', (tester) async {
    await show(tester, full);
    expect(find.text('TCP congestion control'), findsWidgets);
    expect(find.text('3 of 8'), findsOne);
    expect(find.text('NETWORKS CH4 · 10 MIN READ'), findsOne);
    expect(find.text('Key topic'), findsOne);
    expect(find.text('IN ONE SENTENCE'), findsOne);
    // Paragraphs split on blank lines.
    expect(find.text('Like a careful driver.'), findsOne);
    expect(find.text('Lost packets are brake lights.'), findsOne);
    // Folded until asked.
    expect(find.text('ssthresh remembers where trouble began.'), findsNothing);
    for (final label in [
      'FOR EXAMPLE',
      'COMMON MISTAKE',
      'MEMORY HOOK',
      'Why it matters',
      'Check yourself',
      'FROM YOUR NOTES',
      'ch4.pdf · p.12',
    ]) {
      await tester.scrollUntilVisible(find.text(label), 200);
      expect(find.text(label), findsOne, reason: label);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('go deeper opens the detail', (tester) async {
    await show(tester, full);
    await tester.tap(find.text('Go deeper'));
    await tester.pumpAndSettle();
    expect(find.text('ssthresh remembers where trouble began.'), findsOne);
    expect(find.text('Show less'), findsOne);
  });

  testWidgets('an answer is marked and explained once', (tester) async {
    final calls = await show(tester, full);
    await tester.scrollUntilVisible(find.text('Drops to one'), 200);
    await tester.tap(find.text('Drops to one'));
    await tester.pumpAndSettle();
    expect(calls['answer'], false);
    expect(find.text('Not quite. Fast recovery.'), findsOne);
    await tester.tap(find.text('Halves'));
    expect(calls['answer'], false); // one try
  });

  testWidgets('Aa steps the size and keeps it', (tester) async {
    await show(tester, full);
    double size() => tester
        .widget<Text>(find.text('Like a careful driver.'))
        .style!
        .fontSize!;
    expect(size(), LessonMobile.sizes[1]);
    await tester.tap(find.text('Aa'));
    await tester.pumpAndSettle();
    expect(size(), LessonMobile.sizes[2]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(LessonMobile.sizeKey), 2);
  });

  testWidgets('a bare topic shows only what it has; Got it, Ask', (
    tester,
  ) async {
    final calls = await show(
      tester,
      const Topic(
        id: 't2',
        studioId: 's1',
        title: 'DNS',
        subject: 'Networks',
        definition: '',
        simpleExplanation: 'Names to numbers.',
        detailedExplanation: '',
        whyItMatters: '',
      ),
    );
    expect(find.text('Names to numbers.'), findsOne);
    expect(find.text('IN ONE SENTENCE'), findsNothing);
    expect(find.text('Go deeper'), findsNothing);
    expect(find.text('Check yourself'), findsNothing);
    await tester.tap(find.text('Got it · Next topic'));
    await tester.tap(find.bySemanticsLabel('Ask AI about this'));
    expect(calls['done'], true);
    expect(calls['ask'], true);
    expect(tester.takeException(), isNull);
  });
}
