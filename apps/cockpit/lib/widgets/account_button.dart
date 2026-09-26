import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:octo_notes/octo_notes.dart';
import 'package:study_studio/study_studio.dart';

/// Sign-in state of the app's one Firebase session (shared by every module).
final shellSignedInProvider = StreamProvider<bool>((ref) {
  return ref.watch(authServiceProvider).authStateChanges();
});

/// Top-bar account control: "Sign in with Google" when signed out; the
/// OctoCredits balance + avatar menu when signed in. Identity and the balance
/// come from the shared Octopilot account (`/v1/me`).
class AccountButton extends ConsumerWidget {
  const AccountButton({super.key});

  Future<void> _run(BuildContext context, Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Sign-in failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authServiceProvider);
    final signedIn = ref.watch(shellSignedInProvider).valueOrNull ?? auth.isSignedIn;
    if (!signedIn) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.sm),
        child: OutlinedButton.icon(
          onPressed: () => _run(context, auth.signIn),
          icon: const _GoogleMark(),
          label: const Text('Sign in with Google'),
        ),
      );
    }
    final me = ref.watch(notesMeProvider).valueOrNull;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (me?.octoCredits != null)
          Tooltip(
            message: 'OctoCredits',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt_rounded, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: CockpitSpacing.xs),
                Text(_credits(me!.octoCredits!), style: theme.textTheme.titleSmall),
              ],
            ),
          ),
        const SizedBox(width: CockpitSpacing.sm),
        PopupMenuButton<String>(
          tooltip: me?.email ?? 'Account',
          position: PopupMenuPosition.under,
          onSelected: (v) {
            if (v == 'signOut') _run(context, auth.signOut);
          },
          itemBuilder: (_) => [
            PopupMenuItem<String>(
              enabled: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(me?.displayName ?? 'Signed in', style: theme.textTheme.titleSmall),
                  if (me?.email != null)
                    Text(me!.email!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem<String>(value: 'signOut', child: Text('Sign out')),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.sm),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: scheme.surfaceContainerHighest,
              foregroundImage: me?.photoUrl == null ? null : NetworkImage(me!.photoUrl!),
              child: Text(me?.initial ?? '?', style: theme.textTheme.labelLarge),
            ),
          ),
        ),
      ],
    );
  }
}

/// 56485 → "56,485".
String _credits(int value) {
  final d = value.abs().toString();
  final b = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < d.length; i++) {
    if (i > 0 && (d.length - i) % 3 == 0) b.write(',');
    b.write(d[i]);
  }
  return b.toString();
}

/// The Google "G" in its four brand colours, drawn with text (no asset).
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (r) => const SweepGradient(
        colors: [Color(0xFF4285F4), Color(0xFF34A853), Color(0xFFFBBC05), Color(0xFFEA4335), Color(0xFF4285F4)],
      ).createShader(r),
      child: const Text('G', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
    );
  }
}
