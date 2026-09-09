import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';

/// The Doc Oct top bar, borderless: the "Octopilot Doc Oct" wordmark on the
/// left; Save · (optional credits) · avatar on the right. No boxes — just type,
/// spacing and a couple of soft affordances.
class DocOctTopBar extends StatelessWidget {
  const DocOctTopBar({super.key, this.credits, this.onSave, this.onAvatarTap});

  /// When signed in, the Octocredits balance (e.g. 56085).
  final int? credits;
  final VoidCallback? onSave;

  /// Tapping the avatar (used to toggle the signed-in preview state).
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
          TextButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.bookmark_border_rounded, size: 18),
            label: const Text('Save'),
            style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
          ),
          if (credits != null) ...[
            const SizedBox(width: CockpitSpacing.md),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt_rounded, size: 16, color: scheme.tertiary),
                const SizedBox(width: 4),
                Text(_fmt(credits!),
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
            onTap: onAvatarTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(Icons.person_outline_rounded,
                  size: 18, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

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
