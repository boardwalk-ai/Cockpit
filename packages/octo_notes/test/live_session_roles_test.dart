import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:octo_notes/src/application/session_recorder.dart';
import 'package:octo_notes/src/domain/positions.dart';
import 'package:octo_notes/src/presentation/live/live_session_hub_page.dart';
import 'package:octo_notes/src/presentation/magic_pencil/magic_pencil_workspace.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(SessionRole role) => ProviderScope(
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/notes/session',
          routes: [
            GoRoute(path: '/notes', builder: (_, _) => const Scaffold(body: Text('HOME')), routes: [
              GoRoute(path: 'session', builder: (_, _) => LiveSessionHubPage(role: role)),
              GoRoute(path: 'finalize', builder: (_, _) => const Scaffold(body: Text('FINALIZE'))),
            ]),
          ],
        ),
      ),
    );

Future<void> _open(WidgetTester tester, SessionRole role, {Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(_app(role));
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  setUpAll(() async {
    final font = FontLoader('packages/cockpit_ui/PlusJakartaSans');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('packages/cockpit_ui/assets/fonts/PlusJakartaSans-$w.ttf'));
    }
    await font.load();
  });

  test('block positions come after the last one, like the server', () {
    expect(positionAfter(null), 'V');
    expect(positionAfter('V').compareTo('V'), greaterThan(0));
    final k = positionAfter('zzz');
    expect(k.compareTo('zzz'), greaterThan(0));
    expect(k.endsWith('0'), isFalse);
    var last = 'a';
    for (var i = 0; i < 200; i++) {
      final next = positionAfter(last);
      expect(next.compareTo(last), greaterThan(0), reason: '$next after $last');
      last = next;
    }
    // Between two keys, repeatedly (inserting in the middle), like the server.
    for (final (lo, hi) in [('V', 'W'), ('a', 'a1'), ('zz', 'zzV'), ('01', '02')]) {
      var a = lo;
      for (var i = 0; i < 50; i++) {
        final m = positionBetween(a, hi);
        expect(m.compareTo(a) > 0 && m.compareTo(hi) < 0, isTrue, reason: '$a < $m < $hi');
        expect(m.endsWith('0'), isFalse);
        a = m;
      }
    }
    expect(positionBetween(null, 'V').compareTo('V'), lessThan(0));
  });

  test('chunks are 16 kHz mono WAV', () {
    final pcm = Uint8List(32000); // one second
    final w = SessionRecorder.wav(pcm, 16000);
    final h = ByteData.sublistView(w);
    expect(String.fromCharCodes(w.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(w.sublist(8, 12)), 'WAVE');
    expect(h.getUint16(22, Endian.little), 1);
    expect(h.getUint32(24, Endian.little), 16000);
    expect(h.getUint32(40, Endian.little), 32000);
    expect(w.length, 44 + 32000);
  });

  testWidgets('phone, solo: this phone records and shows the transcript and tools', (tester) async {
    await _open(tester, SessionRole.solo);
    expect(find.text('Recording on this phone'), findsOneWidget);
    expect(find.text('Live transcript'), findsOneWidget);
    expect(find.textContaining('Glycolysis'), findsWidgets);
    for (final t in ['Mark', 'Pencil', 'Board', 'Type']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone, receiver: the other phone records; transcript fills the screen', (tester) async {
    await _open(tester, SessionRole.receiver);
    expect(find.text('Your phone is recording'), findsOneWidget);
    expect(find.text('Recording on this phone'), findsNothing);
    expect(find.text('Live transcript'), findsOneWidget);
    expect(find.text('Mark'), findsOneWidget);

    // Pencil upright asks to turn the phone; sideways it's the canvas with rails.
    await tester.tap(find.text('Pencil'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Turn your phone to draw'), findsOneWidget);
    expect(find.textContaining('anyway'), findsNothing);
    tester.view.physicalSize = const Size(844, 390);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(PhoneMagicPencil), findsOneWidget);
    expect(find.byTooltip('Undo'), findsOneWidget);
    expect(find.byTooltip('Add page'), findsOneWidget);
    await tester.tap(find.byTooltip('Back').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(PhoneMagicPencil), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone, typewriter: blocks, a quote from the lecture, a heading', (tester) async {
    await _open(tester, SessionRole.solo);
    await tester.tap(find.text('Type'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Cellular respiration'), findsOneWidget);
    expect(find.byTooltip('Heading'), findsOneWidget);
    expect(find.text('Expand'), findsOneWidget);

    // Tap the transcript line: it lands as a quote with its time.
    final quotes = find.byType(TextField).evaluate().length;
    await tester.tap(find.textContaining('tap to add'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TextField).evaluate().length, quotes + 2, reason: 'the quote and a line to keep typing');

    // Type in the new line, then make it a heading.
    await tester.enterText(find.byType(TextField).at(quotes + 1), 'Krebs cycle');
    await tester.tap(find.byTooltip('Heading'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Krebs cycle'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone, recorder: only the mic, no transcript or tools', (tester) async {
    await _open(tester, SessionRole.recorder);
    expect(find.text('Recording'), findsOneWidget);
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Mark'), findsOneWidget);
    expect(find.text('Live transcript'), findsNothing);
    expect(find.text('Pencil'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('computer, receiver: the hub says the phone records', (tester) async {
    await _open(tester, SessionRole.receiver, size: const Size(1281, 720));
    expect(find.text('Your phone is recording'), findsOneWidget);
    expect(find.text('Typewriter'), findsOneWidget);
    expect(find.text('Magic Pencil'), findsOneWidget);
    expect(find.text('Finalize'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
