import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';

import '../../domain/ai_assistant_controller.dart';
import '../../domain/notes_controller.dart';

/// Panel 9 — Magic Bar & AI Assistant. Natural-language commands against precise
/// context, source-grounded suggestions, and a student-approval model. Never
/// changes notes without approval (spec §13).
class AiAssistantPanel extends StatefulWidget {
  const AiAssistantPanel({
    super.key,
    required this.controller,
    required this.notes,
    required this.onClose,
    required this.onResearch,
  });

  final AiAssistantController controller;
  final NotesController notes;
  final VoidCallback onClose;
  final VoidCallback onResearch;

  @override
  State<AiAssistantPanel> createState() => _AiAssistantPanelState();
}

class _AiAssistantPanelState extends State<AiAssistantPanel> {
  final _command = TextEditingController();
  final _followUp = TextEditingController();

  @override
  void dispose() {
    _command.dispose();
    _followUp.dispose();
    super.dispose();
  }

  void _run() {
    final t = _command.text;
    if (t.trim().isEmpty) return;
    widget.controller.run(t);
    _command.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = widget.controller;
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(CockpitSpacing.lg,
                  CockpitSpacing.md, CockpitSpacing.sm, 0),
              child: Row(
                children: [
                  Text('AI Assistant', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
              child: Row(
                children: [
                  Icon(Icons.circle, size: 8, color: CockpitColors.brand.success),
                  const SizedBox(width: CockpitSpacing.xs),
                  Text('Working with selected context',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(height: CockpitSpacing.md),
            _ContextChips(controller: c),
            const SizedBox(height: CockpitSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
              child: _CommandField(
                controller: _command,
                hint: 'Ask OctoNotes or type a command…',
                onSend: _run,
              ),
            ),
            const SizedBox(height: CockpitSpacing.md),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(CockpitSpacing.lg, 0,
                    CockpitSpacing.lg, CockpitSpacing.lg),
                children: [
                  if (c.generating)
                    _Generating()
                  else if (c.response != null)
                    _ResponseCard(
                      controller: c,
                      notes: widget.notes,
                      onResearch: widget.onResearch,
                      followUp: _followUp,
                    )
                  else
                    _EmptyPrompt(onQuick: (q) {
                      _command.text = q;
                      _run();
                    }),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(CockpitSpacing.lg, 0,
                  CockpitSpacing.lg, CockpitSpacing.md),
              child: Row(
                children: [
                  Icon(Icons.lock_outline_rounded,
                      size: 13, color: scheme.onSurfaceVariant),
                  const SizedBox(width: CockpitSpacing.xs),
                  Text('AI cannot change notes without approval',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ContextChips extends StatelessWidget {
  const _ContextChips({required this.controller});
  final AiAssistantController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: CockpitSpacing.sm,
            runSpacing: CockpitSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Using',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              for (var i = 0; i < controller.contexts.length; i++)
                _Chip(
                  label: controller.contexts[i].label,
                  onRemove: () => controller.removeContext(i),
                ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.sm),
          _ChangeContext(controller: controller),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onRemove});
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.only(
          left: CockpitSpacing.sm, right: CockpitSpacing.xs, top: 3, bottom: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(CockpitRadii.sm),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(width: CockpitSpacing.xs),
          InkWell(
            onTap: onRemove,
            child: Icon(Icons.close_rounded,
                size: 13, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ChangeContext extends StatelessWidget {
  const _ChangeContext({required this.controller});
  final AiAssistantController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PopupMenuButton<String>(
      tooltip: 'Change context',
      onSelected: (v) {
        if (v == 'section') controller.useWholeSection();
        if (v == 'session') controller.useWholeSession();
        if (v == 'block') {
          controller.addContext(const AiContext(
              type: AiContextType.block, label: 'Typewriter Block'));
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'block', child: Text('Add: current block')),
        PopupMenuItem(value: 'section', child: Text('Use Whole Section')),
        PopupMenuItem(value: 'session', child: Text('Use Whole Session (slower)')),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.swap_horiz_rounded, size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: CockpitSpacing.xs),
          Text('Change Context',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _CommandField extends StatelessWidget {
  const _CommandField({
    required this.controller,
    required this.hint,
    required this.onSend,
  });
  final TextEditingController controller;
  final String hint;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      onSubmitted: (_) => onSend(),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: CockpitSpacing.md, vertical: CockpitSpacing.md),
        suffixIcon: IconButton(
          icon: Icon(Icons.send_rounded, size: 18, color: scheme.primary),
          onPressed: onSend,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CockpitRadii.md),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CockpitRadii.md),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        filled: false,
      ),
    );
  }
}

class _Generating extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: CockpitSpacing.md),
          Text('Generating…',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _EmptyPrompt extends StatelessWidget {
  const _EmptyPrompt({required this.onQuick});
  final ValueChanged<String> onQuick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const quick = [
      'What did I miss?',
      'Explain this',
      'Expand keywords',
      'Simplify',
      'Summarize',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick commands',
            style: theme.textTheme.labelMedium
                ?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: CockpitSpacing.sm),
        Wrap(
          spacing: CockpitSpacing.sm,
          runSpacing: CockpitSpacing.sm,
          children: [
            for (final q in quick)
              ActionChip(
                label: Text(q),
                onPressed: () => onQuick(q),
              ),
          ],
        ),
        const SizedBox(height: CockpitSpacing.xl),
        Row(
          children: [
            Icon(Icons.auto_awesome_rounded,
                size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: CockpitSpacing.sm),
            Expanded(
              child: Text(
                'Results are grounded in your selected context and always show '
                'their sources. Your notes stay unchanged until you approve.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ResponseCard extends StatelessWidget {
  const _ResponseCard({
    required this.controller,
    required this.notes,
    required this.onResearch,
    required this.followUp,
  });
  final AiAssistantController controller;
  final NotesController notes;
  final VoidCallback onResearch;
  final TextEditingController followUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = controller.response!;
    void snack(String m) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(CockpitSpacing.lg),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(CockpitRadii.md),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 16, color: scheme.primary),
                  const SizedBox(width: CockpitSpacing.sm),
                  Text('AI Suggestion',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: scheme.primary)),
                ],
              ),
              const SizedBox(height: CockpitSpacing.xxs),
              Text(r.contextSummary,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: CockpitSpacing.md),
              Text(r.title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: CockpitSpacing.sm),

              if (r.isMissingPoints)
                ...[
                  for (final p in r.missingPoints)
                    _PointRow(
                        point: p, onToggle: () => controller.togglePoint(p)),
                ]
              else if (r.body != null)
                Text(r.body!, style: theme.textTheme.bodyMedium),

              if (r.conflict != null) ...[
                const SizedBox(height: CockpitSpacing.sm),
                _ConflictBox(text: r.conflict!),
              ],

              if (r.sources.isNotEmpty && !r.isMissingPoints) ...[
                const SizedBox(height: CockpitSpacing.md),
                Wrap(
                  spacing: CockpitSpacing.xs,
                  runSpacing: CockpitSpacing.xs,
                  children: [
                    for (final s in r.sources)
                      _SourceChip(label: s.chipLabel),
                  ],
                ),
              ],

              const SizedBox(height: CockpitSpacing.md),
              Row(
                children: [
                  Icon(
                      r.sourcesAgree
                          ? Icons.check_circle_rounded
                          : Icons.error_outline_rounded,
                      size: 15,
                      color: r.sourcesAgree
                          ? CockpitColors.brand.success
                          : scheme.primary),
                  const SizedBox(width: CockpitSpacing.xs),
                  Text(
                      r.sourcesAgree
                          ? 'Course sources agree'
                          : 'Possible conflict detected',
                      style: theme.textTheme.labelMedium?.copyWith(
                          color: r.sourcesAgree
                              ? CockpitColors.brand.success
                              : scheme.primary)),
                ],
              ),
              const SizedBox(height: CockpitSpacing.lg),
              Wrap(
                spacing: CockpitSpacing.sm,
                runSpacing: CockpitSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (r.isMissingPoints)
                    FilledButton(
                      onPressed: () {
                        final n = controller.insertSelected(notes);
                        snack('$n point${n == 1 ? '' : 's'} inserted');
                      },
                      child: const Text('Insert Selected'),
                    )
                  else
                    FilledButton(
                      onPressed: () {
                        controller.insertBelow(notes);
                        snack('Inserted below');
                      },
                      child: const Text('Insert Below'),
                    ),
                  OutlinedButton(
                    onPressed: () => snack('Added as pending suggestions'),
                    style: OutlinedButton.styleFrom(
                        side: BorderSide(color: scheme.outline)),
                    child: const Text('Add as Suggestions'),
                  ),
                  TextButton.icon(
                    onPressed: onResearch,
                    icon: const Icon(Icons.open_in_new_rounded, size: 15),
                    label: const Text('Research Further'),
                  ),
                  TextButton.icon(
                    onPressed: controller.dismiss,
                    style: TextButton.styleFrom(
                        foregroundColor: scheme.onSurfaceVariant),
                    icon: const Icon(Icons.close_rounded, size: 15),
                    label: const Text('Dismiss'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: CockpitSpacing.md),
        _CommandField(
          controller: followUp,
          hint: 'Ask a follow-up…',
          onSend: () {
            final t = followUp.text;
            if (t.trim().isEmpty) return;
            controller.run(t);
            followUp.clear();
          },
        ),
      ],
    );
  }
}

class _PointRow extends StatelessWidget {
  const _PointRow({required this.point, required this.onToggle});
  final MissingPoint point;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: CockpitSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.only(top: 1, right: CockpitSpacing.sm),
              child: Icon(
                  point.checked
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  size: 20,
                  color: point.checked ? scheme.primary : scheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(point.text, style: theme.textTheme.bodyMedium)),
          const SizedBox(width: CockpitSpacing.sm),
          _SourceChip(label: point.sourceLabel),
        ],
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CockpitRadii.sm),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(label,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: scheme.onSurfaceVariant)),
    );
  }
}

class _ConflictBox extends StatelessWidget {
  const _ConflictBox({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.md),
      decoration: BoxDecoration(
        color: CockpitColors.brand.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(CockpitRadii.sm),
        border: Border.all(
            color: CockpitColors.brand.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 16, color: CockpitColors.brand.warning),
          const SizedBox(width: CockpitSpacing.sm),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
