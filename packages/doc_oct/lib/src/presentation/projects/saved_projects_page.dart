import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../domain/saved_project.dart';
import '../../theme/doc_tokens.dart';
import '../widgets/doc_scaffold.dart';
import '../widgets/doc_widgets.dart';

/// Screen 1 — **Saved Projects**. Doc Oct's home: your documents as a clean,
/// borderless list, and the one red action that opens the new-document wizard.
class SavedProjectsPage extends ConsumerWidget {
  const SavedProjectsPage({super.key, this.onNew, this.onOpen});

  final VoidCallback? onNew;
  final void Function(SavedProject project)? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(savedProjectsProvider);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return DocScaffold(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                wide ? CockpitSpacing.xxxl : CockpitSpacing.lg,
                wide ? CockpitSpacing.xxxl : CockpitSpacing.xl,
                wide ? CockpitSpacing.xxxl : CockpitSpacing.lg,
                CockpitSpacing.xxxl,
              ),
              children: [
                _Header(count: projects.length, onNew: onNew),
                const SizedBox(height: CockpitSpacing.xxxl),
                if (projects.isEmpty)
                  _EmptyState(onNew: onNew)
                else ...[
                  const Eyebrow('Recent'),
                  const SizedBox(height: CockpitSpacing.lg),
                  for (final p in projects)
                    _ProjectRow(project: p, onTap: () => onOpen?.call(p)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count, this.onNew});
  final int count;
  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('Doc Oct'),
              const SizedBox(height: CockpitSpacing.md),
              Text('Documents', style: theme.textTheme.headlineMedium),
              const SizedBox(height: CockpitSpacing.xs),
              Text(
                '$count saved · pick up where you left off, or start a new paper.',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: CockpitSpacing.lg),
        FilledButton.icon(
          onPressed: onNew,
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('New document'),
        ),
      ],
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({required this.project, this.onTap});
  final SavedProject project;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final meta = [
      project.style.short,
      '${project.words} words',
      '${project.pages} pp',
      _relative(project.updatedAt),
    ].join('  ·  ');

    return DocHoverRow(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: CockpitSpacing.md,
        vertical: CockpitSpacing.lg,
      ),
      child: Row(
        children: [
          // style dot
          Container(
            width: 10,
            height: 10,
            decoration:
                BoxDecoration(color: project.style.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: CockpitSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: CockpitSpacing.xxs),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: CockpitSpacing.md),
          Icon(Icons.chevron_right_rounded,
              size: 22, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.onNew});
  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: CockpitSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Nothing here yet'),
          const SizedBox(height: CockpitSpacing.lg),
          Text('Start your first paper',
              style: theme.textTheme.headlineSmall),
          const SizedBox(height: CockpitSpacing.sm),
          Text(
            'Upload, paste, or write from scratch — Doc Oct handles the formatting.',
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: CockpitSpacing.xl),
          FilledButton.icon(
            onPressed: onNew,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('New document'),
          ),
        ],
      ),
    );
  }
}

/// Compact relative time — "2h ago", "yesterday", "3d ago".
String _relative(DateTime t) {
  final now = DateTime(2026, 9, 9, 14, 30);
  final d = now.difference(t);
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays == 1) return 'yesterday';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${(d.inDays / 7).floor()}w ago';
}
