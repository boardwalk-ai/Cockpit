import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/octo_notes_theme.dart';
import '../widgets/octo_widgets.dart';

/// Width at/above which the finalize screen shows Summary + Smart Organization
/// side by side.
const double _kFinalizeDesktop = 900;

/// A topic gist for the divided Summary (spec: "Summary Gist Divided", by topic).
class _TopicGist {
  const _TopicGist(this.title, this.points);
  final String title;
  final List<String> points;
}

/// Panel 3 (redesign) — **Finalize / Export screen**.
///
/// Reached from the Live Session Hub's Finalize button (replaces the heavier
/// Panel 13 review in the redesign). Shows the session **Summary** (an AI gist
/// divided by topic), the **Smart Organization** structure, and a **Download**
/// action to export the final notes as PDF. Borderless (`DESIGN.md`).
class SessionFinalizePage extends StatefulWidget {
  const SessionFinalizePage({super.key});

  @override
  State<SessionFinalizePage> createState() => _SessionFinalizePageState();
}

class _SessionFinalizePageState extends State<SessionFinalizePage> {
  static const _topics = <_TopicGist>[
    _TopicGist('Glycolysis', [
      'Occurs in the cytoplasm',
      'Glucose is split into two pyruvate',
      'Net gain: 2 ATP and 2 NADH',
    ]),
    _TopicGist('Electron Transport Chain', [
      'On the inner mitochondrial membrane',
      'Builds a proton gradient',
      'Gradient drives ATP synthase',
    ]),
    _TopicGist('Role of Oxygen', [
      'Final electron acceptor',
      'Enables the gradient indirectly',
    ]),
  ];

  late final Set<int> _included = {for (var i = 0; i < _topics.length; i++) i};

  void _toggle(int i) => setState(() {
        _included.contains(i) ? _included.remove(i) : _included.add(i);
      });

  void _back() =>
      context.canPop() ? context.pop() : context.go('/notes/session');

  void _download() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
            'Exporting ${_included.length} topics as PDF — Cellular Respiration.pdf'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OctoNotesTheme.wrap(
      context: context,
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          final desktop = MediaQuery.sizeOf(context).width >= _kFinalizeDesktop;
          return Scaffold(
            backgroundColor: scheme.surface,
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Padding(
                    padding: const EdgeInsets.all(CockpitSpacing.xxl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(onBack: _back),
                        const SizedBox(height: CockpitSpacing.xl),
                        Expanded(
                          child: desktop
                              ? Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                        flex: 5, child: _summary(context)),
                                    const SizedBox(width: CockpitSpacing.xl),
                                    SizedBox(
                                        width: 320,
                                        child: _SmartOrganization()),
                                  ],
                                )
                              : ListView(
                                  children: [
                                    _summary(context),
                                    const SizedBox(height: CockpitSpacing.xl),
                                    _SmartOrganization(),
                                  ],
                                ),
                        ),
                        const SizedBox(height: CockpitSpacing.xl),
                        Center(
                          child: FilledButton.icon(
                            onPressed:
                                _included.isEmpty ? null : _download,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: CockpitSpacing.xxl,
                                  vertical: CockpitSpacing.md),
                            ),
                            icon: const Icon(Icons.download_rounded, size: 18),
                            label: const Text('Download PDF'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Summary — one panel, divided into topic columns (spec "Gist Divided").
  Widget _summary(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Eyebrow('Summary'),
            const SizedBox(width: CockpitSpacing.md),
            Text('Gist divided by topic',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: CockpitSpacing.md),
        Expanded(
          child: OctoSurface(
            padding: const EdgeInsets.all(CockpitSpacing.lg),
            child: LayoutBuilder(builder: (context, cts) {
              final columns = cts.maxWidth >= 640;
              final tiles = [
                for (var i = 0; i < _topics.length; i++)
                  _GistColumn(
                    topic: _topics[i],
                    included: _included.contains(i),
                    onToggle: () => _toggle(i),
                  ),
              ];
              if (!columns) {
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < tiles.length; i++) ...[
                        tiles[i],
                        if (i != tiles.length - 1)
                          Divider(
                              height: CockpitSpacing.xl,
                              color: scheme.outlineVariant),
                      ],
                    ],
                  ),
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < tiles.length; i++) ...[
                    Expanded(child: tiles[i]),
                    if (i != tiles.length - 1)
                      VerticalDivider(
                          width: CockpitSpacing.xl,
                          color: scheme.outlineVariant),
                  ],
                ],
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        IconButton(
            icon: const Icon(Icons.arrow_back_rounded), onPressed: onBack),
        const SizedBox(width: CockpitSpacing.sm),
        Text('Finalize',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(width: CockpitSpacing.md),
        Text('Cellular Respiration Lecture • Biology 101 • Week 4',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant)),
        const Spacer(),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_outlined,
                size: 15, color: CockpitColors.brand.success),
            const SizedBox(width: CockpitSpacing.xs),
            Text('Originals preserved',
                style: theme.textTheme.labelMedium?.copyWith(
                    color: CockpitColors.brand.success,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }
}

class _GistColumn extends StatelessWidget {
  const _GistColumn(
      {required this.topic, required this.included, required this.onToggle});
  final _TopicGist topic;
  final bool included;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Opacity(
      opacity: included ? 1 : 0.45,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(topic.title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              InkWell(
                onTap: onToggle,
                borderRadius: BorderRadius.circular(CockpitRadii.pill),
                child: Icon(
                  included
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 18,
                  color: included
                      ? CockpitColors.brand.success
                      : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.md),
          for (final p in topic.points)
            Padding(
              padding: const EdgeInsets.only(bottom: CockpitSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.only(top: 8, right: CockpitSpacing.sm),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                          color: scheme.onSurfaceVariant,
                          shape: BoxShape.circle),
                    ),
                  ),
                  Expanded(
                      child: Text(p, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SmartOrganization extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget node(String text, {int depth = 0, bool bold = false}) => Padding(
          padding: EdgeInsets.only(
              left: depth * 16.0, bottom: CockpitSpacing.sm),
          child: Row(
            children: [
              Icon(
                  depth == 0
                      ? Icons.folder_outlined
                      : Icons.subdirectory_arrow_right_rounded,
                  size: 15,
                  color: scheme.onSurfaceVariant),
              const SizedBox(width: CockpitSpacing.sm),
              Flexible(
                child: Text(text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight:
                            bold ? FontWeight.w700 : FontWeight.w500)),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Eyebrow('Smart Organization'),
        const SizedBox(height: CockpitSpacing.md),
        Expanded(
          child: OctoSurface(
            padding: const EdgeInsets.all(CockpitSpacing.lg),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  node('Cellular Respiration', bold: true),
                  node('Glycolysis', depth: 1),
                  node('Electron Transport Chain', depth: 1),
                  node('Role of Oxygen', depth: 2),
                  const SizedBox(height: CockpitSpacing.lg),
                  const Eyebrow('Categories'),
                  const SizedBox(height: CockpitSpacing.md),
                  Wrap(
                    spacing: CockpitSpacing.sm,
                    runSpacing: CockpitSpacing.sm,
                    children: const [
                      OctoChip('Definitions'),
                      OctoChip('Formulas'),
                      OctoChip('Questions'),
                      OctoChip('Exam Hints'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
