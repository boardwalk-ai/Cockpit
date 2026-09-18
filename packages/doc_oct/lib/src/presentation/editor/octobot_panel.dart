import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';

import '../../application/assist_service.dart';
import '../../application/backend_config.dart';

const _octoRed = Color(0xFFEA4335);

const _tones = <({String id, String label})>[
  (id: 'mentor', label: 'Mentor'),
  (id: 'honest', label: 'Honest'),
  (id: 'roast', label: 'Roast'),
];

/// The floating "Octo the Bot" launcher (bottom-left of the editor). Tapping it
/// opens Octo's chat — an essay-critique assistant. Mirrors the web editor's
/// Octo launcher + chat window.
class OctoBotLauncher extends StatelessWidget {
  const OctoBotLauncher({super.key, required this.essayContext});

  /// Returns the current essay text so Octo can critique it.
  final String Function() essayContext;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _octoRed,
      shape: const StadiumBorder(),
      elevation: 4,
      shadowColor: _octoRed.withValues(alpha: 0.5),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => _openOcto(context, essayContext),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 11,
                backgroundColor: Colors.white,
                child: Text('🐙', style: TextStyle(fontSize: 12)),
              ),
              SizedBox(width: 8),
              Text('Octo the Bot',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4)),
            ],
          ),
        ),
      ),
    );
  }

  static void _openOcto(BuildContext context, String Function() essayContext) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Octo',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, _, _) {
        final slide = Tween<Offset>(
                begin: const Offset(-0.06, 0.08), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
        return Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: slide,
                child: _OctoWindow(essayContext: essayContext),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OctoMsg {
  _OctoMsg(this.role, this.text); // 'user' | 'assistant'
  final String role;
  final String text;
}

class _OctoWindow extends StatefulWidget {
  const _OctoWindow({required this.essayContext});
  final String Function() essayContext;

  @override
  State<_OctoWindow> createState() => _OctoWindowState();
}

class _OctoWindowState extends State<_OctoWindow> {
  final AssistService _assist = createAssistService();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_OctoMsg> _messages = [];
  String _tone = 'honest';
  String _mode = 'chat';
  bool _loading = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final msg = text.trim();
    if (msg.isEmpty || _loading) return;
    setState(() {
      _messages.add(_OctoMsg('user', msg));
      _input.clear();
      _loading = true;
    });
    _scrollToEnd();
    try {
      final reply = await _assist.chat(
        message: msg,
        history: _messages
            .map((m) => ChatTurn(m.role, m.text))
            .toList(growable: false),
        tone: _tone,
        mode: _mode,
        essay: widget.essayContext(),
      );
      if (mounted) setState(() => _messages.add(_OctoMsg('assistant', reply)));
    } catch (e) {
      if (mounted) {
        setState(() => _messages.add(_OctoMsg('assistant', 'Octo hit a snag: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 12,
      borderRadius: BorderRadius.circular(CockpitRadii.lg),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 360,
        height: 520,
        child: Column(
          children: [
            _header(theme, scheme),
            _toneBar(theme, scheme),
            Expanded(child: _body(theme, scheme)),
            _inputBar(theme, scheme),
          ],
        ),
      ),
    );
  }

  Widget _header(ThemeData theme, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.4))),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 12,
            backgroundColor: _octoRed,
            child: Text('🐙', style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 8),
          Text('Octo the Bot',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, size: 20),
            splashRadius: 18,
          ),
        ],
      ),
    );
  }

  Widget _toneBar(ThemeData theme, ColorScheme scheme) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: [
          for (final t in _tones)
            Padding(
              padding: const EdgeInsets.only(right: 6, top: 6, bottom: 6),
              child: GestureDetector(
                onTap: () => setState(() => _tone = t.id),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: _tone == t.id
                        ? _octoRed
                        : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(CockpitRadii.pill),
                  ),
                  child: Text(t.label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _tone == t.id
                              ? Colors.white
                              : scheme.onSurfaceVariant)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body(ThemeData theme, ColorScheme scheme) {
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(CockpitSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(
                radius: 22,
                backgroundColor: Color(0x1FEA4335),
                child: Text('🐙', style: TextStyle(fontSize: 22)),
              ),
              const SizedBox(height: CockpitSpacing.sm),
              Text('Octo is ready',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(_tone == 'roast' ? 'Brace yourself. 💀' : 'Ask for a critique.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: CockpitSpacing.md),
              OutlinedButton(
                onPressed: () {
                  setState(() => _mode = 'criticism');
                  _send('Yo Octo, criticize my essay');
                },
                style: OutlinedButton.styleFrom(
                    foregroundColor: _octoRed,
                    side: BorderSide(color: _octoRed.withValues(alpha: 0.4))),
                child: const Text('"Yo Octo, criticize my essay"'),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(CockpitSpacing.md),
      itemCount: _messages.length + (_loading ? 1 : 0),
      itemBuilder: (_, i) {
        if (i >= _messages.length) return _typing(scheme);
        final m = _messages[i];
        final isUser = m.role == 'user';
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            constraints: const BoxConstraints(maxWidth: 260),
            decoration: BoxDecoration(
              color: isUser
                  ? _octoRed
                  : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(14),
                topRight: const Radius.circular(14),
                bottomLeft: Radius.circular(isUser ? 14 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 14),
              ),
            ),
            child: Text(m.text,
                style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.4,
                    color: isUser ? Colors.white : scheme.onSurface)),
          ),
        );
      },
    );
  }

  Widget _typing(ColorScheme scheme) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const SizedBox(
            width: 30,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Dot(),
                _Dot(),
                _Dot(),
              ],
            ),
          ),
        ),
      );

  Widget _inputBar(ThemeData theme, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.4))),
      ),
      child: Column(
        children: [
          // Chat / Criticize mode switch
          Center(
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(CockpitRadii.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final m in const [('chat', 'Chat'), ('criticism', 'Criticize')])
                    GestureDetector(
                      onTap: () => setState(() => _mode = m.$1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: _mode == m.$1 ? _octoRed : Colors.transparent,
                          borderRadius: BorderRadius.circular(CockpitRadii.pill),
                        ),
                        child: Text(m.$2,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _mode == m.$1
                                    ? Colors.white
                                    : scheme.onSurfaceVariant)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _send,
                  decoration: InputDecoration(
                    hintText: _mode == 'criticism'
                        ? 'Ask Octo to criticize…'
                        : 'Message Octo…',
                    isDense: true,
                    filled: true,
                    fillColor:
                        scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(CockpitRadii.md),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Material(
                color: _octoRed,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _loading ? null : () => _send(_input.text),
                  child: const Padding(
                    padding: EdgeInsets.all(9),
                    child: Icon(Icons.send_rounded, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          shape: BoxShape.circle,
        ),
      );
}
