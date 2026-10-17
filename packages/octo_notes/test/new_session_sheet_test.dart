import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:octo_notes/src/domain/pairing.dart';
import 'package:octo_notes/src/presentation/home/octo_notes_home_page.dart';
import 'package:octo_notes/src/presentation/new_session/join_recorder_page.dart';
import 'package:octo_notes/src/presentation/new_session/new_session_sheet.dart';
import 'package:octo_notes/src/presentation/new_session/pairing_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app() => ProviderScope(
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/notes',
          routes: [
            GoRoute(path: '/notes', builder: (_, _) => const OctoNotesHomePage(), routes: [
              GoRoute(path: 'join', builder: (_, _) => const JoinRecorderPage()),
              GoRoute(path: 'session', builder: (_, _) => const Scaffold(body: Text('SESSION'))),
            ]),
          ],
        ),
      ),
    );

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(_app());
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  // The real face, so widths are what a phone draws (not the test font).
  setUpAll(() async {
    final font = FontLoader('packages/cockpit_ui/PlusJakartaSans');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('packages/cockpit_ui/assets/fonts/PlusJakartaSans-$w.ttf'));
    }
    await font.load();
  });

  test('a scanned QR gives the secret only when it is ours', () {
    const s = '0123456789abcdef0123456789abcdef';
    expect(Pairing.secretFromQr('octonotes-pair:$s'), s);
    expect(Pairing.secretFromQr(' octonotes-pair:$s \n'), s);
    expect(Pairing.secretFromQr('https://example.com'), isNull);
    expect(Pairing.secretFromQr('octonotes-pair:short'), isNull);
    const p = Pairing(id: 'x', status: 'waiting', code: '482913', secret: s);
    expect(p.prettyCode, '482 913');
    expect(p.qrText, 'octonotes-pair:$s');
  });

  testWidgets('phone: New session opens the sheet, not the desktop modal', (tester) async {
    await _phone(tester);
    await tester.tap(find.text('New Session'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('New session'), findsOneWidget);
    expect(find.text('Use last settings'), findsOneWidget);
    expect(find.text('Record on'.toUpperCase()), findsOneWidget);
    expect(find.text('This phone'), findsOneWidget);
    expect(find.text('Another phone'), findsOneWidget);
    // The title is filled in from the course and the time.
    expect(find.textContaining('Biology 101 ·'), findsOneWidget);

    // More options fold out.
    expect(find.text('Live transcription'), findsNothing);
    await tester.tap(find.textContaining('More options'));
    await tester.pump();
    final sheetList = find.descendant(of: find.byType(NewSessionSheet), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Save in The Deck'), 200, scrollable: sheetList);
    await tester.scrollUntilVisible(find.text('Live transcription'), 200, scrollable: sheetList);
    expect(find.text('Live transcription'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Another phone'), -200, scrollable: sheetList);

    // Another phone without a server: says so; Start asks to pair first.
    await tester.tap(find.text('Another phone'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Pairing needs the OctoNotes server'), findsOneWidget);
    await tester.tap(find.text('Start session'));
    await tester.pump();
    expect(find.text('Pair the other phone first, or record on this phone.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('computer: the modal records here or on my phone (paired first)', (tester) async {
    tester.view.physicalSize = const Size(1281, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('New Session').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('This computer'), findsOneWidget);
    expect(find.text("Records with this computer's microphone."), findsOneWidget);
    await tester.tap(find.text('My phone'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Pairing needs the OctoNotes server'), findsOneWidget);
    await tester.tap(find.text('Start Session'));
    await tester.pump();
    expect(find.text('Pair your phone first, or record with this computer.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone: Join as recorder takes the code on the pad', (tester) async {
    await _phone(tester);
    await tester.tap(find.text('Join as recorder'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Scan QR'), findsOneWidget);
    expect(find.byType(TextField), findsNothing, reason: 'own pad, no system keyboard');

    // Six digits on the pad pair by themselves (no server here: says so).
    for (final d in '482913'.split('')) {
      await tester.tap(find.descendant(of: find.byType(NumberPad), matching: find.text(d)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Joining needs the OctoNotes server'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CodeBoxes), findsOneWidget);
    expect(tester.takeException(), isNull);
  });


  testWidgets('pairing animations run on a phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          const RadarRings(size: 220, child: RollingCode(code: '482913')),
          CountdownRing(expiresAt: DateTime.now().add(const Duration(minutes: 9))),
          const SuccessCheck(size: 70),
          const CodeBoxes(value: '482', state: CodeBoxesState.wrong),
        ]),
      ),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('9:59'), findsNothing);
    expect(find.textContaining('8:5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
