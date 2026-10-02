import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/auth_providers.dart';
import '../../application/essays_service.dart';
import '../../theme/doc_tokens.dart';
import '../widgets/doc_scaffold.dart';
import '../widgets/doc_top_bar.dart';
import '../widgets/doc_widgets.dart';
import '../widgets/motion.dart';
import '../widgets/reveal.dart';

/// The logged-in home — the web's "Your Doc Oct workspace". Start a new
/// document from a template, or reopen a recent one. Restyled borderless: no
/// card outlines or glows; the paper thumbnails and whitespace do the grouping.
class WorkspacePage extends ConsumerWidget {
  const WorkspacePage({super.key, this.onNewDocument, this.onOpenDocument});

  /// A template was chosen (null = Blank).
  final void Function(FormatStyle? style)? onNewDocument;

  /// A saved document was opened (by id).
  final void Function(String id)? onOpenDocument;

  static const _docLimit = 10;

  static const _templates = <(FormatStyle?, String, String)>[
    (null, 'Blank', 'No format'),
    (FormatStyle.mla, 'MLA Paper', 'MLA 9th'),
    (FormatStyle.apa, 'APA Paper', 'APA 7th'),
    (FormatStyle.ieee, 'IEEE Paper', 'IEEE'),
    (FormatStyle.chicago, 'Chicago Paper', 'Chicago'),
    (FormatStyle.harvard, 'Harvard Paper', 'Harvard'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final docs = ref.watch(myDocumentsProvider).valueOrNull ?? const [];

    return DocScaffold(
      child: SafeArea(
        child: Column(
          children: [
            const DocOctTopBar(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: CockpitSpacing.xxxl,
                  vertical: CockpitSpacing.xxl,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1080),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Greeting
                          Text.rich(
                            TextSpan(
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              children: [
                                const TextSpan(text: 'Your '),
                                TextSpan(
                                  text: 'Doc Oct',
                                  style: TextStyle(color: scheme.primary),
                                ),
                                const TextSpan(text: ' workspace'),
                              ],
                            ),
                          ),
                          const SizedBox(height: CockpitSpacing.xs),
                          Text(
                            'Start a new paper or pick up where you left off — '
                            'everything autosaves.',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: CockpitSpacing.xxl),

                          // Templates
                          const Eyebrow('Start a new document'),
                          const SizedBox(height: CockpitSpacing.md),
                          Wrap(
                            spacing: CockpitSpacing.lg,
                            runSpacing: CockpitSpacing.lg,
                            children: [
                              for (final (i, (style, label, sub))
                                  in _templates.indexed)
                                Reveal(
                                  delay: Duration(milliseconds: 60 * i),
                                  child: _TemplateCard(
                                    style: style,
                                    label: label,
                                    sub: sub,
                                    onTap: () => onNewDocument?.call(style),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: CockpitSpacing.xxxl),

                          // Recent
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              const Eyebrow('Recent documents'),
                              const SizedBox(width: CockpitSpacing.sm),
                              Text(
                                '${docs.length} / $_docLimit',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: docs.length >= _docLimit
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: CockpitSpacing.md),
                          if (docs.isEmpty)
                            _EmptyRecent()
                          else
                            Wrap(
                              spacing: CockpitSpacing.lg,
                              runSpacing: CockpitSpacing.lg,
                              children: [
                                for (final (i, d) in docs.indexed)
                                  Reveal(
                                    delay: Duration(milliseconds: 40 * i),
                                    child: _RecentCard(
                                      item: d,
                                      onTap: () => onOpenDocument?.call(d.id),
                                    ),
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
          ],
        ),
      ),
    );
  }
}

/// A light "page" — the borderless document thumbnail. A warm paper surface on
/// the charcoal ground; no outline, the fill alone reads as a sheet.
class _PaperThumb extends StatelessWidget {
  const _PaperThumb({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 8.5 / 11,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        child: ColoredBox(
          color: const Color(0xFFF6F4EF), // warm paper, both themes
          child: child,
        ),
      ),
    );
  }
}

/// Faux body lines drawn on a paper thumbnail.
class _PaperLines extends StatelessWidget {
  const _PaperLines({this.widths = const [1.0, 0.92, 0.96, 0.84, 0.98, 0.9]});
  final List<double> widths;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(CockpitSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // title line
          Container(
            height: 5,
            width: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFC9CED6),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 8),
          for (final w in widths)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: w,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E5EA),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.style,
    required this.label,
    required this.sub,
    required this.onTap,
  });

  final FormatStyle? style;
  final String label;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Pressable(
      pressedScale: 0.96,
      child: SizedBox(
        width: 150,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CockpitRadii.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PaperThumb(
                child: style == null
                    ? Center(
                        child: Icon(
                          Icons.add_rounded,
                          size: 26,
                          color: scheme.primary,
                        ),
                      )
                    : const _PaperLines(
                        widths: [1.0, 0.92, 0.96, 0.84, 0.98, 0.9, 0.94, 0.7],
                      ),
              ),
              const SizedBox(height: CockpitSpacing.sm),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                sub,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.item, required this.onTap});
  final EssayListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = (item.citationStyle ?? '').toUpperCase();
    final meta = [
      if (style.isNotEmpty) style,
      '${item.wordCount} words',
    ].join(' · ');
    return Pressable(
      pressedScale: 0.97,
      child: SizedBox(
        width: 224,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CockpitRadii.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PaperThumb(
                child: Padding(
                  padding: const EdgeInsets.all(CockpitSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 5,
                        width: 72,
                        decoration: BoxDecoration(
                          color: const Color(0xFFC9CED6),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Text(
                          item.snippet.isEmpty
                              ? 'Empty document'
                              : item.snippet,
                          maxLines: 9,
                          overflow: TextOverflow.fade,
                          style: const TextStyle(
                            fontSize: 6,
                            height: 1.7,
                            color: Color(0xFF9AA0AA),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: CockpitSpacing.sm),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                meta,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyRecent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DocSurface(
      padding: const EdgeInsets.symmetric(
        horizontal: CockpitSpacing.xl,
        vertical: CockpitSpacing.xxxl,
      ),
      child: Center(
        child: Column(
          children: [
            Text('No saved documents yet', style: theme.textTheme.titleSmall),
            const SizedBox(height: CockpitSpacing.xxs),
            Text(
              'Pick a template above — your work will appear here automatically.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
