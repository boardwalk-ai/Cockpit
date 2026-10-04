import 'package:flutter/material.dart';

import 'shell_models.dart';
import 'shell_theme.dart';

/// A round icon button for the top bars.
class ShellIconButton extends StatelessWidget {
  const ShellIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      color: c.text,
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        backgroundColor: c.raised.withValues(alpha: 0.6),
      ),
    );
  }
}

/// The account's photo, or its initials.
class ShellAvatar extends StatelessWidget {
  const ShellAvatar({super.key, required this.account, this.size = 32});

  final ShellAccount? account;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    final photo = account?.photoUrl;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: c.accent.withValues(alpha: 0.18),
      foregroundImage: photo == null ? null : NetworkImage(photo),
      child: account == null
          ? Icon(Icons.person_outline, size: size * 0.55, color: c.accent)
          : Text(
              account!.initials,
              style: TextStyle(
                color: c.accent,
                fontSize: size * 0.36,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}

/// Top bar: [leading], a centred title, [trailing].
class ShellTopBar extends StatelessWidget {
  const ShellTopBar({
    super.key,
    required this.title,
    this.leading,
    this.trailing,
  });

  final String title;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            SizedBox(width: 48, child: leading),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(width: 48, child: trailing),
          ],
        ),
      ),
    );
  }
}

/// Keeps content readable on tablets and desktop.
class ShellColumn extends StatelessWidget {
  const ShellColumn({super.key, required this.child, this.maxWidth = 720});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}

/// OctoCredits, written short: 1,240 · 12.5k.
String formatCredits(int credits) {
  if (credits >= 10000) {
    final k = credits / 1000;
    return '${k.toStringAsFixed(k >= 100 ? 0 : 1)}k';
  }
  final s = credits.toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}
