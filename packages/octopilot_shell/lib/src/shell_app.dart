import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'home/home_page.dart';
import 'library/mode_library_page.dart';
import 'motion.dart';
import 'settings/settings_page.dart';
import 'shell_models.dart';
import 'shell_scope.dart';
import 'shell_theme.dart';
import 'voice/voice_page.dart';

/// The shell's own screens: Home (`/`), a mode's Library (`/mode/:mode`),
/// Settings (`/settings`) and voice mode (`/voice`, pops `true` to type
/// instead).
List<RouteBase> shellRoutes() => [
  GoRoute(path: '/', builder: (_, _) => const ShellHomePage()),
  GoRoute(
    path: '/mode/:mode',
    redirect: (_, state) =>
        ShellMode.byName(state.pathParameters['mode']) == null ? '/' : null,
    pageBuilder: (_, state) => _page(
      state,
      ModeLibraryPage(mode: ShellMode.byName(state.pathParameters['mode'])!),
    ),
  ),
  GoRoute(
    path: '/settings',
    pageBuilder: (_, state) => _page(state, const ShellSettingsPage()),
  ),
  GoRoute(
    path: '/voice',
    pageBuilder: (_, state) => CustomTransitionPage<bool>(
      key: state.pageKey,
      transitionDuration: const Duration(milliseconds: 650),
      reverseTransitionDuration: const Duration(milliseconds: 450),
      child: const VoicePage(),
      transitionsBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    ),
  ),
];

Page<void> _page(GoRouterState state, Widget child) => CustomTransitionPage(
  key: state.pageKey,
  transitionDuration: const Duration(milliseconds: 520),
  reverseTransitionDuration: const Duration(milliseconds: 380),
  transitionsBuilder: shellPageTransition,
  child: child,
);

/// The Octopilot app: the shell's screens plus [moduleRoutes].
class OctopilotShellApp extends StatefulWidget {
  const OctopilotShellApp({
    super.key,
    required this.services,
    this.moduleRoutes = const [],
    this.initialLocation = '/',
  });

  final ShellServices services;
  final List<RouteBase> moduleRoutes;
  final String initialLocation;

  @override
  State<OctopilotShellApp> createState() => _OctopilotShellAppState();
}

class _OctopilotShellAppState extends State<OctopilotShellApp> {
  late final GoRouter _router = GoRouter(
    initialLocation: widget.initialLocation,
    routes: [...shellRoutes(), ...widget.moduleRoutes],
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.services.themeMode,
      builder: (context, mode, _) => MaterialApp.router(
        title: 'Octopilot',
        debugShowCheckedModeBanner: false,
        theme: buildShellTheme(Brightness.light),
        darkTheme: buildShellTheme(Brightness.dark),
        themeMode: mode,
        routerConfig: _router,
        builder: (context, child) =>
            ShellScope(services: widget.services, child: child!),
      ),
    );
  }
}
