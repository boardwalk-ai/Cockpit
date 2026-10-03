import 'package:flutter/material.dart';

import '../chat/chat_controller.dart';
import '../chat/main_chat.dart';
import '../shell_theme.dart';
import '../widgets.dart';

/// The open conversation. Follows the reply as it streams.
class ShellMessageList extends StatefulWidget {
  const ShellMessageList({super.key, required this.conversation});

  final ChatController conversation;

  @override
  State<ShellMessageList> createState() => _ShellMessageListState();
}

class _ShellMessageListState extends State<ShellMessageList> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.conversation.addListener(_follow);
    _follow();
  }

  @override
  void didUpdateWidget(ShellMessageList old) {
    super.didUpdateWidget(old);
    if (old.conversation != widget.conversation) {
      old.conversation.removeListener(_follow);
      widget.conversation.addListener(_follow);
    }
  }

  @override
  void dispose() {
    widget.conversation.removeListener(_follow);
    _scroll.dispose();
    super.dispose();
  }

  void _follow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final conversation = widget.conversation;
    final streaming = conversation.streaming;
    final failure = conversation.failure;
    final c = ShellColors.of(context);
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        for (final message in conversation.messages)
          ShellColumn(child: _Bubble(message)),
        if (streaming != null)
          ShellColumn(
            child: streaming.isEmpty
                ? const _Thinking()
                : _Bubble(ChatMessage(ChatRole.assistant, streaming)),
          ),
        if (failure != null)
          ShellColumn(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                failure.message,
                style: TextStyle(color: c.accent, fontSize: 14),
              ),
            ),
          ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.message);

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    final text = TextStyle(color: c.text, fontSize: 15, height: 1.55);
    if (message.role == ChatRole.assistant) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: SelectableText(message.text, style: text),
      );
    }
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: c.raised,
            borderRadius: BorderRadius.circular(20),
          ),
          child: SelectableText(message.text, style: text),
        ),
      ),
    );
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text('Thinking…', style: TextStyle(color: c.hint, fontSize: 14)),
        ],
      ),
    );
  }
}
