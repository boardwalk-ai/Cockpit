import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ghostwriter/ghostwriter.dart';
import 'package:go_router/go_router.dart';
import 'package:study_studio/study_studio.dart';

import 'modules/module_auth.dart';
import 'modules/module_push.dart';

/// Standalone GhostWriter entrypoint: the release app while GhostWriter is the
/// only finished module. Signs in with the shared Octopilot Firebase account
/// (from `google-services.json` / `GoogleService-Info.plist` on phones, the
/// `FIREBASE_*` defines on the web); without either it runs as the dev user.
///
///   flutter run -t lib/main_ghostwriter.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initStudioFirebase();
  runApp(const ProviderScope(child: GhostWriterApp()));
}

class GhostWriterApp extends ConsumerStatefulWidget {
  const GhostWriterApp({super.key});

  @override
  ConsumerState<GhostWriterApp> createState() => _GhostWriterAppState();
}

class _GhostWriterAppState extends ConsumerState<GhostWriterApp> {
  late final GoRouter _router = GoRouter(
    initialLocation: '/ghostwriter',
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/ghostwriter'),
      ...GhostWriterModule(
        auth: ref.read(ghostWriterAuthProvider),
        push: ref.read(ghostWriterPushProvider),
      ).routes(),
    ],
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'GhostWriter',
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
    );
  }
}
