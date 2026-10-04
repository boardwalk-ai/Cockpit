import 'package:doc_oct/doc_oct.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwriter/src/export/gw_pdf.dart';
import 'package:ghostwriter/src/mobile/mobile_cards.dart';
import 'package:ghostwriter/src/session/timeline.dart';

void main() {
  test('the document style picks the layout; none is laid out like APA', () {
    expect(GwPdf.formatStyle('MLA'), FormatStyle.mla);
    expect(GwPdf.formatStyle('ieee'), FormatStyle.ieee);
    expect(GwPdf.formatStyle('none'), FormatStyle.apa);
    expect(GwPdf.today(DateTime(2026, 3, 4)), 'March 4, 2026');
  });

  testWidgets('a finished essay offers its PDF', (tester) async {
    var downloads = 0;
    Future<void> download() async => downloads++;
    Widget card(RunPhase phase, {bool wrote = true}) => MaterialApp(
      home: Scaffold(
        body: GwEndCard(
          end: EndItem(phase, wroteEssay: wrote),
          onOpenEditor: () {},
          onDownload: download,
        ),
      ),
    );

    await tester.pumpWidget(card(RunPhase.finished));
    expect(find.text('Download PDF'), findsOneWidget);
    await tester.tap(find.text('Download PDF'));
    await tester.pump();
    expect(downloads, 1);

    await tester.pumpWidget(card(RunPhase.cancelled));
    expect(find.text('Download PDF'), findsNothing);
  });
}
