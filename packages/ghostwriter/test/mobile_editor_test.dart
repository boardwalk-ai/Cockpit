import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwriter/src/data/gw_api.dart';
import 'package:ghostwriter/src/mobile/mobile_editor.dart';
import 'package:ghostwriter/src/session/doc_session.dart';

import 'fake_server.dart';

void main() {
  late FakeServer server;
  late GwDocumentSession doc;

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    server = FakeServer(
      responses: {
        'GET /v1/projects/p1/versions': {
          'versions': [
            {
              'id': 'v1',
              'rev': 2,
              'reason': 'user_save',
              'createdAt': DateTime.now().toUtc().toIso8601String(),
              'title': 'Rising Tides',
              'preview': 'The draft as GhostWriter left it.',
              'wordCount': 812,
            },
          ],
        },
      },
    );
    final api = GwApi(baseUrl: 'http://api', client: server.client);
    doc = GwDocumentSession(api, 'p1');
    addTearDown(doc.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: GwEditorPage(api: api, projectId: 'p1', session: doc),
      ),
    );
    await tester.pump();
  }

  Future<void> send(WidgetTester tester, Map<String, dynamic> event) async {
    server.send(event);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  }

  Map<String, dynamic> snapshot({required bool locked}) => {
    'type': 'snapshot',
    'rev': 3,
    'locked': locked,
    'title': 'Rising Tides',
    'fields': {'studentName': 'Ada Lovelace'},
    'body': locked ? '' : 'Seas are rising.\n\nCities adapt.',
    'bibliography': 'Sweet, W. (2022).',
  };

  testWidgets('read-only while GhostWriter writes, with live text', (
    tester,
  ) async {
    await open(tester);
    await send(tester, snapshot(locked: true));

    expect(find.text('Read-only while GhostWriter writes.'), findsOneWidget);
    expect(find.byTooltip('Bold'), findsNothing);
    expect(find.byTooltip('History'), findsNothing);

    await send(tester, {'type': 'delta', 'text': 'Seas are rising.'});
    expect(find.text('Writing · 3 words'), findsOneWidget);
  });

  testWidgets('editable after: toolbar, details, history', (tester) async {
    await open(tester);
    await send(tester, snapshot(locked: false));

    expect(find.text('Saved · 5 words'), findsOneWidget);
    expect(find.byTooltip('Bold'), findsOneWidget);
    expect(find.text('Rising Tides'), findsOneWidget);
    expect(find.text('Sweet, W. (2022).'), findsOneWidget);

    // Title page details fold out.
    await tester.tap(find.text('Title page details'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Ada Lovelace'), findsOneWidget);

    // History lists the saved versions.
    await tester.tap(find.byTooltip('History'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Before your edits'), findsOneWidget);
    expect(find.text('just now · 812 words'), findsOneWidget);
  });
}
