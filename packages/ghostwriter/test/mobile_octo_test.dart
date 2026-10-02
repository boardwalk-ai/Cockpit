import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_server.dart';
import 'support.dart';

/// The background never stops animating, so `pumpAndSettle` cannot be used.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  Future<void> open(WidgetTester tester, FakeServer server) async {
    await tester.pumpWidget(GhostWriterApp(session: server.session()));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byTooltip('Ask Octo'));
    await settle(tester);
  }

  testWidgets('the header icon opens Ask Octo and it answers', (tester) async {
    final server = FakeServer(
      responses: {
        'POST /v1/octo/ask': {
          'answer': 'Tap the Open Editor pill at the top right.',
        },
      },
    );
    await open(tester, server);

    expect(find.text('Ask Octo'), findsOneWidget);
    expect(find.text('TRY ASKING'), findsOneWidget);

    // Nothing to send yet.
    await tester.tap(find.byTooltip('Ask'));
    await settle(tester);
    expect(server.calls, isNot(contains('POST /v1/octo/ask')));

    await tester.enterText(
      find.widgetWithText(TextField, 'Ask about the app...'),
      '  Where is my essay?  ',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Ask'));
    await settle(tester);

    expect(server.bodies.last, {'question': 'Where is my essay?'});
    expect(find.text('Where is my essay?'), findsOneWidget);
    expect(
      find.text('Tap the Open Editor pill at the top right.'),
      findsOneWidget,
    );
    expect(find.text('TRY ASKING'), findsNothing);
  });

  testWidgets('a suggestion is asked with one tap', (tester) async {
    final server = FakeServer(
      responses: {
        'POST /v1/octo/ask': {'answer': 'Say what to change in the chat.'},
      },
    );
    await open(tester, server);

    await tester.tap(find.text('How do I change the essay?'));
    await settle(tester);

    expect(server.bodies.last, {'question': 'How do I change the essay?'});
    expect(find.text('Say what to change in the chat.'), findsOneWidget);
  });

  testWidgets('a failure is said plainly and another question can be asked', (
    tester,
  ) async {
    final server = FakeServer(
      responses: {
        'POST /v1/octo/ask': const FakeReply(503, {
          'error': 'Octo cannot answer right now.',
        }),
      },
    );
    await open(tester, server);

    await tester.tap(find.text('Where is my essay?'));
    await settle(tester);
    expect(find.textContaining('cannot answer right now'), findsOneWidget);

    server.responses['POST /v1/octo/ask'] = {'answer': 'In the editor.'};
    await tester.enterText(find.byType(TextField).last, 'Where is it?');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await settle(tester);
    expect(find.text('In the editor.'), findsOneWidget);
    expect(find.textContaining('cannot answer right now'), findsNothing);
  });
}
