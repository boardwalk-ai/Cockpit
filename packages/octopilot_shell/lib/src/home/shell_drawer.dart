import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../chat/main_chat.dart';
import '../motion.dart';
import '../shell_scope.dart';
import '../shell_theme.dart';
import '../widgets.dart';

/// The main chat's history. Module chats are not here.
class ShellDrawer extends StatefulWidget {
  const ShellDrawer({super.key});

  @override
  State<ShellDrawer> createState() => _ShellDrawerState();
}

class _ShellDrawerState extends State<ShellDrawer> {
  var _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ShellScope.of(context).chat.refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = ShellScope.of(context);
    final conversation = services.conversation;
    final c = ShellColors.of(context);

    void close() => Navigator.of(context).pop();

    return Drawer(
      backgroundColor: c.surface,
      width: 300,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 10, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Chats',
                      style: TextStyle(
                        color: c.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'New chat',
                    color: c.text,
                    icon: const Icon(Icons.edit_square),
                    onPressed: () {
                      conversation.newChat();
                      close();
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: TextField(
                onChanged: (q) => setState(() => _query = q.trim()),
                style: TextStyle(color: c.text, fontSize: 14),
                cursorColor: c.accent,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search chats',
                  hintStyle: TextStyle(color: c.hint),
                  prefixIcon: Icon(Icons.search_rounded, color: c.hint),
                  filled: true,
                  fillColor: c.raised.withValues(alpha: 0.6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: services.chat.threads,
                builder: (context, threads, _) {
                  final q = _query.toLowerCase();
                  final shown = [
                    for (final t in threads)
                      if (q.isEmpty || t.title.toLowerCase().contains(q)) t,
                  ];
                  if (shown.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        threads.isEmpty
                            ? 'Your chats show up here.'
                            : 'No chats match "$_query".',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.hint, fontSize: 14),
                      ),
                    );
                  }
                  return ListenableBuilder(
                    listenable: conversation,
                    builder: (context, _) => ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      children: [
                        for (final (i, thread) in shown.indexed)
                          Reveal(
                            key: ValueKey(thread.id),
                            delay: Duration(milliseconds: 40 * (i % 12)),
                            offset: const Offset(-0.12, 0),
                            scale: 1,
                            child: _ThreadTile(
                              thread: thread,
                              selected: thread.id == conversation.threadId,
                              onOpen: () {
                                conversation.open(thread.id);
                                close();
                              },
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Divider(height: 1, color: c.border),
            ValueListenableBuilder(
              valueListenable: services.account,
              builder: (context, account, _) => ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: ShellAvatar(account: account, size: 36),
                title: Text(
                  account?.name ?? 'Account',
                  style: TextStyle(color: c.text, fontWeight: FontWeight.w600),
                ),
                subtitle: account?.credits == null
                    ? null
                    : Text(
                        '${formatCredits(account!.credits!)} OctoCredits',
                        style: TextStyle(color: c.muted, fontSize: 12),
                      ),
                trailing: Icon(Icons.settings_outlined, color: c.muted),
                onTap: () {
                  close();
                  context.push('/settings');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({
    required this.thread,
    required this.selected,
    required this.onOpen,
  });

  final ChatThread thread;
  final bool selected;
  final VoidCallback onOpen;

  Future<void> _menu(BuildContext context) async {
    final services = ShellScope.of(context);
    final c = ShellColors.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.drive_file_rename_outline, color: c.text),
              title: Text('Rename', style: TextStyle(color: c.text)),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: c.accent),
              title: Text('Delete', style: TextStyle(color: c.accent)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'rename':
        final title = await _askTitle(context, thread.title);
        if (title != null && title.isNotEmpty) {
          await services.chat.rename(thread.id, title);
        }
      case 'delete':
        if (await _confirmDelete(context)) {
          if (services.conversation.threadId == thread.id) {
            services.conversation.newChat();
          }
          await services.chat.delete(thread.id);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: ListTile(
        dense: true,
        selected: selected,
        selectedTileColor: c.raised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          thread.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: c.text, fontSize: 14),
        ),
        trailing: IconButton(
          tooltip: 'Chat options',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.more_horiz_rounded, color: c.hint, size: 20),
          onPressed: () => _menu(context),
        ),
        onTap: onOpen,
        onLongPress: () => _menu(context),
      ),
    );
  }
}

Future<String?> _askTitle(BuildContext context, String current) =>
    showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(current: current),
    );

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.current});

  final String current;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _text = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    return AlertDialog(
      backgroundColor: c.surface,
      title: Text('Rename chat', style: TextStyle(color: c.text)),
      content: TextField(
        controller: _text,
        autofocus: true,
        style: TextStyle(color: c.text),
        cursorColor: c.accent,
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: c.muted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _text.text.trim()),
          child: Text('Save', style: TextStyle(color: c.accent)),
        ),
      ],
    );
  }
}

Future<bool> _confirmDelete(BuildContext context) async {
  final c = ShellColors.of(context);
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: c.surface,
      title: Text('Delete chat?', style: TextStyle(color: c.text)),
      content: Text(
        "This chat is deleted for good. You can't undo this.",
        style: TextStyle(color: c.muted),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel', style: TextStyle(color: c.muted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('Delete', style: TextStyle(color: c.accent)),
        ),
      ],
    ),
  );
  return yes ?? false;
}
