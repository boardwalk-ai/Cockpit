import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';

import '../../theme/doc_tokens.dart';
import '../widgets/doc_scaffold.dart';
import '../widgets/doc_top_bar.dart';
import 'wizard_primary_button.dart';
import 'wizard_shell.dart';

/// Wizard · Step 2 (setup). The web's "Set up your paper." — a topic field and
/// the five citation-format choices — restyled borderless: an eyebrow label, a
/// soft-filled input, and pill choices that tint to the style's own colour.
class WizardSetupPage extends StatefulWidget {
  const WizardSetupPage({
    super.key,
    this.onBack,
    this.onAnalyze,
    this.initialTopic = '',
    this.initialStyle = FormatStyle.mla,
  });

  final VoidCallback? onBack;

  /// Called with the entered topic + chosen style when the user continues.
  final void Function(String topic, FormatStyle style)? onAnalyze;
  final String initialTopic;
  final FormatStyle initialStyle;

  @override
  State<WizardSetupPage> createState() => _WizardSetupPageState();
}

class _WizardSetupPageState extends State<WizardSetupPage> {
  late final TextEditingController _topic =
      TextEditingController(text: widget.initialTopic);
  late FormatStyle _style = widget.initialStyle;

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

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
                step: 2,
                onBack: widget.onBack,
                eyebrow: 'Step two',
                headline: const Text('Set up\nyour paper.'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Topic
                    Text(
                      'ESSAY TOPIC OR ASSIGNMENT PROMPT',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: CockpitSpacing.sm),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _topic,
                      builder: (context, _, _) => TextField(
                        controller: _topic,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w500),
                        cursorColor: scheme.primary,
                        decoration: InputDecoration(
                          hintText:
                              'e.g. The impact of social media on mental health',
                          filled: true,
                          fillColor: scheme.surfaceContainerLow,
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(CockpitRadii.md),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: CockpitSpacing.lg,
                            vertical: CockpitSpacing.lg,
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _continue(),
                      ),
                    ),
                    const SizedBox(height: CockpitSpacing.xxl),

                    // Citation format
                    Text(
                      'CITATION FORMAT',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: CockpitSpacing.md),
                    Wrap(
                      spacing: CockpitSpacing.sm,
                      runSpacing: CockpitSpacing.sm,
                      children: [
                        for (final s in FormatStyle.values)
                          _FormatPill(
                            style: s,
                            selected: _style == s,
                            onTap: () => setState(() => _style = s),
                          ),
                      ],
                    ),
                    const SizedBox(height: CockpitSpacing.xxxl),

                    WizardPrimaryButton(
                      label: _topic.text.trim().isEmpty
                          ? 'Open Editor'
                          : 'Analyze & Continue',
                      onPressed: _continue,
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

  void _continue() => widget.onAnalyze?.call(_topic.text.trim(), _style);
}

class _FormatPill extends StatelessWidget {
  const _FormatPill({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final FormatStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: selected
          ? style.color.withValues(alpha: 0.16)
          : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CockpitSpacing.md,
            vertical: CockpitSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration:
                    BoxDecoration(color: style.color, shape: BoxShape.circle),
                child: Text(
                  style.abbr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: CockpitSpacing.sm),
              Text(
                style.short,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
