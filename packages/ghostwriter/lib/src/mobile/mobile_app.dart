import 'package:flutter/material.dart';

import '../session/gw_session.dart';
import 'mobile_ai_settings.dart';
import 'mobile_background.dart';
import 'mobile_chat.dart';
import 'mobile_drawer.dart';
import 'mobile_editor.dart';
import 'mobile_landing.dart';
import 'mobile_octo_sheet.dart';
import 'mobile_theme.dart';
import 'mobile_top_bar.dart';

/// GhostWriter on a phone: the landing screen until an essay is started or
/// opened, then its chat. Everything comes from [session].
class GhostWriterMobileApp extends StatefulWidget {
  const GhostWriterMobileApp({
    super.key,
    required this.session,
    this.onSignOut,
  });

  final GwSession session;

  /// Null hides sign-out (dev builds without a real sign-in).
  final VoidCallback? onSignOut;

  @override
  State<GhostWriterMobileApp> createState() => _GhostWriterMobileAppState();
}

class _GhostWriterMobileAppState extends State<GhostWriterMobileApp>
    with WidgetsBindingObserver {
  final TextEditingController _prompt = TextEditingController();
  final TextEditingController _composer = TextEditingController();

  GwSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    session.load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A run keeps going while the app is away; catch up on coming back.
    if (state == AppLifecycleState.resumed) {
      session.reconnect();
      session.refreshLibrary();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _prompt.dispose();
    _composer.dispose();
    super.dispose();
  }

  void _start() {
    final brief = _prompt.text.trim();
    if (brief.isEmpty) return;
    _prompt.clear();
    session.start(brief);
  }

  void _openEditor() {
    final project = session.projectId;
    if (project == null) return;
    openGwEditor(context, api: session.api, projectId: project);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final name = session.userName;
        return Scaffold(
          backgroundColor: GwColors.background,
          drawerScrimColor: Colors.black.withValues(alpha: 0.55),
          drawerEdgeDragWidth: 36,
          drawer: GhostWriterMobileDrawer(
            projects: session.projects,
            folders: session.folders,
            loading: session.loadingLibrary,
            selectedId: session.projectId,
            sessionName: name ?? 'GUEST',
            credits: session.credits ?? 0,
            onNewChat: session.newChat,
            onOpenProject: session.openProject,
            onRefresh: session.refreshLibrary,
            onSignOut: widget.onSignOut,
            onSettings: () => showGwAiSettings(context, api: session.api),
          ),
          body: GwBackground(
            child: SafeArea(
              child: Column(
                children: [
                  GhostWriterMobileTopBar(
                    credits: session.credits ?? 0,
                    saving: false,
                    onAskOcto: () =>
                        showGwOctoSheet(context, ask: session.api.askOcto),
                  ),
                  if (session.libraryError case final error?)
                    _Notice(message: error, onRetry: session.load),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 380),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: session.hasProject
                          ? KeyedSubtree(
                              key: ValueKey('chat-${session.projectId}'),
                              child: GhostWriterMobileChat(
                                session: session,
                                composer: _composer,
                                onOpenEditor: _openEditor,
                              ),
                            )
                          : ValueListenableBuilder<TextEditingValue>(
                              key: const ValueKey('landing'),
                              valueListenable: _prompt,
                              builder: (context, value, _) =>
                                  GhostWriterMobileLanding(
                                    controller: _prompt,
                                    canStart: value.text.trim().isNotEmpty,
                                    userName: name,
                                    onChanged: (_) {},
                                    onStart: _start,
                                  ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A plain line under the top bar when the account or the list failed to load.
class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 8, 2),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 17,
            color: Color(0xFFFF777D),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: kGwBody.copyWith(
                fontSize: 13,
                height: 1.35,
                color: const Color(0xFFFF9A9E),
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text(
              'Retry',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
