import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/doc_theme.dart';
import '../theme/theme_controller.dart';
import 'projects/saved_projects_page.dart';

/// Standalone Doc Oct app entry — light/dark driven by the floating switcher.
/// Wrap in a [ProviderScope] at the real entry point.
class DocOctApp extends ConsumerWidget {
  const DocOctApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Doc Oct',
      debugShowCheckedModeBanner: false,
      theme: DocTheme.light(),
      darkTheme: DocTheme.dark(),
      themeMode: ref.watch(docThemeControllerProvider),
      home: SavedProjectsPage(
        onNew: () {}, // wizard — wired next
        onOpen: (_) {}, // editor — Phase 2
      ),
    );
  }
}
