import 'dart:async';

import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_providers.dart';
import '../application/wizard_session.dart';
import '../theme/doc_tokens.dart';
import 'editor/editor_page.dart';
import 'loading/doc_oct_loading_page.dart';
import 'widgets/motion.dart';
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

  @override
  void initState() {
    super.initState();
    unawaited(WizardSession.init());
  }

  /// When opening a saved document: its id + serialized state (else null = new).
  String? _openDocId;
  String? _openDocJson;

  /// Loading animation finished. Auth may still be resolving a persisted session.
  bool _introDone = false;

  void _go(_Screen s) => setState(() {
    _screen = s;
  });

  bool get _signedIn => ref.read(authUserProvider).valueOrNull != null;

  void _leaveLoadingIfReady() {
    if (_screen != _Screen.loading || !_introDone) return;
    final auth = ref.read(authUserProvider);
    if (auth.isLoading) return;
    _go(auth.valueOrNull != null ? _Screen.workspace : _Screen.welcome);
  }

  /// A new document without the topic wizard — so no topic/analysis/outline
  /// from an earlier session may leak in; the editor asks for a topic itself.
  void _newDocument(FormatStyle? style) => setState(() {
    unawaited(WizardSession.clear());
    _topic = '';
    _style = style ?? FormatStyle.mla;
    _openDocId = null;
    _openDocJson = null;
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
        _screen = _Screen.editor;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Couldn\'t open document: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep the loading screen up until Firebase has finished reading the
    // persisted session. A 2.6s animation finishing first used to dump signed-in
    // users onto the guest wizard because `ref.listen` does not fire for the
    // provider's initial value.
    ref.watch(authUserProvider);
    ref.listen(authUserProvider, (prev, next) {
      if (_screen == _Screen.loading) {
        _leaveLoadingIfReady();
        return;
      }
      final was = prev?.valueOrNull != null;
      final now = next.valueOrNull != null;
      if (was == now) return;
      // The wizard session lives in this browser's storage — don't hand one
      // user's topic/analysis/outlines to the next account on the machine.
      if (!now) unawaited(WizardSession.clear());
      if (now && _screen == _Screen.welcome) {
        _go(_Screen.workspace);
      } else if (!now && _screen != _Screen.welcome) {
        _go(_Screen.welcome);
      }
    });

    // Every screen change is a camera-shutter blink ([BlinkSwitcher]); the motion
    // theme gives every button under Doc Oct ripples + hover/press states.
    return Theme(
      data: docMotionTheme(Theme.of(context)),
      child: BlinkSwitcher(pageKey: _screen, child: _current()),
    );
  }

  Widget _current() {
    switch (_screen) {
      case _Screen.loading:
        return DocOctLoadingPage(
          onDone: () {
            _introDone = true;
            _leaveLoadingIfReady();
          },
        );

      case _Screen.welcome:
        return WizardWelcomePage(
          onSpecifyTopic: () => _go(_Screen.setup),
          onStartWriting: () => _newDocument(_style),
        );

      case _Screen.setup:
        return WizardSetupPage(
          initialTopic: _topic.isNotEmpty ? _topic : WizardSession.prompt,
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
