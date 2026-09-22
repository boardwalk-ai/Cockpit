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

  /// When opening a saved document: its id + serialized state (else null = new).
  String? _openDocId;
  String? _openDocJson;

  void _go(_Screen s) => setState(() {
        _forward = s.index >= _screen.index;
        _screen = s;
      });

  bool get _signedIn => ref.read(authUserProvider).valueOrNull != null;

  void _newDocument(FormatStyle? style) => setState(() {
        _style = style ?? FormatStyle.mla;
        _openDocId = null;
        _openDocJson = null;
        _forward = true;
        _screen = _Screen.editor;
      });

  Future<void> _openDocument(String id) async {
    final svc = ref.read(essaysServiceProvider);
    if (svc == null) return;
    try {
      final doc = await svc.get(id);
      if (!mounted) return;
      setState(() {
        _openDocId = doc.id;
        _openDocJson = doc.content;
        _forward = true;
        _screen = _Screen.editor;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Couldn\'t open document: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Navigate only on real sign-in/out *transitions* (not steady state), so a
    // periodic token refresh — or visiting the welcome page while signed in —
    // never bounces the user around. First resolution (loading → signed-in)
    // restores a persisted session straight to the workspace.
    ref.listen(authUserProvider, (prev, next) {
      final was = prev?.valueOrNull != null;
      final now = next.valueOrNull != null;
      if (was == now) return;
      if (now && (_screen == _Screen.welcome || _screen == _Screen.loading)) {
        _go(_Screen.workspace);
      } else if (!now && _screen != _Screen.welcome) {
        _go(_Screen.welcome);
      }
    });

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
        return DocOctLoadingPage(
            onDone: () =>
                _go(_signedIn ? _Screen.workspace : _Screen.welcome));

      case _Screen.welcome:
        return WizardWelcomePage(
          onSpecifyTopic: () => _go(_Screen.setup),
          onStartWriting: () => _newDocument(_style),
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
          // Blank (no preset format) starts the new-document wizard; a format
          // template jumps straight into the editor. Either way, still signed in.
          onNewDocument: (style) =>
              style == null ? _go(_Screen.welcome) : _newDocument(style),
          onOpenDocument: _openDocument,
        );

      case _Screen.editor:
        return EditorPage(
          key: ValueKey(_openDocId ?? 'new'),
          initialStyle: _style,
          initialDocId: _openDocId,
          initialDocJson: _openDocJson,
          onBack: () {
            ref.invalidate(myDocumentsProvider); // pick up a new save
            _go(_signedIn ? _Screen.workspace : _Screen.welcome);
          },
        );
    }
  }
}
