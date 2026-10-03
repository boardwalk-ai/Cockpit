import 'package:flutter/material.dart';

import '../shell_theme.dart';

/// The message box. While a reply streams, send turns into stop.
class ShellComposer extends StatefulWidget {
  const ShellComposer({
    super.key,
    required this.replying,
    required this.onSend,
    required this.onStop,
  });

  final bool replying;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;

  @override
  State<ShellComposer> createState() => _ShellComposerState();
}

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
    widget.onSend(text);
    _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    final stop = widget.replying;
    final canSend = _text.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 4, 6, 4),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: c.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _text,
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
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: IconButton(
                tooltip: stop ? 'Stop' : 'Send',
                onPressed: stop ? widget.onStop : (canSend ? _send : null),
                style: IconButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  backgroundColor: stop || canSend ? c.accent : c.raised,
                  disabledBackgroundColor: c.raised,
                ),
                icon: Icon(
                  stop ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                  color: stop || canSend ? c.onAccent : c.hint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
