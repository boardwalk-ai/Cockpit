import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:octo_notes/octo_notes.dart';
import 'package:study_studio/study_studio.dart';

import 'modules/module_auth.dart';

/// Standalone OctoNotes web entrypoint (notes.octopilothub.com). Runs only the
/// OctoNotes module, signed in with the shared Octopilot Firebase account, and
/// talks to octonotes-api via --dart-define=OCTONOTES_API_BASE_URL=….
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initStudioFirebase(); // no-op unless FIREBASE_* defines are provided
  runApp(ProviderScope(overrides: moduleAuthOverrides, child: const OctoNotesApp()));
}

final _router = GoRouter(
  initialLocation: '/notes',
  routes: [
    GoRoute(path: '/', redirect: (_, _) => '/notes'),
    ...const OctoNotesModule().routes(),
  ],
);

class OctoNotesApp extends ConsumerWidget {
  const OctoNotesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeControllerProvider);
    return MaterialApp.router(
      title: 'OctoNotes',
      debugShowCheckedModeBanner: false,
      theme: themeState.light,
      darkTheme: themeState.dark,
      themeMode: themeState.mode,
      routerConfig: _router,
    );
  }
}
