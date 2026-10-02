import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwriter/src/mobile/mobile_chat.dart';
import 'package:ghostwriter/src/session/gw_session.dart';

import 'fake_server.dart';

void main() {
  late FakeServer server;
  late GwSession session;
  late TextEditingController composer;
  late int editorOpens;

  setUp(() {
    server = FakeServer();
    session = server.session();
    composer = TextEditingController();
    editorOpens = 0;
  });

  tearDown(() => session.dispose());

  /// Starts a run and shows the chat, connected and empty.
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GhostWriterMobileChat(
            session: session,
            composer: composer,
            onOpenEditor: () => editorOpens++,
          ),
        ),
      ),
    );
    final started = session.start('An essay on tides');
    await tester.pump();
    await started;
    await tester.pump();
  }

  /// Sends events and lets the list settle.
  Future<void> send(
    WidgetTester tester,
    List<Map<String, dynamic>> events,
  ) async {
    for (final e in events) {
      server.send(e);
    }
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  }

  testWidgets('shows the brief and a typing indicator before any step', (
    tester,
  ) async {
    await open(tester);
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('An essay on tides'), findsWidgets);
    expect(find.bySemanticsLabel('GhostWriter is writing'), findsOneWidget);
    expect(find.text('Starting').evaluate().isEmpty, isTrue);
  });

  testWidgets('a step runs, then a focus question is answered with chips', (
    tester,
  ) async {
    await open(tester);
    await send(tester, [
      ev(1, 'user_message', {'text': 'An essay on tides'}),
      ev(2, 'step_start', {
        'stepId': 's1',
        'tool': 'plan_essay',
        'title': 'Planning the essay',
      }),
    ]);
    expect(find.text('Planning the essay'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await send(tester, [
      ev(3, 'step_done', {'stepId': 's1', 'summary': 'Thesis drafted.'}),
      ev(4, 'question', {
        'field': 'essayFocus',
        'question': 'What should it focus on?',
        'inputType': 'multiselect',
        'allowCustom': true,
        'options': [
          {'label': 'Economy', 'value': 'Economy'},
          {'label': 'Policy', 'value': 'Policy'},
        ],
      }),
    ]);
    expect(find.text('Thesis drafted.'), findsOneWidget);
    expect(find.text('Your turn'), findsOneWidget);
    expect(find.text('Pick at least one'), findsOneWidget);

    await tester.tap(find.text('Policy'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Continue with 1'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(server.calls.last, endsWith('/answer'));
    expect(server.bodies.last, {
      'field': 'essayFocus',
      'value': ['Policy'],
    });

    // The server confirms; the card folds to the answer.
    await send(tester, [
      ev(5, 'question_answered', {
        'field': 'essayFocus',
        'value': ['Policy'],
      }),
    ]);
    expect(find.text('Pick at least one'), findsNothing);
    expect(find.text('GhostWriter needs your input'), findsNothing);
  });

  testWidgets('a number question answers from its chips', (tester) async {
    await open(tester);
    await send(tester, [
      ev(1, 'question', {
        'field': 'wordCount',
        'question': 'How long?',
        'inputType': 'number',
        'suggestions': ['500', '800'],
        'allowCustom': true,
      }),
    ]);

    await tester.tap(find.text('800'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(server.bodies.last, {'field': 'wordCount', 'value': 800});
  });

  testWidgets('sources and writing bring in the corner pills', (tester) async {
    await open(tester);
    expect(find.byTooltip('Open Editor'), findsNothing);

    await send(tester, [
      ev(1, 'sources_ready', {
        'count': 2,
        'sources': [
          {'url': 'https://noaa.example', 'title': 'Sea level rise'},
        ],
      }),
    ]);
    expect(find.byTooltip('Sources · 2'), findsOneWidget);
    expect(find.byTooltip('Open Editor'), findsNothing);

    await send(tester, [
      ev(2, 'writing_started', {'targetWords': 800}),
      ev(3, 'write_progress', {'words': 320, 'targetWords': 800}),
    ]);
    expect(find.byTooltip('Open Editor'), findsOneWidget);
    expect(find.text('Writing your essay'), findsOneWidget);
    expect(find.text('320 / 800 words'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Writing now')), findsOneWidget);

    await tester.tap(find.byTooltip('Open Editor'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(editorOpens, 1);

    // Sources opens the details sheet.
    await tester.tap(find.byTooltip('Sources · 2'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Sea level rise'), findsOneWidget);
  });

  testWidgets('a finished run offers the editor and invites changes', (
    tester,
  ) async {
    await open(tester);
    await send(tester, [
      ev(1, 'writing_started', {'targetWords': 500}),
      ev(2, 'write_progress', {'words': 520, 'targetWords': 500}),
      ev(3, 'done'),
    ]);

    expect(find.text('Finished'), findsOneWidget);
    expect(find.text('Essay written'), findsOneWidget);
    expect(find.text('Your essay is ready.'), findsOneWidget);
    expect(find.text('Ask for a change to your essay'), findsOneWidget);
    expect(find.byTooltip('Stop'), findsNothing);

    await tester.tap(find.text('Proceed to Editor'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(editorOpens, 1);
  });

  testWidgets('Stop cancels the run', (tester) async {
    await open(tester);
    await send(tester, [
      ev(1, 'user_message', {'text': 'An essay on tides'}),
    ]);

    await tester.tap(find.byTooltip('Stop'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(server.calls.last, endsWith('/cancel'));

    await send(tester, [ev(2, 'cancelled')]);
    expect(find.text('Stopped'), findsOneWidget);
    expect(find.text('Stopped.'), findsOneWidget);
  });
}
