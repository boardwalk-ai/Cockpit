import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwriter/src/mobile/mobile_drawer.dart';
import 'package:ghostwriter/src/session/gw_session.dart';

void main() {
  const threads = [
    GwProject(
      id: 'p1',
      title: 'Coastal cities and tides',
      status: 'ready',
      wordCount: 812,
    ),
    GwProject(
      id: 'p2',
      title: 'History of the printing press',
      status: 'writing',
      wordCount: 0,
    ),
    GwProject(
      id: 'p3',
      title: 'Tidal energy explained',
      status: 'ready',
      wordCount: 640,
    ),
  ];

  late List<String> events;

  Future<void> openDrawer(
    WidgetTester tester, {
    List<GwProject>? withThreads,
  }) async {
    events = [];
    final scaffold = GlobalKey<ScaffoldState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          key: scaffold,
          drawer: GhostWriterMobileDrawer(
            projects: withThreads ?? threads,
            folders: const [GwFolder(id: 'f1', name: 'Geography')],
            loading: false,
            selectedId: 'p1',
            sessionName: 'GUEST',
            credits: 2067,
            onNewChat: () => events.add('new'),
            onOpenProject: (id) => events.add('open $id'),
            onRefresh: () async {},
          ),
        ),
      ),
    );

    scaffold.currentState!.openDrawer();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('lists folders, threads and the account', (tester) async {
    await openDrawer(tester);

    expect(find.text('Geography'), findsOneWidget);
    expect(find.text('Coastal cities and tides'), findsOneWidget);
    expect(find.text('History of the printing press'), findsOneWidget);
    expect(find.text('Guest'), findsOneWidget);
    expect(find.bySemanticsLabel('2067 OctoCredits'), findsOneWidget);
  });

  testWidgets('search filters threads by title', (tester) async {
    await openDrawer(tester);

    await tester.enterText(find.byType(TextField), 'tid');
    await tester.pump();

    expect(find.text('Coastal cities and tides'), findsOneWidget);
    expect(find.text('Tidal energy explained'), findsOneWidget);
    expect(find.text('History of the printing press'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();

    expect(find.text('No essays match'), findsOneWidget);
  });

  testWidgets('tapping a thread opens it and closes the drawer', (
    tester,
  ) async {
    await openDrawer(tester);

    await tester.enterText(find.byType(TextField), 'energy');
    await tester.pump();
    await tester.tap(find.text('Tidal energy explained'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(events, ['open p3']);
    expect(find.byType(GhostWriterMobileDrawer), findsNothing);
  });

  testWidgets('New chat starts over and closes the drawer', (tester) async {
    await openDrawer(tester);

    await tester.tap(find.text('New chat'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(events, ['new']);
    expect(find.byType(GhostWriterMobileDrawer), findsNothing);
  });

  testWidgets('shows an empty state with no threads', (tester) async {
    await openDrawer(tester, withThreads: const []);

    expect(find.text('No essays yet'), findsOneWidget);
  });
}
