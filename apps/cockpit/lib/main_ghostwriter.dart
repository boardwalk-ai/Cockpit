import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ghostwriter/ghostwriter.dart';
import 'package:go_router/go_router.dart';
import 'package:study_studio/study_studio.dart';

/// Standalone GhostWriter entrypoint: the release app while GhostWriter is the
/// only finished module. Signs in with the shared Octopilot Firebase account.
///
///   flutter run -t lib/main_ghostwriter.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initStudioFirebase(); // no-op unless FIREBASE_* defines are provided
  runApp(const ProviderScope(child: GhostWriterApp()));
}

final _router = GoRouter(
  initialLocation: '/ghostwriter',
  routes: [
    GoRoute(path: '/', redirect: (_, _) => '/ghostwriter'),
    ...const GhostWriterModule().routes(),
  ],
);

class GhostWriterApp extends StatelessWidget {
  const GhostWriterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'GhostWriter',
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
    );
  }
}
