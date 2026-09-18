import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/auth_providers.dart';

/// The top-bar account control: a "Sign in" pill when signed out, or the octo
/// credits + avatar (with a sign-out menu) when signed in. Mirrors the web
/// editor's credits/profile chip.
class AuthChip extends ConsumerWidget {
  const AuthChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final user = ref.watch(authUserProvider).valueOrNull;
    final auth = ref.read(docAuthProvider);

    if (user == null) {
      return _SignInPill(onTap: () => _signIn(context, ref));
    }

    final me = ref.watch(meProvider).valueOrNull;
    final credits = me?.octoCredits;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (credits != null)
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(CockpitRadii.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.token_rounded, size: 13, color: scheme.primary),
                const SizedBox(width: 5),
                Text(_fmt(credits),
                    style: TextStyle(
                        color: scheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                const SizedBox(width: 4),
                Text('CREDITS',
                    style: TextStyle(
                        color: scheme.primary.withValues(alpha: 0.7),
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5)),
              ],
            ),
          ),
        PopupMenuButton<String>(
          tooltip: user.email ?? 'Account',
          onSelected: (v) {
            if (v == 'signout') auth.signOut();
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              enabled: false,
              child: Text(user.email ?? user.name ?? 'Signed in',
                  style: theme.textTheme.bodySmall),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'signout', child: Text('Sign out')),
          ],
          child: CircleAvatar(
            radius: 14,
            backgroundColor: scheme.primary.withValues(alpha: 0.15),
            foregroundImage:
                user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
            child: Text(
              (user.name ?? user.email ?? '?').characters.first.toUpperCase(),
              style: TextStyle(
                  color: scheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
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

  static String _fmt(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}

class _SignInPill extends StatelessWidget {
  const _SignInPill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.login_rounded, size: 15),
      label: const Text('Sign in'),
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.primary,
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.4)),
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}
