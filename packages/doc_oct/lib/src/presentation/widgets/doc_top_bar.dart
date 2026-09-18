import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/auth_providers.dart';
import '../../application/essays_service.dart';

/// The Doc Oct top bar, borderless: the "Octopilot Doc Oct" wordmark on the
/// left; Save · credits · avatar on the right. Auth-aware — real octo credits
/// when signed in, and the avatar signs in (signed out) or opens the account
/// card with Log Out (signed in).
class DocOctTopBar extends ConsumerWidget {
  const DocOctTopBar({super.key, this.onSave});

  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final user = ref.watch(authUserProvider).valueOrNull;
    final me = ref.watch(meProvider).valueOrNull;
    final credits = user != null ? me?.octoCredits : null;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CockpitSpacing.xl,
        vertical: CockpitSpacing.md,
      ),
      child: Row(
        children: [
          Text.rich(
            TextSpan(
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
              children: [
                TextSpan(
                    text: 'Octopilot ',
                    style: TextStyle(color: scheme.primary)),
                const TextSpan(text: 'Doc Oct'),
              ],
            ),
          ),
          const Spacer(),
          if (onSave != null)
            TextButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.bookmark_border_rounded, size: 18),
              label: const Text('Save'),
              style:
                  TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
            ),
          if (credits != null) ...[
            const SizedBox(width: CockpitSpacing.md),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt_rounded, size: 16, color: scheme.tertiary),
                const SizedBox(width: 4),
                Text(_fmt(credits),
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: 4),
                Text('credits',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ],
          const SizedBox(width: CockpitSpacing.lg),
          InkWell(
            onTap: () {
              if (user == null) {
                _signIn(context, ref);
              } else {
                _showAccountCard(context, ref, user, me);
              }
            },
            customBorder: const CircleBorder(),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: user == null
                  ? scheme.surfaceContainerHigh
                  : scheme.primary.withValues(alpha: 0.15),
              foregroundImage: user?.photoUrl != null
                  ? NetworkImage(user!.photoUrl!)
                  : null,
              child: user == null
                  ? Icon(Icons.person_outline_rounded,
                      size: 18, color: scheme.onSurfaceVariant)
                  : Text(
                      (user.name ?? user.email ?? '?')
                          .characters
                          .first
                          .toUpperCase(),
                      style: TextStyle(
                          color: scheme.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _signIn(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(docAuthProvider).signIn();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign-in failed: $e')),
        );
      }
    }
  }

  void _showAccountCard(
      BuildContext context, WidgetRef ref, dynamic user, Me? me) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final theme = Theme.of(dialogCtx);
        final scheme = theme.colorScheme;
        return Dialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CockpitRadii.lg)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Padding(
              padding: const EdgeInsets.all(CockpitSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: scheme.primary.withValues(alpha: 0.15),
                        foregroundImage: user.photoUrl != null
                            ? NetworkImage(user.photoUrl as String)
                            : null,
                        child: user.photoUrl == null
                            ? Text(
                                ((user.name ?? user.email ?? '?') as String)
                                    .characters
                                    .first
                                    .toUpperCase(),
                                style: TextStyle(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w700))
                            : null,
                      ),
                      const SizedBox(width: CockpitSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (user.name != null)
                              Text(user.name as String,
                                  style: theme.textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700)),
                            if (user.email != null)
                              Text(user.email as String,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (me != null) ...[
                    const SizedBox(height: CockpitSpacing.lg),
                    _creditRow(theme, 'Octo credits', me.octoCredits),
                    _creditRow(theme, 'Words', me.wordCredits),
                    _creditRow(theme, 'Sources', me.sourceCredits),
                    _creditRow(theme, 'Humanizer', me.humanizerCredits),
                  ],
                  const SizedBox(height: CockpitSpacing.lg),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.of(dialogCtx).pop();
                      ref.read(docAuthProvider).signOut();
                    },
                    icon: const Icon(Icons.logout_rounded, size: 16),
                    label: const Text('Log out'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _creditRow(ThemeData theme, String label, int value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            Text(_fmt(value),
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      );

  static String _fmt(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i != 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}
