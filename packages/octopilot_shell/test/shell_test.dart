import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final voice = DemoVoiceEngine(
    wordTime: const Duration(milliseconds: 20),
    frame: const Duration(milliseconds: 10),
  );
  final opened = <String>[];
  var deleted = 0;
  String? savedVoice;
  var aiSettings = 0;

  late final services = ShellServices(
    chat: chat,
    voice: voice,
    voices: const [
      ShellVoice(id: 'marc', name: 'Marc', colors: [Colors.red, Colors.orange]),
      ShellVoice(
        id: 'sarah',
        name: 'Sarah',
        female: true,
        colors: [Colors.pink, Colors.amber],
      ),
    ],
    onVoiceChanged: (id) => savedVoice = id,
    greeter: lateNightGreeter(),
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
    // The glows and the orb move forever; with reduced motion they hold
    // still, so frames can settle.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
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
    expect(find.textContaining(', Ada'), findsOneWidget);
    // Voice first; the message box is one tap away.
    expect(find.text('Tap to talk'), findsOneWidget);
    expect(find.text('Message Octopilot'), findsNothing);
    await tester.tap(find.byTooltip('Type a message'));
    await tester.pumpAndSettle();
    expect(find.text('Message Octopilot'), findsOneWidget);
  });

  testWidgets('a mode opens its library; modules open, soon ones say so', (
    tester,
  ) async {
    final h = Harness(account: ada);
    await h.pump(tester);

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Write and make things'), findsOneWidget);
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
    expect(find.text('Write and make things'), findsOneWidget);
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
    await tester.tap(find.byTooltip('Type a message'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'How do I write an essay?');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(find.text('How do I write an essay?'), findsOneWidget);
    expect(find.text('What will you do today?'), findsNothing);
    expect(find.byTooltip('Stop'), findsOneWidget);

    await pumpUntil(tester, find.byTooltip('Talk'));
    expect(find.textContaining('pick GhostWriter'), findsOneWidget);
    expect(find.byTooltip('Talk'), findsOneWidget, reason: 'empty box: mic');

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
    await tester.tap(find.byTooltip('Type a message'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump(const Duration(milliseconds: 35));
    await tester.tap(find.byTooltip('Stop'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Talk'), findsOneWidget);
    expect(find.textContaining("I'm Octopilot"), findsOneWidget);
    expect(find.textContaining('What would you like to do?'), findsNothing);
  });

  testWidgets('chats can be renamed, searched and deleted', (tester) async {
    final h = Harness(account: ada);
    await h.pump(tester);
    await tester.tap(find.byTooltip('Type a message'));
    await tester.pumpAndSettle();
    for (final text in ['first question', 'second question']) {
      h.services.conversation.newChat();
      await tester.enterText(find.byType(TextField), text);
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await pumpUntil(tester, find.byTooltip('Talk'));
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

    await tester.tap(find.text('Model and personality'));
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

  testWidgets('voice: greets, then hold to talk; the turn lands in the chat', (
    tester,
  ) async {
    final h = Harness(account: ada);
    await h.pump(tester);
    final greeting = lateNightGreeter().take(name: 'Ada');

    await tester.tap(find.byTooltip('Talk'));
    await pumpUntil(tester, find.text(greeting));
    await pumpUntil(tester, find.text('Hold to talk'));
    expect(h.chat.threads.value, isEmpty, reason: 'a greeting is not a turn');

    final hold = await tester.startGesture(
      tester.getCenter(find.byType(VoiceOrb).last),
    );
    await pumpUntil(tester, find.text('Listening'));
    await pumpUntil(tester, find.text('How do I write an essay here?'));
    // Still held: nothing is sent yet.
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Listening'), findsOneWidget);
    await hold.up();
    await pumpUntil(tester, find.text('Speaking'));
    expect(h.chat.threads.value.single.title, 'How do I write an essay here?');
    await pumpUntil(tester, find.text('Hold to talk'));

    await tester.tap(find.byTooltip('End voice'));
    await tester.pumpAndSettle();
    expect(find.text('How do I write an essay here?'), findsOneWidget);
    expect(find.textContaining('pick GhostWriter'), findsOneWidget);
  });

  testWidgets('voice: type instead opens the message box', (tester) async {
    await Harness(account: ada).pump(tester);
    await tester.tap(find.byTooltip('Talk'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(find.byTooltip('Type instead'));
    await tester.pumpAndSettle();
    expect(find.text('Message Octopilot'), findsOneWidget);
  });

  testWidgets('a voice is picked in settings, heard, and remembered', (
    tester,
  ) async {
    final h = Harness(account: ada);
    await h.pump(tester);
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Voice'), findsOneWidget);
    expect(find.text('Marc'), findsOneWidget, reason: 'the first by default');

    await tester.tap(find.text('Voice'));
    await tester.pumpAndSettle();
    expect(find.text('Tap one to hear it.'), findsOneWidget);
    await tester.tap(find.text('Sarah'));
    await pumpUntil(tester, find.text('Female'));
    expect(h.services.voiceId.value, 'sarah');
    expect(h.savedVoice, 'sarah');
    expect(haptics, contains('HapticFeedbackType.selectionClick'));
    // Let the hello finish.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  });

  testWidgets('voice: the reply shows only once its voice is ready', (
    tester,
  ) async {
    final h = Harness(account: ada);
    final ready = Completer<void>();
    final slow = _SlowVoice(h.voice, ready.future);
    final services = await _pumpVoice(tester, h, slow);

    await _holdAndSay(tester);
    await pumpUntil(tester, find.text('Thinking'));
    // The text reply is in, the voice is not: still thinking, nothing said.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(services.conversation.replying, isFalse);
    expect(find.text('Thinking'), findsOneWidget);
    expect(find.textContaining('pick GhostWriter'), findsNothing);

    ready.complete();
    await pumpUntil(tester, find.text('Speaking'));
    expect(find.textContaining('pick GhostWriter'), findsOneWidget);
    await tester.tap(find.byTooltip('End voice'));
    await tester.pumpAndSettle();
  });

  testWidgets('voice: a hold that hears nothing sends nothing', (tester) async {
    final h = Harness(account: ada);
    final deaf = _DeafVoice(h.voice);
    final services = await _pumpVoice(tester, h, deaf);

    final hold = await tester.startGesture(
      tester.getCenter(find.byType(VoiceOrb).last),
    );
    await pumpUntil(tester, find.text('Listening'));
    await hold.up();
    await pumpUntil(tester, find.textContaining("I didn't catch that"));
    expect(services.conversation.messages, isEmpty);
    final listens = deaf.listens;
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(deaf.listens, listens, reason: 'the mic opens only while held');
    await tester.tap(find.byTooltip('End voice'));
    await tester.pumpAndSettle();
  });

  testWidgets('voice: the recognizer stopping mid-hold is asked again', (
    tester,
  ) async {
    final h = Harness(account: ada);
    final choppy = _ChoppyVoice(h.voice);
    final services = await _pumpVoice(tester, h, choppy);

    final hold = await tester.startGesture(
      tester.getCenter(find.byType(VoiceOrb).last),
    );
    await pumpUntil(tester, find.text('make an essay'));
    await hold.up();
    await pumpUntil(tester, find.text('Thinking'));
    expect(services.conversation.messages.first.text, 'make an essay');
    expect(choppy.listens, 2);
    await tester.tap(find.byTooltip('End voice'));
    await tester.pumpAndSettle();
  });

  test('greetings fit the time and the name', () {
    final night = Greeter(clock: () => DateTime(2026, 1, 1, 23));
    expect(night.choices(), contains('Hey night owl. What are we working on?'));
    expect(
      night.choices(),
      isNot(contains('Good morning! How can I help you?')),
    );
    expect(
      night.choices().where((g) => g.contains('{name}')),
      isEmpty,
      reason: 'no name, no presets that need one',
    );
    expect(
      night.choices(name: 'Ada'),
      contains("Still up, Ada? Let's get it done."),
    );

    final morning = Greeter(clock: () => DateTime(2026, 1, 1, 7));
    expect(
      morning.choices(name: 'Ada'),
      contains('Morning, Ada. Coffee ready? What are we working on?'),
    );

    // Never the same twice in a row; the one picked ahead is what is said.
    final g = Greeter(
      random: math.Random(3),
      clock: () => DateTime(2026, 1, 1, 14),
    );
    var last = g.take();
    for (var i = 0; i < 20; i++) {
      final ahead = g.upcoming();
      final now = g.take();
      expect(now, ahead);
      expect(now, isNot(last));
      last = now;
    }
  });

  test('credits are written short', () {
    expect(formatCredits(980), '980');
    expect(formatCredits(1240), '1,240');
    expect(formatCredits(12400), '12.4k');
    expect(formatCredits(250000), '250k');
  });
}

/// Pumps frames until [finder] finds something (at most ~6 s).
Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 300; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('never found: $finder');
}

/// Hears like [inner], but its voice is ready only when [ready] completes.
class _SlowVoice implements VoiceEngine {
  _SlowVoice(this.inner, this.ready);

  final VoiceEngine inner;
  final Future<void> ready;

  @override
  Future<String?> listen({
    required ValueChanged<String> onPartial,
    required ValueChanged<double> onLevel,
    bool held = false,
  }) => inner.listen(onPartial: onPartial, onLevel: onLevel, held: held);

  @override
  void finishListening() => inner.finishListening();

  /// Greetings ([keep]) are ready at once; replies wait for [ready].
  @override
  Future<Speech> prepare(
    String text, {
    required String voice,
    bool keep = false,
  }) async {
    if (!keep) await ready;
    return inner.prepare(text, voice: voice, keep: keep);
  }

  @override
  Future<void> play(
    Speech speech, {
    required ValueChanged<double> onLevel,
    required ValueChanged<double> onProgress,
  }) => inner.play(speech, onLevel: onLevel, onProgress: onProgress);

  @override
  void stop() => inner.stop();
}

/// A microphone that never hears anything.
class _DeafVoice extends _SlowVoice {
  _DeafVoice(VoiceEngine inner) : super(inner, Future.value());

  var listens = 0;
  Completer<void>? _released;

  @override
  Future<String?> listen({
    required ValueChanged<String> onPartial,
    required ValueChanged<double> onLevel,
    bool held = false,
  }) async {
    listens++;
    await (_released = Completer<void>()).future;
    return null;
  }

  @override
  void finishListening() => _release();

  @override
  void stop() {
    _release();
    super.stop();
  }

  void _release() {
    if (!(_released?.isCompleted ?? true)) _released!.complete();
  }
}

/// A recognizer that stops by itself after two words, while the orb is held.
class _ChoppyVoice extends _SlowVoice {
  _ChoppyVoice(VoiceEngine inner) : super(inner, Future.value());

  var listens = 0;
  Completer<void>? _released;

  @override
  Future<String?> listen({
    required ValueChanged<String> onPartial,
    required ValueChanged<double> onLevel,
    bool held = false,
  }) async {
    listens++;
    if (listens == 1) {
      onPartial('make an');
      return 'make an';
    }
    onPartial('essay');
    await (_released = Completer<void>()).future;
    return 'essay';
  }

  @override
  void finishListening() => _release();

  @override
  void stop() {
    _release();
    super.stop();
  }

  void _release() {
    if (!(_released?.isCompleted ?? true)) _released!.complete();
  }
}

/// The same greeting every run: late at night, the same random picks.
Greeter lateNightGreeter() =>
    Greeter(random: math.Random(1), clock: () => DateTime(2026, 1, 1, 23));

/// Voice mode open on [engine], past its greeting.
Future<ShellServices> _pumpVoice(
  WidgetTester tester,
  Harness h,
  VoiceEngine engine,
) async {
  final services = ShellServices(
    chat: h.chat,
    voice: engine,
    modules: h.services.modules,
    account: h.account,
    themeMode: h.theme,
    setThemeMode: (_) {},
    greeter: lateNightGreeter(),
  );
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(OctopilotShellApp(services: services));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Talk'));
  await pumpUntil(tester, find.text('Hold to talk'));
  return services;
}

/// Holds the orb until the demo question is heard, then lets go.
Future<void> _holdAndSay(WidgetTester tester) async {
  final hold = await tester.startGesture(
    tester.getCenter(find.byType(VoiceOrb).last),
  );
  await pumpUntil(tester, find.text('How do I write an essay here?'));
  await hold.up();
}
