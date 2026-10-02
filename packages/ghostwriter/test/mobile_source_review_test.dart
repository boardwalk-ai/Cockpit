import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwriter/src/mobile/mobile_cards.dart';
import 'package:ghostwriter/src/session/timeline.dart';

void main() {
  QuestionItem review() => QuestionItem.fromEvent({
    'field': 'sourceReview',
    'question': 'Review each source, then continue.',
    'inputType': 'sourceReview',
    'allowCustom': false,
    'sources': [
      {
        'url': 'https://noaa.example/slr',
        'title': 'Sea level rise scenarios',
        'publisher': 'NOAA',
      },
      {'url': 'https://www.nature.example/retreat', 'title': 'Managed retreat'},
      {'url': 'https://city.example/plan', 'title': ''},
    ],
  });

  late List<Object> answers;

  Future<void> show(WidgetTester tester, QuestionItem question) async {
    answers = [];
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SingleChildScrollView(
            child: GwQuestionCard(
              question: question,
              active: true,
              onAnswer: (value) async => answers.add(value),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('lists every source with its publisher or site', (tester) async {
    await show(tester, review());

    expect(find.text('Sea level rise scenarios'), findsOneWidget);
    expect(find.text('NOAA'), findsOneWidget);
    // No publisher: the site stands in, without the www.
    expect(find.text('nature.example'), findsOneWidget);
    // No title either.
    expect(find.text('Untitled source'), findsOneWidget);
    expect(find.text('Continue with 3 of 3 sources'), findsOneWidget);
  });

  testWidgets('continuing untouched keeps every source', (tester) async {
    await show(tester, review());

    await tap(tester, find.text('Continue with 3 of 3 sources'));

    expect(answers, [
      [
        {'url': 'https://noaa.example/slr'},
        {'url': 'https://www.nature.example/retreat'},
        {'url': 'https://city.example/plan'},
      ],
    ]);
  });

  testWidgets('a source can be left out and another given a note', (
    tester,
  ) async {
    await show(tester, review());

    // Leave out the last source.
    await tap(tester, find.byTooltip('Exclude source').last);
    expect(find.text('Continue with 2 of 3 sources'), findsOneWidget);
    expect(find.byTooltip('Include source'), findsOneWidget);
    // A source that is left out offers no note.
    expect(find.text('Add a focus note'), findsNWidgets(2));

    // Say what to take from the first.
    await tap(tester, find.text('Add a focus note').first);
    await tester.enterText(find.byType(TextField), '  Only the 2050 figures ');
    await tester.pump();

    await tap(tester, find.text('Continue with 2 of 3 sources'));

    expect(answers, [
      [
        {
          'url': 'https://noaa.example/slr',
          'focusNote': 'Only the 2050 figures',
        },
        {'url': 'https://www.nature.example/retreat'},
        {'url': 'https://city.example/plan', 'rejected': true},
      ],
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a note on a source that is then left out is not sent', (
    tester,
  ) async {
    await show(tester, review());

    await tap(tester, find.text('Add a focus note').first);
    await tester.enterText(find.byType(TextField), 'Use the tables');
    await tester.pump();
    await tap(tester, find.byTooltip('Exclude source').first);
    await tap(tester, find.text('Continue with 2 of 3 sources'));

    expect((answers.single as List).first, {
      'url': 'https://noaa.example/slr',
      'rejected': true,
    });
  });

  testWidgets('a left-out source can be brought back', (tester) async {
    await show(tester, review());

    await tap(tester, find.byTooltip('Exclude source').first);
    await tap(tester, find.byTooltip('Include source'));

    expect(find.text('Continue with 3 of 3 sources'), findsOneWidget);
  });

  testWidgets('leaving out every source cannot be sent', (tester) async {
    await show(tester, review());

    for (var i = 0; i < 3; i++) {
      await tap(tester, find.byTooltip('Exclude source').first);
    }
    expect(find.text('Keep at least one source'), findsOneWidget);

    await tap(tester, find.text('Keep at least one source'));
    expect(answers, isEmpty);
  });

  testWidgets('an answered review shows counts, not links', (tester) async {
    final question = review()
      ..answered = true
      ..answer = [
        {'url': 'https://noaa.example/slr', 'focusNote': 'Only 2050'},
        {'url': 'https://www.nature.example/retreat'},
        {'url': 'https://city.example/plan', 'rejected': true},
      ];
    await show(tester, question);

    expect(find.text('2 sources kept'), findsOneWidget);
    expect(find.text('1 left out'), findsOneWidget);
    expect(find.text('1 with a note'), findsOneWidget);
    expect(find.textContaining('https://'), findsNothing);
    expect(find.text('Continue with 3 of 3 sources'), findsNothing);
  });
}
