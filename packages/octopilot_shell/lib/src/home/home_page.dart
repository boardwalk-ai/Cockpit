import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../chat/chat_controller.dart';
import '../shell_scope.dart';
import '../shell_theme.dart';
import '../widgets.dart';
import 'composer.dart';
import 'message_list.dart';
import 'mode_cards.dart';
import 'shell_drawer.dart';

/// Home: the main chat. A new conversation shows the three mode cards.
class ShellHomePage extends StatelessWidget {
  const ShellHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final services = ShellScope.of(context);
    final conversation = services.conversation;
    final c = ShellColors.of(context);

    return Scaffold(
      drawer: const ShellDrawer(),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: conversation,
          builder: (context, _) => Column(
            children: [
              ShellTopBar(
                title: 'Octopilot',
                leading: Builder(
                  builder: (context) => ShellIconButton(
                    icon: Icons.menu_rounded,
                    tooltip: 'Chats',
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                ),
                trailing: conversation.isEmpty
                    ? _AccountButton()
                    : ShellIconButton(
                        icon: Icons.edit_square,
                        tooltip: 'New chat',
                        onPressed: conversation.newChat,
                      ),
              ),
              Expanded(
                child: conversation.loading
                    ? Center(child: CircularProgressIndicator(color: c.accent))
                    : conversation.isEmpty && conversation.failure == null
                    ? const _Welcome()
                    : ShellMessageList(conversation: conversation),
              ),
              ShellColumn(child: _Composer(conversation: conversation)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final services = ShellScope.of(context);
    return ValueListenableBuilder(
      valueListenable: services.account,
      builder: (context, account, _) => IconButton(
        tooltip: 'Settings',
        onPressed: () => context.push('/settings'),
        icon: ShellAvatar(account: account),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight - 24),
          child: ShellColumn(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'What will you do today?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Pick a mode, or ask me anything about the app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.muted, fontSize: 14),
                ),
                const SizedBox(height: 24),
                const ModeCards(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.conversation});

  final ChatController conversation;

  @override
  Widget build(BuildContext context) => ShellComposer(
    replying: conversation.replying,
    onSend: conversation.send,
    onStop: conversation.stop,
  );
}
