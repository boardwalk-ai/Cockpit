import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';

import '../../domain/organization_controller.dart';

/// Panel 11 — Smart Organization. Detects structure and proposes an organized
/// version; nothing changes until the student applies, and every pass is
/// reversible ("Original Notes Preserved", spec §3, §7).
class OrganizePanel extends StatelessWidget {
  const OrganizePanel({
    super.key,
    required this.controller,
    required this.onClose,
  });

  final OrganizationController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(CockpitSpacing.lg,
                  CockpitSpacing.md, CockpitSpacing.sm, 0),
              child: Row(
                children: [
                  Text('Smart Organization', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: onClose,
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
                  Text('${controller.foundCount} suggestions found',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(height: CockpitSpacing.md),
            _Controls(controller: controller),
            const SizedBox(height: CockpitSpacing.sm),
            _ViewTabs(controller: controller),
            Divider(height: 1, color: scheme.outlineVariant),
            Expanded(
              child: switch (controller.view) {
                OrgView.suggestions => _SuggestionsView(controller: controller),
                OrgView.outline => _OutlineView(controller: controller),
                OrgView.categories => _CategoriesView(controller: controller),
              },
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            _Actions(controller: controller),
          ],
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller});
  final OrganizationController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
      child: Row(
        children: [
          PopupMenuButton<OrgScope>(
            tooltip: 'Organize scope',
            onSelected: controller.setScope,
            itemBuilder: (context) => [
              for (final s in OrgScope.values)
                PopupMenuItem(value: s, child: Text(s.label)),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: CockpitSpacing.sm, vertical: CockpitSpacing.xs),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(CockpitRadii.sm),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(controller.scope.label,
                      style: theme.textTheme.labelMedium),
                  const Icon(Icons.arrow_drop_down_rounded, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(width: CockpitSpacing.md),
          Switch(
            value: controller.autoOrganize,
            onChanged: controller.setAutoOrganize,
            activeThumbColor: Colors.white,
            activeTrackColor: scheme.primary,
          ),
          const SizedBox(width: CockpitSpacing.xs),
          Flexible(
            child: Text('Auto-Organize',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium),
          ),
          const Spacer(),
          _OrigPreviewToggle(controller: controller),
        ],
      ),
    );
  }
}

class _OrigPreviewToggle extends StatelessWidget {
  const _OrigPreviewToggle({required this.controller});
  final OrganizationController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget seg(bool organized, String label) {
      final sel = controller.showingOrganized == organized;
      return InkWell(
        borderRadius: BorderRadius.circular(CockpitRadii.sm),
        onTap: () => controller.setShowingOrganized(organized),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: CockpitSpacing.md, vertical: CockpitSpacing.xs),
          decoration: BoxDecoration(
            color: sel ? scheme.primary.withValues(alpha: 0.1) : null,
            borderRadius: BorderRadius.circular(CockpitRadii.sm),
            border: Border.all(
                color: sel ? scheme.primary : Colors.transparent),
          ),
          child: Text(label,
              style: theme.textTheme.labelMedium?.copyWith(
                  color: sel ? scheme.primary : scheme.onSurfaceVariant)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CockpitRadii.sm),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg(false, 'Original'),
          seg(true, 'Organized Preview'),
        ],
      ),
    );
  }
}

class _ViewTabs extends StatelessWidget {
  const _ViewTabs({required this.controller});
  final OrganizationController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget tab(OrgView v, String label) {
      final sel = controller.view == v;
      return InkWell(
        onTap: () => controller.setView(v),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: CockpitSpacing.md, vertical: CockpitSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: sel ? scheme.primary : scheme.onSurfaceVariant,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  )),
              const SizedBox(height: CockpitSpacing.xs),
              Container(
                  height: 2,
                  width: 24,
                  color: sel ? scheme.primary : Colors.transparent),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.md),
      child: Row(
        children: [
          tab(OrgView.suggestions, 'Suggestions'),
          tab(OrgView.outline, 'Outline'),
          tab(OrgView.categories, 'Categories'),
        ],
      ),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.controller});
  final OrganizationController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Wrap(
      spacing: CockpitSpacing.sm,
      runSpacing: CockpitSpacing.sm,
      children: [
        for (final c in controller.categories)
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: CockpitSpacing.md, vertical: CockpitSpacing.xs),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(CockpitRadii.sm),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(c.icon, size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: CockpitSpacing.xs),
                Text(c.label, style: theme.textTheme.labelMedium),
                const SizedBox(width: CockpitSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: CockpitSpacing.xs),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(CockpitRadii.pill),
                  ),
                  child: Text('${c.count}',
                      style: theme.textTheme.labelSmall),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SuggestionsView extends StatelessWidget {
  const _SuggestionsView({required this.controller});
  final OrganizationController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      children: [
        _CategoryChips(controller: controller),
        const SizedBox(height: CockpitSpacing.lg),
        Text('Proposed Outline', style: theme.textTheme.titleSmall),
        const SizedBox(height: CockpitSpacing.sm),
        _OutlineTree(node: controller.outline),
        const SizedBox(height: CockpitSpacing.lg),
        for (final s in controller.suggestions) ...[
          _SuggestionCard(controller: controller, suggestion: s),
          const SizedBox(height: CockpitSpacing.sm),
        ],
      ],
    );
  }
}

class _OutlineView extends StatelessWidget {
  const _OutlineView({required this.controller});
  final OrganizationController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      children: [
        Text('Proposed structure', style: theme.textTheme.titleSmall),
        const SizedBox(height: CockpitSpacing.sm),
        _OutlineTree(node: controller.outline),
        const SizedBox(height: CockpitSpacing.md),
        Text('Drag sections and blocks to reorder manually.',
            style: theme.textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _CategoriesView extends StatelessWidget {
  const _CategoriesView({required this.controller});
  final OrganizationController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      children: [
        Text('Detected categories', style: theme.textTheme.titleSmall),
        const SizedBox(height: CockpitSpacing.sm),
        for (final c in controller.categories)
          InkWell(
            borderRadius: BorderRadius.circular(CockpitRadii.sm),
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text('Highlighted ${c.count} ${c.label} blocks'))),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.sm),
              child: Row(
                children: [
                  Icon(c.icon, size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: CockpitSpacing.md),
                  Expanded(child: Text(c.label, style: theme.textTheme.bodyMedium)),
                  Text('${c.count}',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _OutlineTree extends StatelessWidget {
  const _OutlineTree({required this.node, this.depth = 0});
  final OutlineNode node;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(
              left: depth * 18.0, top: 3, bottom: 3),
          child: Row(
            children: [
              Icon(Icons.drag_indicator,
                  size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: CockpitSpacing.xs),
              if (node.children.isNotEmpty)
                Icon(Icons.keyboard_arrow_down_rounded,
                    size: 16, color: scheme.onSurfaceVariant),
              Icon(node.icon, size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: CockpitSpacing.sm),
              Expanded(
                child: Text(node.title,
                    style: depth == 0
                        ? theme.textTheme.titleSmall
                        : theme.textTheme.bodyMedium),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 16, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
        for (final child in node.children)
          _OutlineTree(node: child, depth: depth + 1),
      ],
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.controller, required this.suggestion});
  final OrganizationController controller;
  final OrgSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = suggestion;
    final confColor = s.confidence == OrgConfidence.high
        ? CockpitColors.brand.success
        : s.confidence == OrgConfidence.medium
            ? CockpitColors.brand.warning
            : scheme.primary;
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => controller.toggle(s.id),
            child: Padding(
              padding: const EdgeInsets.only(top: 1, right: CockpitSpacing.sm),
              child: Icon(
                  s.checked
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  size: 20,
                  color: s.checked ? scheme.primary : scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.title, style: theme.textTheme.bodyMedium),
                const SizedBox(height: CockpitSpacing.xxs),
                Text(s.reason,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: CockpitSpacing.sm),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: CockpitSpacing.sm, vertical: 1),
                      decoration: BoxDecoration(
                        color: confColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(CockpitRadii.sm),
                      ),
                      child: Text(s.confidence.label,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: confColor)),
                    ),
                    const SizedBox(width: CockpitSpacing.sm),
                    Text(s.blockLabel,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => controller.dismiss(s.id),
            style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: scheme.onSurfaceVariant),
            icon: const Icon(Icons.close_rounded, size: 14),
            label: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.controller});
  final OrganizationController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    void snack(String m) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));

    return Padding(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Preview summary (spec §7).
          Row(
            children: [
              Icon(Icons.auto_awesome_motion_rounded,
                  size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: CockpitSpacing.xs),
              Flexible(
                child: Text(
                    '${controller.sectionsCreated} sections created  ·  '
                    '${controller.blocksMoved} blocks moved  ·  '
                    '${controller.categoriesAssigned} categories assigned',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.md),
          Row(
            children: [
              FilledButton(
                onPressed: controller.canApply
                    ? () {
                        final n = controller.applySelected();
                        snack('Applied $n change${n == 1 ? '' : 's'} '
                            '(reversible)');
                      }
                    : null,
                child: const Text('Apply Selected'),
              ),
              const SizedBox(width: CockpitSpacing.sm),
              OutlinedButton(
                onPressed: () {
                  final n = controller.applyAll();
                  snack('Applied $n changes (reversible)');
                },
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: scheme.outline)),
                child: const Text('Apply All'),
              ),
              const Spacer(),
              TextButton(
                onPressed: controller.dismissAll,
                child: const Text('Dismiss'),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Row(
            children: [
              Icon(Icons.verified_user_rounded,
                  size: 14, color: CockpitColors.brand.success),
              const SizedBox(width: CockpitSpacing.xs),
              Expanded(
                child: Text('Original Notes Preserved — every change is reversible',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ),
              TextButton(
                onPressed: controller.canUndo ? controller.undoLast : null,
                child: const Text('Undo Last Organization'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
