// Verifies the source modal's insert actions (citation-only always available;
// quote+citation gated on a selection).
import 'package:doc_oct/src/domain/source.dart';
import 'package:doc_oct/src/presentation/editor/source_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const source = Source(
    url: 'https://example.com/a',
    title: 'A Study of Things',
    author: 'Smith, Jane',
    publishedYear: '2020',
    publisher: 'Example Press',
    fullContent: 'Findings show that things happen for reasons.',
  );

  Widget host(void Function(String) onInsert) => MaterialApp(
    home: Scaffold(
      body: SourceModal(
        source: source,
        inText: '(Smith, 2020)',
        humanize: (t) async => t,
        canHumanize: false, // no humanize toggle → shows raw content
        onInsert: onInsert,
      ),
    ),
  );

  testWidgets('citation-only insert emits the in-text mark', (t) async {
    String? inserted;
    await t.pumpWidget(host((s) => inserted = s));
    await t.pumpAndSettle();

    await t.tap(find.text('Insert citation only'));
    await t.pump();
    expect(inserted, '(Smith, 2020)');
  });

  testWidgets('quote+citation is disabled until text is selected', (t) async {
    await t.pumpWidget(host((_) {}));
    await t.pumpAndSettle();

    final button = t.widget<FilledButton>(
      find.ancestor(
        of: find.text('Insert quote + citation'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull); // disabled with no selection
  });

  group('Auto Humanize follows the panel, per-source override', () {
    late List<String> calls;
    late List<bool> changes;
    late List<String> reported;

    setUp(() {
      calls = [];
      changes = [];
      reported = [];
    });

    Widget modal({bool initial = false, String? cached}) => MaterialApp(
      home: Scaffold(
        body: SourceModal(
          source: source,
          inText: '(Smith, 2020)',
          humanize: (t) async {
            calls.add(t);
            return 'Humanized text.';
          },
          canHumanize: true,
          initialHumanize: initial,
          cachedHumanized: cached,
          onHumanizeChanged: changes.add,
          onHumanized: reported.add,
          onInsert: (_) {},
        ),
      ),
    );

    bool switchOn(WidgetTester t) =>
        t.widget<Switch>(find.byType(Switch)).value;

    testWidgets('panel off → modal off, raw content, no humanize call', (
      t,
    ) async {
      await t.pumpWidget(modal());
      await t.pumpAndSettle();
      expect(switchOn(t), isFalse);
      expect(calls, isEmpty);
      expect(find.text(source.fullContent), findsOneWidget);
    });

    testWidgets('panel on → modal humanizes and reports it for this source', (
      t,
    ) async {
      await t.pumpWidget(modal(initial: true));
      await t.pumpAndSettle();
      expect(switchOn(t), isTrue);
      expect(calls, hasLength(1));
      expect(find.text('Humanized text.'), findsOneWidget);
      expect(reported, ['Humanized text.']);
      expect(changes, isEmpty, reason: 'no per-source override');
    });

    testWidgets('turning it on in the modal is reported as this source only', (
      t,
    ) async {
      await t.pumpWidget(modal());
      await t.pumpAndSettle();
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      expect(changes, [true]);
      expect(calls, hasLength(1));
      expect(find.text('Humanized text.'), findsOneWidget);
    });

    testWidgets('reopening reuses this source\'s humanized text', (t) async {
      await t.pumpWidget(modal(initial: true, cached: 'Earlier result.'));
      await t.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.text('Earlier result.'), findsOneWidget);
    });
  });
}
