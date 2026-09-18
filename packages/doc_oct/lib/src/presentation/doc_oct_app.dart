import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_providers.dart';
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

class DocOctFlow extends ConsumerStatefulWidget {
  const DocOctFlow({super.key});

  @override
  ConsumerState<DocOctFlow> createState() => _DocOctFlowState();
}

class _DocOctFlowState extends ConsumerState<DocOctFlow> {
  _Screen _screen = _Screen.loading;
  String _topic = '';
  FormatStyle _style = FormatStyle.mla;

  /// Direction of the last navigation — drives which way the pages slide.
  bool _forward = true;

  void _go(_Screen s) => setState(() {
        _forward = s.index >= _screen.index;
        _screen = s;
      });

  Future<void> _signIn() async {
    try {
      await ref.read(docAuthProvider).signIn();
      if (mounted) _go(_Screen.workspace);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign-in failed: $e')),
        );
      }
    }
  }

  void _signOut() {
    ref.read(docAuthProvider).signOut();
    _go(_Screen.welcome);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: _transition,
      layoutBuilder: (current, previous) => Stack(
        children: [...previous, if (current != null) current],
      ),
      child: KeyedSubtree(key: ValueKey(_screen), child: _current()),
    );
  }

  /// A direction-aware cross-fade + horizontal slide. Incoming pages enter from
  /// the forward side; the outgoing page fades and drifts the opposite way.
  Widget _transition(Widget child, Animation<double> animation) {
    final incoming = child.key == ValueKey(_screen);
    final dir = _forward ? 1.0 : -1.0;
    final begin = incoming ? Offset(0.05 * dir, 0) : Offset(-0.05 * dir, 0);
    final slide = Tween<Offset>(begin: begin, end: Offset.zero)
        .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(position: slide, child: child),
    );
  }

  Widget _current() {
    switch (_screen) {
      case _Screen.loading:
        return DocOctLoadingPage(onDone: () => _go(_Screen.welcome));

      case _Screen.welcome:
        return WizardWelcomePage(
          onSpecifyTopic: () => _go(_Screen.setup),
          onStartWriting: () => _go(_Screen.editor),
          onSignIn: _signIn,
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
              _forward = true;
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
              _forward = true;
              _screen = _Screen.editor;
            });
          },
          onOpenDocument: (_) => _go(_Screen.editor),
          onSignOut: _signOut,
        );

      case _Screen.editor:
        return EditorPage(
          initialStyle: _style,
          onBack: () => _go(_Screen.welcome),
        );
    }
  }
}
