import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ghostwriter/ghostwriter.dart';
import 'package:octopilot_shell/octopilot_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_studio/study_studio.dart';

import 'modules/module_auth.dart';
import 'modules/module_push.dart';
import 'modules/study_voice_adapter.dart';
import 'voice/pocket_voice_engine.dart';

/// The Octopilot app: the shell (main chat Home, a Library per mode,
/// Settings) with the modules that are out. Signs in with the shared
/// Octopilot Firebase account; without Firebase config it runs as the dev
/// user.
///
///   flutter run -t lib/main_octopilot.dart
/// `--dart-define=OCTOPILOT_DEV_AUTH=true` skips Firebase and runs as the
/// dev user, for a phone against a dev API with auth off.
const _devAuth = bool.fromEnvironment('OCTOPILOT_DEV_AUTH');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!_devAuth) await initStudioFirebase();
  runApp(
    ProviderScope(
      overrides: [
        studyPushProvider.overrideWith(
          (ref) => ref.watch(studyPushImplProvider),
        ),
      ],
      child: const OctopilotApp(),
    ),
  );
}

const _themeKey = 'octopilot.theme';
const _voiceKey = 'octopilot.voice';

class OctopilotApp extends ConsumerStatefulWidget {
  const OctopilotApp({super.key});

  @override
  ConsumerState<OctopilotApp> createState() => _OctopilotAppState();
}

class _OctopilotAppState extends ConsumerState<OctopilotApp> {
  late final GwAuth _auth = ref.read(ghostWriterAuthProvider);
  late final GhostWriterModule _ghostWriter = GhostWriterModule(
    auth: _auth,
    push: ref.read(ghostWriterPushProvider),
  );
  final _studyStudio = const StudyStudioModule();
  final _account = ValueNotifier<ShellAccount?>(null);
  final _theme = ValueNotifier<ThemeMode>(ThemeMode.system);
  final _voice = ValueNotifier<String>(octopilotVoices.first.id);
  final _voiceEngine = PocketVoiceEngine();
  late final _studyVoice = EngineStudyVoice(_voiceEngine, _voice);
  StreamSubscription<bool>? _signIns;

  late final ShellServices _services = ShellServices(
    // Until the app's own API exists, the main chat is answered by
    // GhostWriter's API (Ask Octo, scoped to the whole app).
    chat: LocalMainChat(answer: _answer),
    voice: _voiceEngine,
    voices: octopilotVoices,
    voiceId: _voice,
    onVoiceChanged: _saveVoice,
    modules: [
      ShellModuleEntry(
        id: _ghostWriter.id,
        mode: ShellMode.create,
        title: _ghostWriter.title,
        description: 'Essays with AI, from brief to sources to draft.',
        icon: Icons.history_edu_rounded,
        path: _ghostWriter.rootPath,
      ),
      ShellModuleEntry(
        id: _studyStudio.id,
        mode: ShellMode.learn,
        title: 'Study Studio',
        description: 'Flashcards and practice from your material.',
        icon: Icons.style_outlined,
        path: _studyStudio.rootPath,
      ),
      const ShellModuleEntry(
        id: 'octo_notes',
        mode: ShellMode.organize,
        title: 'OctoNotes',
        description: 'Notes that organise themselves.',
        icon: Icons.sticky_note_2_outlined,
      ),
    ],
    account: _account,
    themeMode: _theme,
    setThemeMode: _setTheme,
    onAiSettings: (context) =>
        GhostWriterHost.showAiSettings(context, auth: _auth),
    onNotifications: _soon,
    onCredits: _soon,
    onAbout: _soon,
    onSignIn: _auth.enabled ? _auth.signIn : null,
    onSignOut: _auth.enabled ? _signOut : null,
    // Needs the account-deletion endpoint.
    onDeleteAccount: (context) async => _soon(context),
  );

  @override
  void initState() {
    super.initState();
    _loadTheme();
    // The first greeting, made now: it also loads the on-device model.
    _loadVoice().then((_) => _services.prepareGreeting());
    _signIns = _auth.authStateChanges().listen((_) => _loadAccount());
    _loadAccount();
  }

  /// Stops this phone's Study Studio notifications while the sign-in still
  /// works, then signs out.
  Future<void> _signOut() async {
    await ref.read(studyPushLinkProvider)?.unregister();
    await _auth.signOut();
  }

  @override
  void dispose() {
    _signIns?.cancel();
    _services.conversation.dispose();
    super.dispose();
  }

  Future<void> _loadVoice() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(
        _voiceKey,
      );
      if (octopilotVoices.any((v) => v.id == saved)) _voice.value = saved!;
    } on Object {
      // No saved choice: the first voice.
    }
  }

  Future<void> _saveVoice(String id) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_voiceKey, id);
    } on Object {
      // Kept for this session only.
    }
  }

  Future<void> _loadTheme() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(
        _themeKey,
      );
      final mode = ThemeMode.values.where((m) => m.name == saved).firstOrNull;
      if (mode != null) _theme.value = mode;
    } on Object {
      // No saved choice: follow the system.
    }
  }

  Future<void> _setTheme(ThemeMode mode) async {
    _theme.value = mode;
    try {
      await (await SharedPreferences.getInstance()).setString(
        _themeKey,
        mode.name,
      );
    } on Object {
      // Kept for this session only.
    }
  }

  Future<void> _loadAccount() async {
    if (_auth.enabled && !_auth.isSignedIn) {
      _account.value = null;
      return;
    }
    try {
      final me = await GhostWriterHost.me(auth: _auth);
      // Signed in: this phone gets Study Studio notifications if allowed.
      ref.read(studyPushLinkProvider)?.start();
      _account.value = ShellAccount(
        name: (me['name'] as String?) ?? (me['email'] as String?) ?? 'You',
        email: me['email'] as String?,
        photoUrl: me['photoUrl'] as String?,
        plan: me['plan'] as String?,
        credits: (me['octoCredits'] as num?)?.toInt(),
      );
    } on Object {
      // The server is unreachable: show the app without an account.
      _account.value = null;
    }
  }

  Future<String> _answer(String text, List<ChatMessage> history) =>
      GhostWriterHost.askApp(
        text,
        history: [
          for (final m in history)
            {
              'role': m.role == ChatRole.user ? 'user' : 'assistant',
              'text': m.text,
            },
        ],
        auth: _auth,
      );

  void _soon(BuildContext context) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Coming soon.')));

  @override
  Widget build(BuildContext context) => ProviderScope(
    // Study Studio answers out loud and reads questions with the same voice.
    overrides: [studyVoiceProvider.overrideWithValue(_studyVoice)],
    child: OctopilotShellApp(
      services: _services,
      moduleRoutes: [..._ghostWriter.routes(), ..._studyStudio.routes()],
      links: notificationLinks(ref.read(ghostWriterPushProvider)),
    ),
  );
}
