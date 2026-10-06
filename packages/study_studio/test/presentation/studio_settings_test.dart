import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/domain/entities/flashcard.dart';
import 'package:study_studio/src/domain/entities/source.dart';
import 'package:study_studio/src/domain/entities/studio.dart';
import 'package:study_studio/src/domain/study_plan.dart';
import 'package:study_studio/src/presentation/mobile/studio_export.dart';
import 'package:study_studio/src/presentation/mobile/studio_ready_mobile.dart';
import 'package:study_studio/src/presentation/mobile/studio_settings_mobile.dart';
import 'package:study_studio/src/presentation/mobile/study_create_mobile.dart';
import 'package:study_studio/src/presentation/mobile/welcome_back_sheet.dart';

import 'home_page_test.dart' show phone, viewport;
import 'mastery_report_mobile_test.dart' show topic;

final now = DateTime(2026, 10, 7, 9);

Studio studioWith({List<Flashcard> cards = const []}) => Studio(
  id: 's1',
  title: 'Networks: midterm!',
  subject: '',
  createdAt: now,
  updatedAt: now,
  sourceFiles: const [
    SourceFile(id: 'f1', name: 'Lecture 5.pdf', type: SourceFileType.pdf),
  ],
  topics: [
    topic('cc', 'Congestion control', 0.3, cards: cards),
    topic('osi', 'OSI layers', 0.9),
  ],
);

Flashcard fc(String front, String back, {int reps = 0, DateTime? due}) =>
    Flashcard(
      id: front,
      topicId: 'cc',
      front: front,
      back: back,
      reps: reps,
      intervalDays: reps > 0 ? 1 : 0,
      dueDate: due,
    );

void main() {
  test('Anki export: one card a line, tabs and newlines flattened', () {
    final s = studioWith(
      cards: [fc('What\thalves?', 'The\nwindow'), fc(' ', 'skipped')],
    );
    final lines = ankiTsv(s).trim().split('\n');
    expect(lines.take(3), ['#separator:tab', '#html:false', '#tags column:3']);
    expect(lines.last, 'What halves?\tThe window\tNetworks-midterm::Congestion_control');
    expect(ankiCount(s), 1);
    expect(exportName(s), 'Networks-midterm');
  });

  testWidgets('study notes come out as a PDF', (tester) async {
    final bytes = await tester.runAsync(
      () => studyNotesPdf(studioWith(cards: [fc('Q', 'A')]), now: now),
    );
    expect(String.fromCharCodes(bytes!.take(4)), '%PDF');
  });

  test('welcome back: only after days away with something to say', () {
    final due = studioWith(cards: [fc('Q', 'A')]); // a new card is due
    expect(
      WelcomeBack.of(due, lastOpen: null, now: now),
      isNull,
      reason: 'first visit',
    );
    expect(
      WelcomeBack.of(
        due,
        lastOpen: now.subtract(const Duration(days: 1)),
        now: now,
      ),
      isNull,
    );
    final wb = WelcomeBack.of(
      due,
      lastOpen: now.subtract(const Duration(days: 4)),
      now: now,
      plan: PlanSettings(
        mode: PlanMode.exam,
        exam: now.add(const Duration(days: 10)),
      ),
    )!;
    expect(wb.away, 4);
    expect(wb.due, 1);
    expect(wb.examIn, 10);
    // Nothing due, nothing fading: no sheet.
    expect(
      WelcomeBack.of(
        studioWith(),
        lastOpen: now.subtract(const Duration(days: 9)),
        now: now,
      ),
      isNull,
    );
  });

  testWidgets('settings: rename, add a file, update, export, delete', (
    tester,
  ) async {
    viewport(tester, const Size(390, 1100));
    final renamed = <String>[];
    final updated = <List<SmPickedFile>>[];
    final exported = <String>[];
    var deleted = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: StudioSettingsMobile(
          studio: studioWith(cards: [fc('Q', 'A')]),
          onBack: () {},
          onRename: (t) async {
            renamed.add(t);
            return true;
          },
          onUpdate: updated.add,
          onExportNotes: () async => exported.add('notes'),
          onExportCards: () async => exported.add('cards'),
          onDelete: () => deleted = true,
          pickFiles: (_) async => [
            SmPickedFile(
              name: 'Lecture 6.pdf',
              type: SourceFileType.pdf,
              bytes: Uint8List(2048),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Lecture 5.pdf'), findsOne);

    await tester.enterText(find.byType(TextField), '  Networks final ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(renamed, ['Networks final']);
    expect(find.byIcon(Icons.check_circle_rounded), findsOne);
    await tester.pump(const Duration(seconds: 3));

    expect(find.textContaining('Update studio'), findsNothing);
    await tester.tap(find.text('Add files'));
    await tester.pumpAndSettle();
    expect(find.text('Lecture 6.pdf'), findsOne);
    await tester.tap(find.text('Update studio'));
    expect(updated.single.single.name, 'Lecture 6.pdf');

    await tester.tap(find.text('Study notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flashcards'));
    await tester.pumpAndSettle();
    expect(exported, ['notes', 'cards']);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.textContaining('Update studio'), findsNothing);

    await tester.ensureVisible(find.text('Delete studio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete studio'));
    expect(deleted, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ready: counts, then the first lesson', (tester) async {
    viewport(tester, phone);
    final started = <String>[];
    var looked = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: StudioReadyMobile(
          studio: studioWith(cards: [fc('Q', 'A'), fc('Q2', 'A2')]),
          builtIn: const Duration(seconds: 48),
          onStart: (t) => started.add(t.id),
          onLook: () => looked = true,
        ),
      ),
    );
    // The words keep turning round the stamp: no settling.
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Your studio\nis ready'), findsOne);
    expect(find.text('1 file · built in 48 s'), findsOne);
    expect(find.text('2'), findsWidgets); // topics and flashcards
    expect(find.text('Congestion control'), findsOne);
    await tester.tap(find.text('Start the first lesson'));
    expect(started, ['cc']);
    await tester.tap(find.text('Look around first'));
    expect(looked, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
