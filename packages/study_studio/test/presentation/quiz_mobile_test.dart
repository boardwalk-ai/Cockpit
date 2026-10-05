import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/domain/entities/quiz_question.dart';
import 'package:study_studio/src/presentation/mobile/quiz_mobile.dart';

import 'home_page_test.dart' show phone, viewport;

const mc = QuizQuestion(
  id: 'q1',
  topicId: 'tcp',
  type: QuizType.multipleChoice,
  question: 'Three duplicate ACKs?',
  choices: ['Drops to one', 'Halves', 'Doubles'],
  answer: 'Halves',
  explanation: 'Fast recovery.',
);

const tf = QuizQuestion(
  id: 'q2',
  topicId: 'osi',
  type: QuizType.trueFalse,
  question: 'Routers work at layer 3.',
  choices: ['True', 'False'],
  answer: 'True',
  explanation: 'They route by IP.',
);

const fill = QuizQuestion(
  id: 'q3',
  topicId: 'subnet',
  type: QuizType.fillBlank,
  question: 'A /24 has ____ usable hosts.',
  answer: '254',
  explanation: '256 minus two.',
);

void main() {
  late List<(String, bool)> answers;
  late List<String> reviewed;
  var closed = 0;

  Future<void> show(WidgetTester tester, List<QuizQuestion> qs) async {
    viewport(tester, phone);
    answers = [];
    reviewed = [];
    closed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: QuizMobile(
          questions: qs,
          topicTitles: const {
            'tcp': 'TCP congestion',
            'osi': 'OSI model',
            'subnet': 'Subnetting',
          },
          onClose: () => closed++,
          onAnswer: (q, right) => answers.add((q.id, right)),
          onReview: reviewed.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a full round: choice, true or false, typed; then results', (
    tester,
  ) async {
    await show(tester, [mc, tf, fill]);
    expect(find.text('1/3'), findsOne);
    expect(find.text('MULTIPLE CHOICE · TCP CONGESTION'), findsOne);

    // Wrong, once only.
    await tester.tap(find.text('Drops to one'));
    await tester.pumpAndSettle();
    expect(find.text('Not quite'), findsOne);
    expect(find.text('Fast recovery.'), findsOne);
    await tester.tap(find.text('Halves'));
    expect(answers, [('q1', false)]);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // True or false.
    expect(find.text('TRUE OR FALSE · OSI MODEL'), findsOne);
    await tester.tap(find.text('True'));
    await tester.pumpAndSettle();
    expect(find.text('They route by IP.'), findsOne);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Typed: the blank shows what is typed; Check marks it.
    expect(find.text('FILL THE BLANK · SUBNETTING'), findsOne);
    await tester.enterText(find.byType(TextField), '254');
    await tester.pump();
    expect(find.textContaining(' 254 ', findRichText: true), findsOne);
    await tester.tap(find.bySemanticsLabel('Check'));
    await tester.pumpAndSettle();
    expect(answers.last, ('q3', true));
    await tester.tap(find.text('See results'));
    await tester.pumpAndSettle();

    expect(find.text('2/3'), findsOne);
    expect(find.text('Getting there'), findsOne);
    expect(find.text('REVIEW THESE'), findsOne);
    await tester.tap(find.text('TCP congestion'));
    expect(reviewed, ['tcp']);
    expect(find.text('Retry 1 missed'), findsOne);

    // Retry only what was missed.
    await tester.tap(find.text('Retry 1 missed'));
    await tester.pumpAndSettle();
    expect(find.text('1/1'), findsOne);
    expect(find.text('Three duplicate ACKs?'), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wrong typed answer shows the right one', (tester) async {
    await show(tester, [fill]);
    await tester.enterText(find.byType(TextField), '256');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Not quite'), findsOne);
    expect(find.text('Answer: 254', findRichText: true), findsOne);
    await tester.tap(find.text('See results'));
    await tester.pumpAndSettle();
    expect(find.text('0/1'), findsOne);
    await tester.tap(find.byIcon(Icons.check_rounded).last);
    expect(closed, 1);
  });
}
