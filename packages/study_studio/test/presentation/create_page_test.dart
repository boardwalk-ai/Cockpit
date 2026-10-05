import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/domain/entities/source.dart';
import 'package:study_studio/src/presentation/mobile/study_create_mobile.dart';

import 'home_page_test.dart' show phone, viewport;

List<SmPickedFile> picked(int count) => [
  for (var i = 0; i < count; i++)
    SmPickedFile(
      name: 'Notes_$i.pdf',
      type: SourceFileType.pdf,
      bytes: Uint8List(2048),
    ),
];

void main() {
  late TextEditingController name;
  setUp(() => name = TextEditingController());
  tearDown(() => name.dispose());

  Future<void> show(
    WidgetTester tester,
    List<SmPickedFile> files, {
    VoidCallback? onBuild,
    void Function(int)? onRemove,
  }) async {
    viewport(tester, phone);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: StudyCreateMobile(
          files: files,
          name: name,
          credits: 56085,
          onAdd: () {},
          onRemove: onRemove ?? (_) {},
          onBuild: onBuild ?? () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('empty: an add tile, Build waits for a file', (tester) async {
    var built = false;
    await show(tester, const [], onBuild: () => built = true);
    expect(find.text('Drop in your notes.\nWe’ll build the rest.'), findsOne);
    expect(find.text('Add notes, slides or photos'), findsOne);
    expect(find.text('Name your studio'), findsOne);
    await tester.tap(find.text('Build'));
    expect(built, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('two files: cards, a suggested name, Build works', (
    tester,
  ) async {
    var built = false;
    await show(tester, picked(2), onBuild: () => built = true);
    expect(find.text('Notes_0.pdf'), findsOne);
    expect(find.text('Notes_1.pdf'), findsOne);
    expect(find.text('Notes 0'), findsOne); // the name's hint
    expect(find.text('2 files · 4 KB'), findsOne);
    await tester.tap(find.text('Build'));
    expect(built, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('four files: a strip that scrolls sideways', (tester) async {
    await show(tester, picked(4));
    expect(find.byType(ListView), findsOne);
    expect(find.text('Notes_0.pdf'), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('eight files: one summary, a sheet to review and remove', (
    tester,
  ) async {
    final files = picked(8);
    await show(tester, files, onRemove: files.removeAt);
    final composer = tester.getRect(find.text('8 files'));
    expect(find.text('Notes_0.pdf'), findsNothing);
    await tester.tap(find.text('8 files'));
    await tester.pumpAndSettle();
    // The sheet's title, and the composer's line under it.
    expect(find.text('8 files · 16 KB'), findsNWidgets(2));
    expect(find.text('Notes_7.pdf'), findsOne);
    await tester.tap(find.bySemanticsLabel('Remove Notes_0.pdf'));
    await tester.pumpAndSettle();
    expect(find.text('7 files · 14 KB'), findsOne);
    expect(find.text('Notes_0.pdf'), findsNothing);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    // The composer kept its place.
    expect(composer.top, greaterThan(600));
    expect(tester.takeException(), isNull);
  });

  test('names come from the file', () {
    expect(smNameFromFile('Networks_ch4-final.pdf'), 'Networks ch4 final');
    expect(smTypeFor('a.PPTX'), SourceFileType.pptx);
    expect(smTypeFor('lecture.m4a'), SourceFileType.audio);
  });
}
