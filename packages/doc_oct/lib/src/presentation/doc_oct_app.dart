import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'projects/saved_projects_page.dart';

/// Standalone Doc Oct app entry — borderless theme, light/dark driven by the
/// floating [ThemeSwitcher] via the shared [themeControllerProvider]. Wrap in a
/// [ProviderScope] at the real entry point.
class DocOctApp extends ConsumerWidget {
  const DocOctApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Doc Oct',
      debugShowCheckedModeBanner: false,
      theme: BorderlessTheme.build(Brightness.light),
      darkTheme: BorderlessTheme.build(Brightness.dark),
      themeMode: ref.watch(themeControllerProvider).mode,
      home: const SavedProjectsPage(),
    );
  }
}

/// Doc Oct mounted as a **route inside a host app** (e.g. Cockpit). Forces the
/// borderless theme onto its own subtree (following the app brightness) so it
/// keeps the OctoNotes look regardless of the host's theme.
class DocOctRoot extends StatelessWidget {
  const DocOctRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return BorderlessTheme.wrap(
      context: context,
      child: const SavedProjectsPage(),
    );
  }
}
