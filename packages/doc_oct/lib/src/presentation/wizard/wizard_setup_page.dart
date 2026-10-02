import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';

import '../../application/wizard_session.dart';
import '../../theme/doc_tokens.dart';
import '../widgets/doc_scaffold.dart';
import '../widgets/doc_top_bar.dart';
import '../widgets/doc_widgets.dart';
import '../widgets/motion.dart';
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
  late final TextEditingController _topic = TextEditingController(
    text: widget.initialTopic.isNotEmpty
        ? widget.initialTopic
        : (WizardSession.prompt.isNotEmpty
              ? WizardSession.prompt
              : WizardSession.topic),
  );
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
                headline: const [
                  TextSpan(text: 'Set up'),
                  TextSpan(text: 'your paper.'),
                ],
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
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                        ),
                        cursorColor: scheme.primary,
                        decoration: InputDecoration(
                          hintText:
                              'e.g. The impact of social media on mental health',
                          hintStyle: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 17,
                            fontWeight: FontWeight.w400,
                            color: scheme.onSurfaceVariant.withValues(
                              alpha: 0.55,
                            ),
                          ),
                          filled: true,
                          fillColor: scheme.surfaceContainerLow.withValues(
                            alpha: 0.6,
                          ),
                          // A hairline edge that turns red on focus.
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              CockpitRadii.md,
                            ),
                            borderSide: BorderSide(
                              color: scheme.onSurface.withValues(alpha: 0.08),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              CockpitRadii.md,
                            ),
                            borderSide: BorderSide(
                              color: scheme.primary.withValues(alpha: 0.7),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: CockpitSpacing.lg,
                            vertical: 18,
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

  Future<void> _continue() async {
    final topic = _topic.text.trim();
    await WizardSession.savePrompt(topic);
    widget.onAnalyze?.call(topic, _style);
  }
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
    return Pressable(
      child: Material(
        color: selected
            ? style.color.withValues(alpha: 0.12)
            : scheme.surfaceContainerLow.withValues(alpha: 0.6),
        shape: StadiumBorder(
          side: BorderSide(
            color: selected
                ? style.color.withValues(alpha: 0.55)
                : scheme.onSurface.withValues(alpha: 0.06),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              CockpitSpacing.sm,
              CockpitSpacing.sm,
              CockpitSpacing.md,
              CockpitSpacing.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The style's logo — lit when chosen, dimmed otherwise.
                StyleMonogram(style, active: selected),
                const SizedBox(width: CockpitSpacing.sm),
                Text(
                  style.short,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: selected
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
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
