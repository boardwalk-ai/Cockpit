import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:octo_notes/src/presentation/notebooks/notebooks_page.dart';

late GoRouter _router;

Widget _app([String at = '/notes/notebooks']) {
  _router = GoRouter(
    initialLocation: at,
    routes: [
      GoRoute(path: '/notes', builder: (_, _) => const Scaffold(body: Text('HOME')), routes: [
        GoRoute(path: 'notebooks', builder: (_, s) => NotebooksPage(manage: s.uri.queryParameters['manage'])),
        GoRoute(path: 'notebook', builder: (_, s) => Scaffold(body: Text('READER ${s.uri.query}'))),
        GoRoute(path: 'session', builder: (_, s) => Scaffold(body: Text('SESSION ${s.uri.query}'))),
        GoRoute(path: 'finalize', builder: (_, s) => Scaffold(body: Text('FINALIZE ${s.uri.query}'))),
        GoRoute(path: 'final', builder: (_, s) => Scaffold(body: Text('FINAL ${s.uri.query}'))),
      ]),
    ],
  );
  return ProviderScope(child: MaterialApp.router(routerConfig: _router));
}

Future<void> _settle(WidgetTester tester, [int ms = 1600]) async {
  for (var t = 0; t < ms; t += 100) {
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

  setUp(() {});

  Future<void> phone(WidgetTester tester, [String at = '/notes/notebooks']) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(at));
    await _settle(tester, 800);
  }

  testWidgets('shelf of notebooks, search and filters', (tester) async {
    await phone(tester);
    expect(find.text('Notebooks'), findsOneWidget);
    expect(find.text('Biology 101'), findsWidgets);
    expect(find.text('New session'), findsOneWidget);
    expect(find.text('8 pages'), findsOneWidget);

    await tester.tap(find.text('Final'));
    await _settle(tester, 600);
    expect(find.text('5 pages'), findsOneWidget);
    await tester.tap(find.text('All'));
    await _settle(tester, 600);

    // Searching glides the shelf to the notebook with the matches.
    await tester.enterText(find.byType(TextField), 'photo');
    await _settle(tester, 900);
    expect(find.text('PAGES FOUND'), findsOneWidget);
    expect(find.text('2 pages'), findsOneWidget);
    expect(find.text('2 found'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'silk');
    await _settle(tester, 1200);
    expect(find.text('1 found'), findsOneWidget);
    expect(find.text('HIST 120'), findsOneWidget);
    final pc = tester.widget<PageView>(find.byType(PageView)).controller!;
    expect(pc.page!.round(), 2, reason: 'World History is the third notebook');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the cover opens the notebook to read', (tester) async {
    await phone(tester);
    // The centred cover is Biology 101.
    await tester.tap(find.text('BIO 101'));
    await _settle(tester, 800);
    expect(find.text('READER course=bio'), findsOneWidget);
  });

  testWidgets('managing a notebook lists its lectures; a live one opens live', (tester) async {
    await phone(tester, '/notes/notebooks?manage=bio');
    await _settle(tester, 2000);
    expect(find.text('NOTEBOOK'), findsOneWidget);
    expect(find.text('New page in Biology 101'), findsOneWidget);
    expect(find.text('Enzymes'), findsOneWidget);
    expect(find.text('Integration by parts'), findsNothing, reason: 'Calculus pages stay in their own notebook');

    // A live lecture reopens without the mic.
    await tester.tap(find.text('Cellular respiration'));
    await _settle(tester, 600);
    expect(find.textContaining('SESSION id=1&role=solo&record=0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long-press a page for rename, move and delete with undo', (tester) async {
    await phone(tester);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await _settle(tester, 400);
    await tester.longPress(find.text('Integration by parts'));
    await _settle(tester, 600);
    expect(find.text('Move to another notebook'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await _settle(tester, 600);
    expect(find.text('Integration by parts'), findsNothing);
    await tester.tap(find.text('Undo'));
    await _settle(tester, 600);
    expect(find.text('Integration by parts'), findsOneWidget);
    // Let the five-second delete timer run out (it was undone).
    await _settle(tester, 5200);
    expect(find.text('Integration by parts'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an ended lecture opens in its notebook', (tester) async {
    await phone(tester);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await _settle(tester, 400);
    await tester.tap(find.text('Integration by parts'));
    await _settle(tester, 600);
    expect(find.textContaining('READER course=calc&session=2'), findsOneWidget);
  });
}
