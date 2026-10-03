import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'home/home_page.dart';
import 'library/mode_library_page.dart';
import 'settings/settings_page.dart';
import 'shell_models.dart';
import 'shell_scope.dart';
import 'shell_theme.dart';

/// The shell's own screens: Home (`/`), a mode's Library (`/mode/:mode`) and
/// Settings (`/settings`).
List<RouteBase> shellRoutes() => [
  GoRoute(path: '/', builder: (_, _) => const ShellHomePage()),
  GoRoute(
    path: '/mode/:mode',
    redirect: (_, state) =>
        ShellMode.byName(state.pathParameters['mode']) == null ? '/' : null,
    builder: (_, state) =>
        ModeLibraryPage(mode: ShellMode.byName(state.pathParameters['mode'])!),
  ),
  GoRoute(path: '/settings', builder: (_, _) => const ShellSettingsPage()),
];

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
