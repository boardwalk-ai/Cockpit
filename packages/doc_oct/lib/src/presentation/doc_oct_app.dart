import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'loading/doc_oct_loading_page.dart';
import 'wizard/wizard_welcome_page.dart';

/// Standalone Doc Oct app entry — borderless theme, light/dark via the floating
/// [ThemeSwitcher] / shared [themeControllerProvider]. Wrap in a [ProviderScope].
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
      home: const DocOctFlow(),
    );
  }
}

/// Doc Oct mounted as a route inside a host app (e.g. Cockpit) — forces the
/// borderless theme onto its subtree, following the app brightness.
class DocOctRoot extends StatelessWidget {
  const DocOctRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return BorderlessTheme.wrap(context: context, child: const DocOctFlow());
  }
}

/// The entry flow: the signature loading screen, then the wizard welcome
/// (Phase 1 stops here; setup/analysis/workspace/editor come next).
class DocOctFlow extends StatefulWidget {
  const DocOctFlow({super.key});

  @override
  State<DocOctFlow> createState() => _DocOctFlowState();
}

class _DocOctFlowState extends State<DocOctFlow> {
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return DocOctLoadingPage(onDone: () => setState(() => _loaded = true));
    }
    return const WizardWelcomePage();
  }
}
