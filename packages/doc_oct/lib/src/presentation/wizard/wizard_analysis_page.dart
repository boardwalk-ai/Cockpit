import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';

import '../../theme/doc_tokens.dart';
import '../widgets/doc_scaffold.dart';
import '../widgets/doc_top_bar.dart';
import '../widgets/doc_widgets.dart';
import 'wizard_primary_button.dart';
import 'wizard_shell.dart';

/// Wizard · Step 3 (analysis). The web's "Your assignment, decoded." — Octo's
/// breakdown of the prompt plus optional outline modes — restyled borderless:
/// the breakdown sits on a soft surface, fields are eyebrow + value pairs, and
/// the outline modes are borderless tiles that tint red when picked.
class WizardAnalysisPage extends StatefulWidget {
  const WizardAnalysisPage({
    super.key,
    required this.topic,
    required this.style,
    this.onBack,
    this.onContinue,
  });

  final String topic;
  final FormatStyle style;
  final VoidCallback? onBack;
  final VoidCallback? onContinue;

  @override
  State<WizardAnalysisPage> createState() => _WizardAnalysisPageState();
}

class _WizardAnalysisPageState extends State<WizardAnalysisPage> {
  // Phase-1 shell: no engine yet, so show a representative breakdown of the
  // prompt. (Phase 2 wires this to the real assignment analyzer.)
  int? _mode; // 0 = Build My Way, 1 = Auto Outline, 2 = One Paragraph

  String get _topic =>
      widget.topic.isEmpty ? 'your assignment prompt' : widget.topic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final fields = <(String, String)>[
      ('Topic', _topic),
      ('Essay type', 'Argumentative essay'),
      ('Scope', 'Focused — one core claim, 3–4 supporting points'),
      ('Structure', 'Intro · body paragraphs · counter-argument · conclusion'),
    ];

    return DocScaffold(
      child: SafeArea(
        child: Column(
          children: [
            const DocOctTopBar(),
            Expanded(
              child: WizardShell(
                step: 3,
                scroll: true,
                onBack: widget.onBack,
                eyebrow: 'Step three',
                headline: Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'Your assignment,\n'),
                    TextSpan(
                      text: 'decoded.',
                      style: TextStyle(color: scheme.primary),
                    ),
                  ]),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Octo broke down your prompt. Review it, optionally '
                      'generate an outline, then start writing.',
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: CockpitSpacing.xl),

                    // Breakdown
                    DocSurface(
                      padding: const EdgeInsets.all(CockpitSpacing.xl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'This prompt asks you to take a position and '
                                  'defend it with evidence. Keep the thesis '
                                  'arguable, and let each body paragraph carry '
                                  'one reason.',
                                ),
                              ),
                              const SizedBox(width: CockpitSpacing.md),
                              StyleTag(widget.style, dense: true),
                            ],
                          ),
                          const SizedBox(height: CockpitSpacing.lg),
                          Wrap(
                            spacing: CockpitSpacing.xxl,
                            runSpacing: CockpitSpacing.lg,
                            children: [
                              for (final (label, value) in fields)
                                SizedBox(
                                  width: 220,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Eyebrow(label),
                                      const SizedBox(height: CockpitSpacing.xxs),
                                      Text(
                                        value,
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: CockpitSpacing.lg),

                    // Continue (right-aligned)
                    Align(
                      alignment: Alignment.centerRight,
                      child: WizardPrimaryButton(
                        label: 'Continue to Editor',
                        dense: true,
                        onPressed: widget.onContinue,
                      ),
                    ),
                    const SizedBox(height: CockpitSpacing.xxl),

                    // Outline (optional)
                    Text.rich(
                      TextSpan(
                        style: theme.textTheme.titleMedium,
                        children: [
                          const TextSpan(text: 'Outline '),
                          TextSpan(
                            text: '(optional)',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: CockpitSpacing.xxs),
                    Text(
                      'Pick a mode, or skip and write freely.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: CockpitSpacing.md),
                    Row(
                      children: [
                        _OutlineMode(
                          icon: Icons.add_rounded,
                          label: 'Build My Way',
                          selected: _mode == 0,
                          onTap: () => setState(() => _mode = _mode == 0 ? null : 0),
                        ),
                        const SizedBox(width: CockpitSpacing.sm),
                        _OutlineMode(
                          icon: Icons.auto_awesome_rounded,
                          label: 'Auto Outline',
                          selected: _mode == 1,
                          onTap: () => setState(() => _mode = _mode == 1 ? null : 1),
                        ),
                        const SizedBox(width: CockpitSpacing.sm),
                        _OutlineMode(
                          icon: Icons.notes_rounded,
                          label: 'One Paragraph',
                          selected: _mode == 2,
                          onTap: () => setState(() => _mode = _mode == 2 ? null : 2),
                        ),
                      ],
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

class _OutlineMode extends StatelessWidget {
  const _OutlineMode({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Expanded(
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.12)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: CockpitSpacing.md,
              horizontal: CockpitSpacing.sm,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: accent),
                const SizedBox(height: CockpitSpacing.xs),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
