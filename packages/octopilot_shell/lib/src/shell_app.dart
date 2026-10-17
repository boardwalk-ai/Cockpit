import 'dart:async';
import 'dart:math' as math;

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
    this.links,
    this.initialLocation = '/',
    this.textScale = 0.92,
    this.overlay,
  });

  final ShellServices services;
  final List<RouteBase> moduleRoutes;

  /// Places to open as they come (a tapped notification's `/study/…`).
  final Stream<String>? links;

  final String initialLocation;

  /// Wraps every screen (e.g. an in-app notification banner on top).
  final Widget Function(BuildContext context, Widget child)? overlay;

  /// How big text is drawn, for every screen (modules too). The phone's own
  /// larger-text setting is followed up to its normal size, no further, so
  /// screens keep their layout.
  final double textScale;

  @override
  State<OctopilotShellApp> createState() => _OctopilotShellAppState();
}

class _OctopilotShellAppState extends State<OctopilotShellApp> {
  late final GoRouter _router = GoRouter(
    initialLocation: widget.initialLocation,
    routes: [...shellRoutes(), ...widget.moduleRoutes],
  );

  StreamSubscription<String>? _links;

  @override
  void initState() {
    super.initState();
    _links = widget.links?.listen((to) {
      if (to.startsWith('/')) _router.go(to);
    });
  }

  @override
  void dispose() {
    _links?.cancel();
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
        builder: (context, child) {
          final media = MediaQuery.of(context);
          final system = math.min(media.textScaler.scale(1), 1.0);
          return MediaQuery(
            data: media.copyWith(
              textScaler: TextScaler.linear(system * widget.textScale),
            ),
            child: ShellScope(
              services: widget.services,
              child: widget.overlay?.call(context, child!) ?? child!,
            ),
          );
        },
      ),
    );
  }
}
