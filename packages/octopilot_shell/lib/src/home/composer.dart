import 'package:flutter/material.dart';

import '../motion.dart';
import '../shell_theme.dart';

/// The message box. Its button is the mic while empty, send once there is
/// text, and stop while a reply streams.
class ShellComposer extends StatefulWidget {
  const ShellComposer({
    super.key,
    required this.replying,
    required this.onSend,
    required this.onStop,
    this.onVoice,
    this.focusNode,
  });

  final bool replying;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;

  /// Back to talking. Null hides the mic.
  final VoidCallback? onVoice;
  final FocusNode? focusNode;

  @override
  State<ShellComposer> createState() => _ShellComposerState();
}

enum _Action { stop, send, voice, none }

class _ShellComposerState extends State<ShellComposer> {
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final text = _text.text.trim();
    if (text.isEmpty || widget.replying) return;
    Haptics.tap();
    widget.onSend(text);
    _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    final action = widget.replying
        ? _Action.stop
        : _text.text.trim().isNotEmpty
        ? _Action.send
        : widget.onVoice != null
        ? _Action.voice
        : _Action.none;
    final focused = widget.focusNode?.hasFocus ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: AnimatedContainer(
        duration: motion(context, const Duration(milliseconds: 260)),
        padding: const EdgeInsets.fromLTRB(18, 4, 6, 4),
        decoration: BoxDecoration(
          color: c.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: focused ? c.accent.withValues(alpha: 0.6) : c.border,
          ),
          boxShadow: [
            BoxShadow(
              color: (focused ? c.accent : Colors.black).withValues(
                alpha: focused ? 0.18 : 0.12,
              ),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Focus(
                onFocusChange: (_) => setState(() {}),
                child: TextField(
                  controller: _text,
                  focusNode: widget.focusNode,
                  minLines: 1,
                  maxLines: 6,
                  textInputAction: TextInputAction.newline,
                  style: TextStyle(color: c.text, fontSize: 15, height: 1.4),
                  cursorColor: c.accent,
                  decoration: InputDecoration(
                    hintText: 'Message Octopilot',
                    hintStyle: TextStyle(color: c.hint),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: AnimatedSwitcher(
                duration: motion(context, const Duration(milliseconds: 260)),
                transitionBuilder: (child, a) => RotationTransition(
                  turns: Tween(begin: -0.15, end: 0.0).animate(a),
                  child: ScaleTransition(scale: a, child: child),
                ),
                child: _button(c, action),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _button(ShellColors c, _Action action) {
    final (icon, tooltip, onTap, filled) = switch (action) {
      _Action.stop => (Icons.stop_rounded, 'Stop', widget.onStop, true),
      _Action.send => (Icons.arrow_upward_rounded, 'Send', _send, true),
      _Action.voice => (Icons.graphic_eq_rounded, 'Talk', widget.onVoice, true),
      _Action.none => (Icons.arrow_upward_rounded, 'Send', null, false),
    };
    return Tooltip(
      key: ValueKey(action),
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Pressable(
          scale: 0.86,
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: filled ? c.accent : c.raised,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: filled ? c.onAccent : c.hint),
          ),
        ),
      ),
    );
  }
}
