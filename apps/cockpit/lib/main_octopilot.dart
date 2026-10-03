import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ghostwriter/ghostwriter.dart';
import 'package:octopilot_shell/octopilot_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_studio/study_studio.dart';

import 'modules/module_auth.dart';
import 'modules/module_push.dart';

/// The Octopilot app: the shell (main chat Home, a Library per mode,
/// Settings) with the modules that are out. Signs in with the shared
/// Octopilot Firebase account; without Firebase config it runs as the dev
/// user.
///
///   flutter run -t lib/main_octopilot.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initStudioFirebase();
  runApp(const ProviderScope(child: OctopilotApp()));
}

const _themeKey = 'octopilot.theme';

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
  final _account = ValueNotifier<ShellAccount?>(null);
  final _theme = ValueNotifier<ThemeMode>(ThemeMode.system);
  StreamSubscription<bool>? _signIns;

  late final ShellServices _services = ShellServices(
    // The main chat's server is not built yet.
    chat: DemoMainChat(),
    modules: [
      ShellModuleEntry(
        id: _ghostWriter.id,
        mode: ShellMode.create,
        title: _ghostWriter.title,
        description: 'Essays with AI, from brief to sources to draft.',
        icon: Icons.history_edu_rounded,
        path: _ghostWriter.rootPath,
      ),
      const ShellModuleEntry(
        id: 'study_studio',
        mode: ShellMode.learn,
        title: 'Study Studio',
        description: 'Flashcards and practice from your material.',
        icon: Icons.style_outlined,
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
    onSignOut: _auth.enabled ? _auth.signOut : null,
    // Needs the account-deletion endpoint.
    onDeleteAccount: (context) async => _soon(context),
  );

  @override
  void initState() {
    super.initState();
    _loadTheme();
    _signIns = _auth.authStateChanges().listen((_) => _loadAccount());
    _loadAccount();
  }

  @override
  void dispose() {
    _signIns?.cancel();
    _services.conversation.dispose();
    super.dispose();
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

  void _soon(BuildContext context) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Coming soon.')));

  @override
  Widget build(BuildContext context) => OctopilotShellApp(
    services: _services,
    moduleRoutes: _ghostWriter.routes(),
  );
}
