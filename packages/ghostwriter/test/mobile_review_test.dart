import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwriter/src/data/gw_api.dart';
import 'package:ghostwriter/src/mobile/mobile_review.dart';
import 'package:ghostwriter/src/session/gw_session.dart';
import 'package:ghostwriter/src/session/timeline.dart';

import 'fake_server.dart';

void main() {
  test('a revision event becomes a card to review', () {
    final timeline = RunTimeline();
    timeline.apply({
      'seq': 1,
      'type': 'revision',
      'versionId': 'v1',
      'wordsBefore': 820,
      'wordsAfter': 640,
    });
    final item = timeline.items.single as RevisionItem;
    expect(
      (item.versionId, item.wordsBefore, item.wordsAfter),
      ('v1', 820, 640),
    );
  });

  group('the review', () {
    late FakeServer server;
    RevisionReview? result;
    var popped = false;

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      server = FakeServer(
        responses: {
          'GET /v1/projects/p1/versions/v1': {
            'id': 'v1',
            'body': 'Seas are rising fast.\n\nCities must plan.',
          },
          'GET /v1/projects/p1/document': {
            'body': 'Seas are rising quickly.\n\nCities must plan.',
          },
        },
      );
      final api = GwApi(baseUrl: 'http://api', client: server.client);
      result = null;
      popped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await openGwReview(
                  context,
                  api: api,
                  projectId: 'p1',
                  versionId: 'v1',
                );
                popped = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows what changed, and Keep keeps it', (tester) async {
      await open(tester);
      expect(find.text('+1 words'), findsOneWidget);
      expect(find.text('−1 words'), findsOneWidget);
      expect(find.text('1 paragraph changed'), findsOneWidget);
      // Only the changed paragraph, until all are asked for.
      expect(find.text('¶ 1'), findsOneWidget);
      expect(find.text('¶ 2'), findsNothing);
      await tester.tap(find.text('Show all'));
      await tester.pump();
      expect(find.text('¶ 2'), findsOneWidget);

      await tester.tap(find.text('Keep changes'));
      await tester.pumpAndSettle();
      expect(popped, isTrue);
      expect(result, RevisionReview.kept);
      expect(server.calls, isNot(contains(contains('/restore'))));
    });

    testWidgets('Undo puts the old version back, once confirmed', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Undo changes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(server.calls, isNot(contains(contains('/restore'))));

      await tester.tap(find.text('Undo changes'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Undo'));
      await tester.pumpAndSettle();
      expect(
        server.calls,
        contains('POST /v1/projects/p1/versions/v1/restore'),
      );
      expect(result, RevisionReview.undone);
    });
  });
}
