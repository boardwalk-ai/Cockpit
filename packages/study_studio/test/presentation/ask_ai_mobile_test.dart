import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/data/api/sse_client.dart';
import 'package:study_studio/src/domain/ask.dart';
import 'package:study_studio/src/domain/entities/concept.dart';
import 'package:study_studio/src/domain/entities/quiz_question.dart';
import 'package:study_studio/src/domain/entities/topic.dart';
import 'package:study_studio/src/presentation/mobile/ask_ai_mobile.dart';

import 'home_page_test.dart' show phone, viewport;

Topic topic(
  String id,
  String title,
  double mastery, {
  List<Concept> concepts = const [],
  List<QuizQuestion> quiz = const [],
}) => Topic(
  id: id,
  studioId: 's1',
  title: title,
  subject: '',
  definition: '',
  simpleExplanation: '',
  detailedExplanation: '',
  whyItMatters: '',
  mastery: mastery,
  concepts: concepts,
  quizQuestions: quiz,
);

final cc = topic(
  'cc',
  'Congestion control',
  0.3,
  concepts: const [
    Concept(id: 'a', name: 'Packet loss'),
    Concept(id: 'b', name: 'Congestion window'),
  ],
  quiz: const [
    QuizQuestion(
      id: 'q1',
      topicId: 'cc',
      type: QuizType.shortAnswer,
      question: 'What halves?',
      answer: 'The window',
      explanation: '',
    ),
  ],
);
final nat = topic('nat', 'NAT', 0.5);
final osi = topic('osi', 'OSI layers', 0.9);

void main() {
  test('suggestions come from the weak spots', () {
    expect(askSuggestions([osi, nat, cc]), [
      'Explain Congestion control simply',
      'Give me an example of NAT',
      'Why does OSI layers matter?',
    ]);
    expect(askSuggestions([osi, cc], focus: cc), [
      'Explain Congestion control simply',
      'How does Packet loss connect to Congestion window?',
      'Why does Congestion control matter?',
    ]);
    expect(askSuggestions(const []), isEmpty);
  });

  test('the related topic: titles, then ideas', () {
    expect(askRelatedTopic([osi, nat, cc], 'a packet loss halves it'), cc);
    expect(
      askRelatedTopic([osi, nat, cc], 'NAT and the congestion window'),
      nat,
    );
    expect(askRelatedTopic([osi, nat, cc], 'nothing here'), isNull);
  });

  test('SSE lines become events, one at a time', () {
    final r = SseReader();
    expect(r.add('event: delta'), isNull);
    expect(r.add('data: {"text": "Hi"}'), isNull);
    final e = r.add('')!;
    expect(e.event, 'delta');
    expect(e.data['text'], 'Hi');
    r.add('event: citations');
    r.add('data: [{"fileName": "a.pdf"}]');
    expect(r.add('')!.data['value'], isA<List<dynamic>>());
    expect(r.add(''), isNull);
  });

  testWidgets('ask, watch it stream, follow up with history', (tester) async {
    viewport(tester, phone);
    final handle = tester.ensureSemantics();
    final asked = <(String, Topic?, List<AskTurn>)>[];
    late StreamController<AskEvent> live;
    final quizzed = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: AskAiMobile(
          topics: [osi, nat, cc],
          fileCount: 3,
          ask: (q, t, h) {
            asked.add((q, t, h));
            live = StreamController<AskEvent>();
            return live.stream;
          },
          onBack: () {},
          onLesson: (_) {},
          onQuiz: (t) => quizzed.add(t.id),
          onCards: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('What’s unclear?'), findsOne);
    expect(find.text('Answers come from your 3 files'), findsOne);

    await tester.tap(find.text('Explain Congestion control simply'));
    await tester.pump();
    expect(asked.single.$1, 'Explain Congestion control simply');
    await tester.pump(const Duration(milliseconds: 700));
    expect(
      find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Thinking'),
      findsOne,
    );

    live.add(
      const AskSources([AskSource(number: 1, fileName: 'Lecture 5.pdf')]),
    );
    live.add(const AskText('A lost packet halves the **congestion window** '));
    live.add(const AskText('[1].'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Lecture 5.pdf'), findsOne);
    expect(
      find.textContaining('congestion window', findRichText: true),
      findsOne,
    );
    await live.close();
    await tester.pumpAndSettle();

    // It was about congestion control: ways in, and follow-ups.
    expect(find.text('IN YOUR STUDIO'), findsOne);
    expect(find.text('Quiz · 1'), findsOne);
    await tester.tap(find.text('Quiz me on this'));
    expect(quizzed, ['cc']);

    await tester.tap(find.text('Give an example'));
    await tester.pump();
    expect(asked.last.$1, 'Give me an example of that');
    expect(asked.last.$3.single.question, 'Explain Congestion control simply');
    expect(asked.last.$3.single.answer, contains('congestion window'));

    live.addError(Exception('down'));
    await live.close();
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOne);

    // Narrow to one topic.
    await tester.tap(find.byIcon(Icons.edit_note_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Congestion control'));
    await tester.pumpAndSettle();
    expect(
      find.text('How does Packet loss connect to Congestion window?'),
      findsOne,
    );
    await tester.enterText(find.byType(TextField), 'What is it?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(asked.last.$2, cc);
    await live.close();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    handle.dispose();
  });
}
