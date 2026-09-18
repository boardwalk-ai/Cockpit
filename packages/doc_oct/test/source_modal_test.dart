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
}
