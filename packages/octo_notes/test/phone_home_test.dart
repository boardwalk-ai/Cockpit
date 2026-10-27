import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:octo_notes/src/application/account_providers.dart';
import 'package:octo_notes/src/application/session_providers.dart';
import 'package:octo_notes/src/data/account/account_repository.dart';
import 'package:octo_notes/src/domain/account.dart';
import 'package:octo_notes/src/domain/notes_session.dart';
import 'package:octo_notes/src/presentation/home/octo_notes_home_page.dart';
import 'package:octo_notes/src/presentation/widgets/octo_widgets.dart';

NotesSession _s(String id, String title, String status) => NotesSession(
      id: id,
      title: title,
      status: status,
      workspaceMode: 'both',
      updatedAt: DateTime(2026, 10, 18),
      durationMs: 48 * 60000,
      startedAt: DateTime.now().subtract(const Duration(minutes: 3)),
    );

Widget _app(HomeData? home) => ProviderScope(
      overrides: [
        homeDataProvider.overrideWith((_) async => home),
        accountRepositoryProvider.overrideWithValue(
          InMemoryAccountRepository(NotesAccount.fromJson(const {'uid': 'u1', 'name': 'Dev Student', 'registered': true})),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(initialLocation: '/notes', routes: [
          GoRoute(path: '/settings', builder: (_, _) => const Scaffold(body: Text('SETTINGS'))),
          GoRoute(path: '/notes', builder: (_, _) => const OctoNotesHomePage(), routes: [
            GoRoute(path: 'session', builder: (_, s) => Scaffold(body: Text('SESSION ${s.uri.query}'))),
            GoRoute(path: 'finalize', builder: (_, s) => Scaffold(body: Text('FINALIZE ${s.uri.query}'))),
          ]),
        ]),
      ),
    );

Future<void> _pump(WidgetTester tester, HomeData? home) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(home));
  for (var i = 0; i < 10; i++) {
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

  testWidgets('no backend: start and join, and honest empty lines, no samples', (tester) async {
    await _pump(tester, null);
    expect(find.text('New Session'), findsOneWidget);
    expect(find.text('Join as recorder'), findsOneWidget);
    expect(find.text('LIVE'), findsNothing);
    expect(find.text('Your courses show up here as notebooks.'), findsOneWidget);
    expect(find.textContaining('Macroeconomics'), findsNothing);
    expect(find.byType(OctoThemeSwitcher), findsNothing, reason: 'the phone follows the app theme');
    expect(find.byType(Drawer), findsNothing);
    // The profile opens the app's settings.
    await tester.tap(find.text('D'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('SETTINGS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('live card, ready to finalize and recent pages from the server', (tester) async {
    await _pump(
      tester,
      HomeData(
        live: [_s('1', 'Cellular respiration', 'live')],
        continueSessions: [_s('2', 'Integration by parts', 'ended'), _s('9', 'Draft idea', 'draft')],
        recent: [_s('3', 'The Silk Road', 'finalized')],
      ),
    );
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('Cellular respiration'), findsOneWidget);
    expect(find.textContaining('03:0'), findsOneWidget, reason: 'clock since the start');
    expect(find.text('Integration by parts'), findsOneWidget);
    expect(find.text('Draft idea'), findsNothing, reason: 'only ended lectures wait to be finalized');
    await tester.drag(find.byType(ListView).first, const Offset(0, -400));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('The Silk Road'), findsOneWidget);
    await tester.ensureVisible(find.text('Integration by parts'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Integration by parts'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('FINALIZE id=2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
