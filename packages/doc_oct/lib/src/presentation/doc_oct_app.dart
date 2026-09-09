import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/doc_tokens.dart';
import 'editor/editor_page.dart';
import 'loading/doc_oct_loading_page.dart';
import 'wizard/wizard_analysis_page.dart';
import 'wizard/wizard_setup_page.dart';
import 'wizard/wizard_welcome_page.dart';
import 'workspace/workspace_page.dart';

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

/// The Phase-1 screens, threaded into a simple navigator so every screen is
/// reachable: loading → welcome (logged-out wizard) → setup → analysis, plus
/// the signed-in workspace (via the avatar) → an editor placeholder.
enum _Screen { loading, welcome, setup, analysis, workspace, editor }

class DocOctFlow extends StatefulWidget {
  const DocOctFlow({super.key});

  @override
  State<DocOctFlow> createState() => _DocOctFlowState();
}

class _DocOctFlowState extends State<DocOctFlow> {
  _Screen _screen = _Screen.loading;
  String _topic = '';
  FormatStyle _style = FormatStyle.mla;

  void _go(_Screen s) => setState(() => _screen = s);

  @override
  Widget build(BuildContext context) {
    switch (_screen) {
      case _Screen.loading:
        return DocOctLoadingPage(onDone: () => _go(_Screen.welcome));

      case _Screen.welcome:
        return WizardWelcomePage(
          onSpecifyTopic: () => _go(_Screen.setup),
          onStartWriting: () => _go(_Screen.editor),
          onSignIn: () => _go(_Screen.workspace),
        );

      case _Screen.setup:
        return WizardSetupPage(
          initialTopic: _topic,
          initialStyle: _style,
          onBack: () => _go(_Screen.welcome),
          onAnalyze: (topic, style) {
            setState(() {
              _topic = topic;
              _style = style;
              _screen = topic.isEmpty ? _Screen.editor : _Screen.analysis;
            });
          },
        );

      case _Screen.analysis:
        return WizardAnalysisPage(
          topic: _topic,
          style: _style,
          onBack: () => _go(_Screen.setup),
          onContinue: () => _go(_Screen.editor),
        );

      case _Screen.workspace:
        return WorkspacePage(
          onNewDocument: (style) {
            setState(() {
              _style = style ?? FormatStyle.mla;
              _screen = _Screen.editor;
            });
          },
          onOpenDocument: (_) => _go(_Screen.editor),
          onSignOut: () => _go(_Screen.welcome),
        );

      case _Screen.editor:
        return EditorPage(
          initialStyle: _style,
          onBack: () => _go(_Screen.welcome),
        );
    }
  }
}
