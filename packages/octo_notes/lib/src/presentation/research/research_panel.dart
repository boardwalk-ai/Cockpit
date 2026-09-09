import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';

import '../../domain/notes_controller.dart';
import '../../domain/research_controller.dart';

/// Panel 10 — Research & Explanations. Course materials first, then trusted
/// external sources, with per-claim evidence and student approval. The source
/// excerpt stays visually distinct from the AI explanation (spec §26).
class ResearchPanel extends StatefulWidget {
  const ResearchPanel({
    super.key,
    required this.controller,
    required this.notes,
    required this.onClose,
  });

  final ResearchController controller;
  final NotesController notes;
  final VoidCallback onClose;

  @override
  State<ResearchPanel> createState() => _ResearchPanelState();
}

class _ResearchPanelState extends State<ResearchPanel> {
  late final TextEditingController _q =
      TextEditingController(text: widget.controller.question);
  final _followUp = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    _followUp.dispose();
    super.dispose();
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
                  Text('Research & Explanations',
                      style: theme.textTheme.titleMedium),
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
                  Icon(Icons.circle, size: 8, color: scheme.primary),
                  const SizedBox(width: CockpitSpacing.xs),
                  Text('Researching selected question',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(height: CockpitSpacing.md),
            _ContextChips(controller: c),
            const SizedBox(height: CockpitSpacing.sm),
            _ScopeSelector(controller: c),
            const SizedBox(height: CockpitSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
              child: TextField(
                controller: _q,
                onSubmitted: c.run,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Research question',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search_rounded, size: 18),
                    onPressed: () => c.run(_q.text),
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
              ),
            ),
            const SizedBox(height: CockpitSpacing.md),
            Expanded(
              child: c.searching
                  ? _Searching()
                  : c.result == null
                      ? const _EmptyState()
                      : _Results(
                          controller: c,
                          notes: widget.notes,
                          followUp: _followUp,
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
                  Text('Nothing enters your notes without approval',
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
  final ResearchController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
      child: Wrap(
        spacing: CockpitSpacing.sm,
        runSpacing: CockpitSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Using',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          for (var i = 0; i < controller.contexts.length; i++)
            _Chip(
              label: controller.contexts[i],
              onRemove: () => controller.removeContext(i),
            ),
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

class _ScopeSelector extends StatelessWidget {
  const _ScopeSelector({required this.controller});
  final ResearchController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget seg(ResearchScope s, IconData icon, String label) {
      final sel = controller.scope == s;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(CockpitRadii.sm),
          onTap: () => controller.setScope(s),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.sm),
            decoration: BoxDecoration(
              color: sel ? scheme.primary.withValues(alpha: 0.1) : null,
              borderRadius: BorderRadius.circular(CockpitRadii.sm),
              border: Border.all(
                  color: sel ? scheme.primary : scheme.outlineVariant),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 15,
                    color: sel ? scheme.primary : scheme.onSurfaceVariant),
                const SizedBox(width: CockpitSpacing.xs),
                Text(label,
                    style: theme.textTheme.labelMedium?.copyWith(
                        color: sel ? scheme.primary : scheme.onSurface)),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              seg(ResearchScope.courseFirst, Icons.menu_book_rounded,
                  'Course Sources First'),
              const SizedBox(width: CockpitSpacing.sm),
              seg(ResearchScope.external, Icons.public_rounded,
                  'External Sources'),
            ],
          ),
          const SizedBox(height: CockpitSpacing.xs),
          Text('Course materials searched first',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: CockpitColors.brand.success)),
        ],
      ),
    );
  }
}

class _Searching extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(height: CockpitSpacing.md),
          Text('Searching course materials first…',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.travel_explore_rounded,
      title: 'Research a question',
      message: 'Ask a question above. Course materials are searched before any '
          'external sources, and every claim links to evidence.',
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.controller,
    required this.notes,
    required this.followUp,
  });
  final ResearchController controller;
  final NotesController notes;
  final TextEditingController followUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = controller.result!;
    void snack(String m) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          CockpitSpacing.lg, 0, CockpitSpacing.lg, CockpitSpacing.lg),
      children: [
        // Supported Explanation (AI interpretation — visually distinct).
        Container(
          padding: const EdgeInsets.all(CockpitSpacing.lg),
          decoration: BoxDecoration(
            color: CockpitColors.brand.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(CockpitRadii.md),
            border: Border.all(
                color: CockpitColors.brand.success.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Supported Explanation',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: CockpitColors.brand.success)),
                  const Spacer(),
                  Icon(Icons.verified_user_rounded,
                      size: 15, color: CockpitColors.brand.success),
                  const SizedBox(width: CockpitSpacing.xs),
                  Text('${r.agreeCount} sources agree',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: CockpitColors.brand.success)),
                ],
              ),
              const SizedBox(height: CockpitSpacing.sm),
              Text(r.explanation, style: theme.textTheme.bodyMedium),
              const SizedBox(height: CockpitSpacing.sm),
              Text('Every claim is linked to evidence',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        const SizedBox(height: CockpitSpacing.lg),
        Text('Evidence', style: theme.textTheme.titleSmall),
        const SizedBox(height: CockpitSpacing.sm),
        for (final s in r.evidence) ...[
          _EvidenceCard(source: s),
          const SizedBox(height: CockpitSpacing.sm),
        ],
        const SizedBox(height: CockpitSpacing.sm),
        Wrap(
          spacing: CockpitSpacing.sm,
          runSpacing: CockpitSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton(
              onPressed: () {
                controller.addAsExplanation(notes);
                snack('Added as explanation');
              },
              child: const Text('Add as Explanation'),
            ),
            OutlinedButton(
              onPressed: () {
                controller.insertBelow(notes);
                snack('Inserted below');
              },
              style: OutlinedButton.styleFrom(
                  side: BorderSide(color: scheme.outline)),
              child: const Text('Insert Below'),
            ),
            OutlinedButton(
              onPressed: () => snack('Saved to Research'),
              style: OutlinedButton.styleFrom(
                  side: BorderSide(color: scheme.outline)),
              child: const Text('Save Research'),
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
        const SizedBox(height: CockpitSpacing.md),
        TextField(
          controller: followUp,
          onSubmitted: (v) {
            if (v.trim().isEmpty) return;
            controller.run(v);
            followUp.clear();
          },
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Ask a follow-up…',
            suffixIcon: const Icon(Icons.send_rounded, size: 18),
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
        ),
      ],
    );
  }
}

/// An evidence card (spec §12). Source excerpt is kept separate from the AI
/// summary; external sources are clearly labeled (spec §16, §26).
class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({required this.source});
  final ResearchSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = source;
    final badgeColor = s.kind.isExternal
        ? CockpitColors.brand.info
        : CockpitColors.brand.success;
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(CockpitSpacing.xs),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(CockpitRadii.sm),
                ),
                child: Icon(s.kind.icon, size: 16, color: badgeColor),
              ),
              const SizedBox(width: CockpitSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _tag(context, s.kind.label,
                            s.kind.isExternal ? scheme.primary : badgeColor),
                        if (s.kind.isExternal) ...[
                          const SizedBox(width: CockpitSpacing.xs),
                          Text('External Source',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                        const Spacer(),
                        Text(s.locator,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: CockpitSpacing.xs),
                    Text(s.title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: CockpitSpacing.xxs),
                    // The original source excerpt (never merged with AI text).
                    Text(s.excerpt, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: CockpitSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _tag(context, s.kind.qualityBadge, badgeColor),
                  const SizedBox(height: CockpitSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        side: BorderSide(color: scheme.outlineVariant)),
                    icon: const Icon(Icons.open_in_new_rounded, size: 14),
                    label: Text(s.openLabel),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tag(BuildContext context, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: CockpitSpacing.sm, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(CockpitRadii.sm),
        ),
        child: Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: color)),
      );
}
