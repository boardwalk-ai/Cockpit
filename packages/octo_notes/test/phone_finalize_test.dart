import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:octo_notes/src/presentation/live/phone_finalize.dart';
import 'package:octo_notes/src/presentation/live/session_finalize_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _open(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: SessionFinalizePage())));
}

Future<void> _wait(WidgetTester tester, Duration d) async {
  for (var t = Duration.zero; t < d; t += const Duration(milliseconds: 100)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    final font = FontLoader('packages/cockpit_ui/PlusJakartaSans');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('packages/cockpit_ui/assets/fonts/PlusJakartaSans-$w.ttf'));
    }
    await font.load();
  });

  testWidgets('phone: wrap up, review topics, hold to finalize, done', (tester) async {
    await _open(tester, const Size(390, 844));
    expect(find.byType(PhoneFinalize), findsOneWidget);
    expect(find.text('Wrapping up\nyour lecture'), findsOneWidget);
    expect(find.text('Recording stopped'), findsOneWidget);

    await _wait(tester, const Duration(seconds: 5));
    expect(find.text('Glycolysis'), findsOneWidget);
    expect(find.text('Hold to finalize · 4 topics'), findsOneWidget);
    expect(find.textContaining('Refresh'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget, reason: 'the title, no boxed fields');

    // Leave one topic out.
    await tester.tap(find.bySemanticsLabel('Include in notes').first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('3 of 4 in your notes'), findsOneWidget);

    // A tap doesn't finalize; holding does.
    final hold = find.text('Hold to finalize · 3 topics');
    await tester.tap(hold);
    await _wait(tester, const Duration(milliseconds: 600));
    expect(find.text('Your notes\nare ready'), findsNothing);
    final g = await tester.startGesture(tester.getCenter(hold));
    await _wait(tester, const Duration(milliseconds: 1500));
    await g.up();
    await _wait(tester, const Duration(seconds: 2));
    expect(find.text('Your notes\nare ready'), findsOneWidget);
    expect(find.text('Send to Study Studio'), findsOneWidget);
    expect(find.text('Download PDF'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('computer: the desktop finalize stays as it was', (tester) async {
    await _open(tester, const Size(1281, 720));
    await tester.pump();
    expect(find.byType(PhoneFinalize), findsNothing);
    expect(find.text('Download PDF'), findsOneWidget);
  });
}
