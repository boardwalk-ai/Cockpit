import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';

import '../widgets/doc_scaffold.dart';
import '../widgets/doc_top_bar.dart';
import 'wizard_shell.dart';

/// Wizard · Step 1 (logged-out welcome). The web's entry, restyled borderless:
/// a display headline on the left, and two entry choices on the right.
class WizardWelcomePage extends StatelessWidget {
  const WizardWelcomePage({super.key, this.onSpecifyTopic, this.onStartWriting});

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
                headline: Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'Write with precision.\n'),
                    TextSpan(
                      text: 'Cite with confidence.',
                      style: TextStyle(color: scheme.primary),
                    ),
                  ]),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Format your essays to exact style guidelines — MLA, APA, '
                      'Chicago, IEEE, Harvard — every margin, indent, and '
                      'citation handled automatically.',
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(color: scheme.onSurfaceVariant),
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
    );
    final b = _EntryCard(
      primary: false,
      icon: Icons.edit_note_rounded,
      title: 'Start writing',
      subtitle: 'Jump straight in — disposable session',
      cta: 'Open editor',
      onTap: onStartWriting,
    );
    if (narrow) {
      return Column(children: [
        a,
        const SizedBox(height: CockpitSpacing.md),
        b,
      ]);
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
  });

  final bool primary;
  final IconData icon;
  final String title;
  final String subtitle;
  final String cta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = primary ? scheme.primary : scheme.onSurface;
    // Borderless: a soft fill, no outline. The primary choice carries a faint
    // red wash + red accent; the secondary stays neutral.
    return Material(
      color: primary
          ? scheme.primary.withValues(alpha: 0.10)
          : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(CockpitRadii.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(CockpitSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 22,
                  color: primary ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(height: CockpitSpacing.xl),
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: CockpitSpacing.xxs),
              Text(subtitle,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: CockpitSpacing.md),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(cta,
                      style: theme.textTheme.labelMedium?.copyWith(
                          color: accent, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, size: 15, color: accent),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
