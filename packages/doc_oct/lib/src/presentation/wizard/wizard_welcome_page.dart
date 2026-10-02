import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';

import '../widgets/doc_scaffold.dart';
import '../widgets/doc_top_bar.dart';
import '../widgets/motion.dart';
import 'wizard_shell.dart';

/// Wizard · Step 1 (logged-out welcome). The web's entry, restyled borderless:
/// a display headline on the left, and two entry choices on the right.
class WizardWelcomePage extends StatelessWidget {
  const WizardWelcomePage({
    super.key,
    this.onSpecifyTopic,
    this.onStartWriting,
  });

  final VoidCallback? onSpecifyTopic;
  final VoidCallback? onStartWriting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DocScaffold(
      child: SafeArea(
        child: Column(
          children: [
            const DocOctTopBar(),
            Expanded(
              child: WizardShell(
                step: 1,
                eyebrow: 'Academic formatting, automated',
                headline: [
                  const TextSpan(text: 'Write with precision.'),
                  TextSpan(
                    text: 'Cite with confidence.',
                    style: TextStyle(color: scheme.primary),
                  ),
                ],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Text(
                        'Format your essays to exact style guidelines — MLA, '
                        'APA, Chicago, IEEE, Harvard — every margin, indent, '
                        'and citation handled automatically.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.65,
                        ),
                      ),
                    ),
                    const SizedBox(height: CockpitSpacing.xxl),
                    _EntryOptions(
                      onSpecifyTopic: onSpecifyTopic,
                      onStartWriting: onStartWriting,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryOptions extends StatelessWidget {
  const _EntryOptions({this.onSpecifyTopic, this.onStartWriting});
  final VoidCallback? onSpecifyTopic;
  final VoidCallback? onStartWriting;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 620;
    final a = _EntryCard(
      primary: true,
      icon: Icons.search_rounded,
      title: 'Specify my topic',
      subtitle: 'Premium features + source search',
      cta: 'Start',
      onTap: onSpecifyTopic,
      fill: !narrow,
    );
    final b = _EntryCard(
      primary: false,
      icon: Icons.edit_note_rounded,
      title: 'Start writing',
      subtitle: 'Jump straight in — disposable session',
      cta: 'Open editor',
      onTap: onStartWriting,
      fill: !narrow,
    );
    if (narrow) {
      return Column(
        children: [
          a,
          const SizedBox(height: CockpitSpacing.md),
          b,
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: a),
          const SizedBox(width: CockpitSpacing.md),
          Expanded(child: b),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.primary,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.cta,
    this.onTap,
    this.fill = false,
  });

  final bool primary;
  final IconData icon;
  final String title;
  final String subtitle;
  final String cta;
  final VoidCallback? onTap;

  /// Side by side (equal heights): pin the CTA row to the card's bottom so
  /// both cards' links line up.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = primary ? scheme.primary : scheme.onSurface;
    // Both cards share one neutral fill and a hairline edge; the primary
    // choice is marked by a red edge + red icon badge, not a red wash (which
    // turned muddy on the charcoal).
    final radius = BorderRadius.circular(CockpitRadii.lg);
    return Pressable(
      enabled: onTap != null,
      glowColor: primary ? scheme.primary : null,
      borderRadius: radius,
      pressedScale: 0.97,
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: primary
                ? scheme.primary.withValues(alpha: 0.45)
                : scheme.onSurface.withValues(alpha: 0.07),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(CockpitSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (primary ? scheme.primary : scheme.onSurface)
                        .withValues(alpha: primary ? 0.14 : 0.06),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: primary ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: CockpitSpacing.xl),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: CockpitSpacing.xs),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: CockpitSpacing.lg),
                if (fill) const Spacer(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      cta,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_rounded, size: 15, color: accent),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
