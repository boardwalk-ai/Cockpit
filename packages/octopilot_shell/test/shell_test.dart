import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:octopilot_shell/octopilot_shell.dart';

class Harness {
  Harness({ShellAccount? account})
    : account = ValueNotifier(account),
      theme = ValueNotifier(ThemeMode.dark);

  final ValueNotifier<ShellAccount?> account;
  final ValueNotifier<ThemeMode> theme;
  final chat = DemoMainChat(wordDelay: const Duration(milliseconds: 10));
  final opened = <String>[];
  var deleted = 0;
  var aiSettings = 0;

  late final services = ShellServices(
    chat: chat,
    modules: const [
      ShellModuleEntry(
        id: 'ghostwriter',
        mode: ShellMode.create,
        title: 'GhostWriter',
        description: 'Essays with AI',
        icon: Icons.edit,
        path: '/ghostwriter',
      ),
      ShellModuleEntry(
        id: 'slides',
        mode: ShellMode.create,
        title: 'Slides',
        description: 'Decks',
        icon: Icons.slideshow,
      ),
      ShellModuleEntry(
        id: 'study_studio',
        mode: ShellMode.learn,
        title: 'Study Studio',
        description: 'Flashcards',
        icon: Icons.school,
      ),
    ],
    account: account,
    themeMode: theme,
    setThemeMode: (mode) => theme.value = mode,
    onAiSettings: (_) => aiSettings++,
    onSignOut: () async {},
    onDeleteAccount: (_) async => deleted++,
    openModule: (context, module) {
      opened.add(module.id);
      context.push(module.path!);
    },
  );

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      OctopilotShellApp(
        services: services,
        moduleRoutes: [
          GoRoute(
            path: '/ghostwriter',
            builder: (_, _) => const Scaffold(body: Text('GhostWriter here')),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }
}

const ada = ShellAccount(
  name: 'Ada Lovelace',
  email: 'ada@test',
  plan: 'Pro Monthly',
  credits: 12400,
);

void main() {
  testWidgets('home greets with the three modes', (tester) async {
    await Harness(account: ada).pump(tester);

    expect(find.text('What will you do today?'), findsOneWidget);
    for (final mode in ['Create', 'Learn', 'Organize']) {
      expect(find.text(mode), findsOneWidget);
    }
    expect(find.text('AL'), findsOneWidget, reason: 'the account initials');
    expect(find.text('Message Octopilot'), findsOneWidget);
  });

  testWidgets('a mode opens its library; modules open, soon ones say so', (
    tester,
  ) async {
    final h = Harness(account: ada);
    await h.pump(tester);

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Create library'), findsOneWidget);
    expect(find.text('GhostWriter'), findsOneWidget);
    expect(find.text('Slides'), findsOneWidget);
    expect(find.text('Soon'), findsOneWidget);
    expect(find.text('Study Studio'), findsNothing, reason: 'that is Learn');

    await tester.tap(find.text('Slides'));
    await tester.pump();
    expect(find.text('Slides is coming soon.'), findsOneWidget);

    await tester.tap(find.text('GhostWriter'));
    await tester.pumpAndSettle();
    expect(h.opened, ['ghostwriter']);
    expect(find.text('GhostWriter here'), findsOneWidget);

    // Back to the library, then home.
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(find.text('Create library'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('What will you do today?'), findsOneWidget);
  });

  testWidgets('a mode with nothing in it says so', (tester) async {
    await Harness().pump(tester);
    await tester.tap(find.text('Organize'));
    await tester.pumpAndSettle();
    expect(
      find.text('Nothing here yet. New tools are on the way.'),
      findsOneWidget,
    );
  });

  testWidgets('chatting streams a reply and keeps it in the history', (
    tester,
  ) async {
    final h = Harness(account: ada);
    await h.pump(tester);

    await tester.enterText(find.byType(TextField), 'How do I write an essay?');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(find.text('How do I write an essay?'), findsOneWidget);
    expect(find.text('What will you do today?'), findsNothing);
    expect(find.byTooltip('Stop'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.textContaining('pick GhostWriter'), findsOneWidget);
    expect(find.byTooltip('Send'), findsOneWidget);

    // The history has it; a new chat brings the modes back.
    await tester.tap(find.byTooltip('Chats'));
    await tester.pumpAndSettle();
    expect(find.text('How do I write an essay?'), findsNWidgets(2));
    await tester.tap(find.byTooltip('New chat').last);
    await tester.pumpAndSettle();
    expect(find.text('What will you do today?'), findsOneWidget);

    // Reopen it from the history.
    await tester.tap(find.byTooltip('Chats'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('How do I write an essay?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('pick GhostWriter'), findsOneWidget);
  });

  testWidgets('stop keeps what was said', (tester) async {
    final h = Harness(account: ada);
    await h.pump(tester);
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump(const Duration(milliseconds: 35));
    await tester.tap(find.byTooltip('Stop'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Send'), findsOneWidget);
    expect(find.textContaining("I'm Octopilot"), findsOneWidget);
    expect(find.textContaining('What would you like to do?'), findsNothing);
  });

  testWidgets('chats can be renamed, searched and deleted', (tester) async {
    final h = Harness(account: ada);
    await h.pump(tester);
    for (final text in ['first question', 'second question']) {
      h.services.conversation.newChat();
      await tester.enterText(find.byType(TextField), text);
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byTooltip('Chats'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search chats'),
      'first',
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Chat options'), findsOneWidget);

    await tester.tap(find.byTooltip('Chat options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Renamed');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(h.chat.threads.value.map((t) => t.title), contains('Renamed'));

    await tester.enterText(find.widgetWithText(TextField, 'first'), '');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Chat options').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(h.chat.threads.value.map((t) => t.title), ['Renamed']);
    expect(
      h.services.conversation.isEmpty,
      isTrue,
      reason: 'the open chat was the deleted one',
    );
  });

  testWidgets('settings: account, theme, AI, delete account', (tester) async {
    final h = Harness(account: ada);
    await h.pump(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('ada@test'), findsOneWidget);
    expect(find.text('Pro Monthly'), findsOneWidget);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(h.theme.value, ThemeMode.light);
    final context = tester.element(find.text('Settings'));
    expect(Theme.of(context).brightness, Brightness.light);

    await tester.tap(find.text('Model and voice'));
    expect(h.aiSettings, 1);
    expect(find.text('Notifications'), findsNothing, reason: 'not wired');

    await tester.scrollUntilVisible(find.text('Delete account'), 100);
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    expect(find.text('Delete your account?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(h.deleted, 0);

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account').last);
    await tester.pumpAndSettle();
    expect(h.deleted, 1);
  });

  testWidgets('signed out, settings offer no account actions', (tester) async {
    await Harness().pump(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Not signed in'), findsOneWidget);
    expect(find.text('Sign out'), findsNothing);
    expect(find.text('Delete account'), findsNothing);
  });

  test('credits are written short', () {
    expect(formatCredits(980), '980');
    expect(formatCredits(1240), '1,240');
    expect(formatCredits(12400), '12.4k');
    expect(formatCredits(250000), '250k');
  });
}
