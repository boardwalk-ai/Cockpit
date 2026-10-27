import 'package:flutter/material.dart';

import '../aurora.dart';
import '../motion.dart';
import '../shell_scope.dart';
import '../shell_theme.dart';
import '../voice/voice_picker.dart';
import '../widgets.dart';

/// The app's settings: everything that is about the whole app, not one
/// module.
class ShellSettingsPage extends StatelessWidget {
  const ShellSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final services = ShellScope.of(context);
    final c = ShellColors.of(context);

    Widget? row(
      IconData icon,
      String title,
      void Function(BuildContext)? action, {
      String? value,
    }) {
      if (action == null) return null;
      return _Row(
        icon: icon,
        title: title,
        value: value,
        onTap: () => action(context),
      );
    }

    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: Column(
            children: [
              ShellTopBar(
                title: 'Settings',
                leading: ShellIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              Expanded(
                child: ValueListenableBuilder(
                  valueListenable: services.account,
                  builder: (context, account, _) => ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      ShellColumn(
                        maxWidth: 640,
                        child: _Staggered(
                          children: [
                            _Card(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      ShellAvatar(account: account, size: 52),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              account?.name ?? 'Not signed in',
                                              style: TextStyle(
                                                color: c.text,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            if (account?.email != null)
                                              Text(
                                                account!.email!,
                                                style: TextStyle(
                                                  color: c.muted,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            if (account?.plan != null)
                                              Text(
                                                account!.plan!,
                                                style: TextStyle(
                                                  color: c.hint,
                                                  fontSize: 11,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const _Label('AI'),
                            _Card(
                              children: [
                                row(
                                  Icons.auto_awesome_outlined,
                                  'Model and personality',
                                  services.onAiSettings,
                                ),
                                if (services.voices.isNotEmpty)
                                  ValueListenableBuilder(
                                    valueListenable: services.voiceId,
                                    builder: (context, _, _) => _Row(
                                      icon: Icons.graphic_eq_rounded,
                                      title: 'Voice',
                                      value: services.currentVoice?.name,
                                      onTap: () => showVoicePicker(context),
                                    ),
                                  ),
                              ],
                            ),
                            const _Label('App'),
                            _Card(
                              children: [
                                row(
                                  Icons.notifications_none_rounded,
                                  'Notifications',
                                  services.onNotifications,
                                ),
                                const _Appearance(),
                              ],
                            ),
                            const _Label('Account'),
                            _Card(
                              children: [
                                row(
                                  Icons.bolt_rounded,
                                  'OctoCredits',
                                  services.onCredits,
                                  value: account?.credits == null
                                      ? null
                                      : formatCredits(account!.credits!),
                                ),
                                row(
                                  Icons.info_outline_rounded,
                                  'About, privacy and terms',
                                  services.onAbout,
                                ),
                                if (account == null &&
                                    services.onSignIn != null)
                                  _SignInRow(signIn: services.onSignIn!),
                                if (account != null &&
                                    services.onSignOut != null)
                                  _Row(
                                    icon: Icons.logout_rounded,
                                    title: 'Sign out',
                                    onTap: () => services.onSignOut!(),
                                  ),
                              ],
                            ),
                            if (account != null &&
                                services.onDeleteAccount != null) ...[
                              const SizedBox(height: 20),
                              _Card(
                                children: [
                                  _Row(
                                    icon: Icons.delete_outline_rounded,
                                    title: 'Delete account',
                                    danger: true,
                                    onTap: () => _deleteAccount(context),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final services = ShellScope.of(context);
    final c = ShellColors.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('Delete your account?', style: TextStyle(color: c.text)),
        content: Text(
          'Your account, chats, essays and notes are deleted for good, and '
          "your OctoCredits are lost. You can't undo this.",
          style: TextStyle(color: c.muted, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: c.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete account', style: TextStyle(color: c.accent)),
          ),
        ],
      ),
    );
    if ((yes ?? false) && context.mounted) {
      await services.onDeleteAccount!(context);
    }
  }
}

/// Settings sections, each coming in a moment after the one above.
class _Staggered extends StatelessWidget {
  const _Staggered({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, child) in children.indexed)
        Reveal(
          delay: Duration(milliseconds: 60 * i),
          offset: const Offset(0, 0.2),
          scale: 0.98,
          child: child,
        ),
    ],
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 22, 6, 8),
    child: Text(
      text,
      style: TextStyle(
        color: ShellColors.of(context).hint,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    ),
  );
}

/// A rounded group of rows; null rows are left out.
class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget?> children;

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    final rows = children.whereType<Widget>().toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return Material(
      clipBehavior: Clip.antiAlias,
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: c.border),
      ),
      child: Column(
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) Divider(height: 1, indent: 52, color: c.border),
            row,
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.onTap,
    this.value,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    final color = danger ? c.accent : c.text;
    return ListTile(
      leading: Icon(icon, color: danger ? c.accent : c.muted),
      title: Text(title, style: TextStyle(color: color, fontSize: 13)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            Text(value!, style: TextStyle(color: c.muted, fontSize: 12)),
          if (!danger) Icon(Icons.chevron_right_rounded, color: c.hint),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _Appearance extends StatelessWidget {
  const _Appearance();

  @override
  Widget build(BuildContext context) {
    final services = ShellScope.of(context);
    final c = ShellColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.contrast_rounded, color: c.muted),
              const SizedBox(width: 16),
              Text('Appearance', style: TextStyle(color: c.text, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder(
            valueListenable: services.themeMode,
            builder: (context, mode, _) => SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  foregroundColor: c.muted,
                  selectedForegroundColor: c.onAccent,
                  selectedBackgroundColor: c.accent,
                  side: BorderSide(color: c.border),
                ),
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('System')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ],
                selected: {mode},
                onSelectionChanged: (s) => services.setThemeMode(s.first),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Sign in with Google": a spinner while the account picker and the server
/// are busy, and a plain message if it didn't work.
class _SignInRow extends StatefulWidget {
  const _SignInRow({required this.signIn});

  final Future<void> Function() signIn;

  @override
  State<_SignInRow> createState() => _SignInRowState();
}

class _SignInRowState extends State<_SignInRow> {
  bool _busy = false;

  Future<void> _go() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    try {
      await widget.signIn();
    } on Object catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text("Couldn't sign in. Check your connection and try again. ($e)")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    return ListTile(
      leading: Icon(Icons.login_rounded, color: c.muted),
      title: Text(
        _busy ? 'Signing in…' : 'Sign in with Google',
        style: TextStyle(color: c.text, fontSize: 13),
      ),
      trailing: _busy
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
            )
          : Icon(Icons.chevron_right_rounded, color: c.hint),
      onTap: _busy ? null : _go,
    );
  }
}
