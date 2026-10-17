import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:octo_notes/src/presentation/recommendations/final_notes_page.dart';
import 'package:octo_notes/src/presentation/recommendations/phone_final_notes.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('packages/cockpit_ui/PlusJakartaSans');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('packages/cockpit_ui/assets/fonts/PlusJakartaSans-$w.ttf'));
    }
    await font.load();
  });

  testWidgets('phone: read, switch topics, play a quote, send to Study Studio', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: FinalNotesPage())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(PhoneFinalNotes), findsOneWidget);
    expect(find.text('Cellular respiration'), findsOneWidget);
    expect(find.text('Final · version 1'), findsOneWidget);
    // The capsule names only the current topic.
    expect(find.text('Glycolysis'), findsNWidgets(2));
    expect(find.text('Krebs cycle'), findsOneWidget);

    await tester.tap(find.text('3').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Krebs cycle'), findsNWidgets(2), reason: 'scrolled there and the capsule follows');

    // A lecture quote opens the player.
    final page = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
    await tester.scrollUntilVisible(find.textContaining('Think of it as the bridge'), -150, scrollable: page);
    await tester.drag(page, const Offset(0, 200));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.textContaining('Think of it as the bridge'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('12:02'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Send to Study Studio'), 300, scrollable: page);
    expect(find.text('Study from this note'), findsOneWidget);
    expect(find.textContaining('flashcards'), findsNothing, reason: 'Study Studio decides what to build');
    await tester.tap(find.text('Send to Study Studio'));
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Opening Study Studio'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
