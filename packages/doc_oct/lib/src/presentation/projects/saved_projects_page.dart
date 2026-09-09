import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../domain/saved_project.dart';
import '../../theme/doc_tokens.dart';
import '../widgets/doc_scaffold.dart';
import '../widgets/doc_widgets.dart';

/// Screen 1 — **Saved Projects**. The Doc Oct home: your saved documents, and
/// the way in to a new one (which opens the wizard). Borderless throughout.
class SavedProjectsPage extends ConsumerWidget {
  const SavedProjectsPage({super.key, this.onNew, this.onOpen});

  /// Opens the new-document wizard.
  final VoidCallback? onNew;

  /// Opens an existing project (→ editor, Phase 2).
  final void Function(SavedProject project)? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(savedProjectsProvider);
    final wide = MediaQuery.sizeOf(context).width >= 720;

    return DocScaffold(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1140),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    wide ? DocSpacing.xxl : DocSpacing.lg,
                    DocSpacing.xxl,
                    wide ? DocSpacing.xxl : DocSpacing.lg,
                    DocSpacing.md,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _Header(count: projects.length, onNew: onNew),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    wide ? DocSpacing.xxl : DocSpacing.lg,
                    DocSpacing.sm,
                    wide ? DocSpacing.xxl : DocSpacing.lg,
                    DocSpacing.xxxl,
                  ),
                  sliver: projects.isEmpty
                      ? SliverToBoxAdapter(child: _EmptyState(onNew: onNew))
                      : SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 372,
                            mainAxisSpacing: DocSpacing.lg,
                            crossAxisSpacing: DocSpacing.lg,
                            mainAxisExtent: 208,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) {
                              if (i == 0) return _NewProjectTile(onNew: onNew);
                              final p = projects[i - 1];
                              return _ProjectCard(
                                project: p,
                                onTap: () => onOpen?.call(p),
                              );
                            },
                            childCount: projects.length + 1,
                          ),
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

class _Header extends StatelessWidget {
  const _Header({required this.count, this.onNew});
  final int count;
  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 720;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DocEyebrow('Doc Oct'),
              const SizedBox(height: DocSpacing.md),
              Text(
                'Your documents',
                style: (wide
                        ? theme.textTheme.displaySmall
                        : theme.textTheme.headlineMedium)
                    ?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: DocSpacing.sm),
              Text(
                '$count saved · pick up where you left off, or start something new.',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        if (wide) ...[
          const SizedBox(width: DocSpacing.lg),
          FilledButton.icon(
            onPressed: onNew,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('New document'),
          ),
        ],
      ],
    );
  }
}

/// The strong CTA tile that opens the wizard. Red-tinted borderless panel.
class _NewProjectTile extends StatelessWidget {
  const _NewProjectTile({this.onNew});
  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DocPanel(
      onTap: onNew,
      color: scheme.primary.withValues(alpha: 0.10),
      padding: const EdgeInsets.all(DocSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(DocRadii.md),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.5),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
          ),
          const Spacer(),
          Text(
            'New document',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Upload, paste, or start blank —\nwe format the rest.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.3,
                ),
          ),
        ],
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, this.onTap});
  final SavedProject project;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DocPanel(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DocStyleBadge(style: project.style),
              const Spacer(),
              Icon(Icons.more_horiz_rounded,
                  size: 20, color: scheme.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: DocSpacing.md),
          Text(
            project.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: Text(
              project.snippet,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: DocSpacing.md),
          Row(
            children: [
              DocChip(label: project.style.short, color: project.style.color,
                  dense: true),
              const SizedBox(width: DocSpacing.sm),
              Flexible(
                child: Text(
                  '${project.words} words · ${project.pages} pp · '
                  '${_relative(project.updatedAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
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
      padding: const EdgeInsets.only(top: DocSpacing.xxl),
      child: DocPanel(
        padding: const EdgeInsets.all(DocSpacing.xxxl),
        child: Column(
          children: [
            Icon(Icons.description_outlined,
                size: 44, color: scheme.onSurfaceVariant),
            const SizedBox(height: DocSpacing.lg),
            Text('No documents yet',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: DocSpacing.xs),
            Text(
              'Start your first academic paper — upload, paste, or write from scratch.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: DocSpacing.xl),
            FilledButton.icon(
              onPressed: onNew,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('New document'),
            ),
          ],
        ),
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
