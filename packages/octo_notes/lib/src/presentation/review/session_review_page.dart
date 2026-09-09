import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/review_controller.dart';
import '../../theme/octo_notes_theme.dart';
import '../widgets/octo_widgets.dart';

/// Width at/above which the review workspace shows the full three-column layout.
const double _kReviewDesktop = 1040;

/// Panel 13 — Session Review & Finalize (ON-P13).
///
/// A full-screen, evidence-based review workspace shown after **Finish
/// Session**: compare six layers (Original Sources · Raw Transcript · Student
/// Notes · AI Assistance · Smart Notes · Final Notes), resolve pending issues,
/// then approve and save Final Notes to The Deck — without ever mutating an
/// underlying layer. See `docs/panel-13-review-finalize.md`.
class SessionReviewPage extends StatefulWidget {
  const SessionReviewPage({super.key});

  @override
  State<SessionReviewPage> createState() => _SessionReviewPageState();
}

class _SessionReviewPageState extends State<SessionReviewPage> {
  late final ReviewController _c;

  @override
  void initState() {
    super.initState();
    _c = ReviewController(sessionId: 'sess-bio101-w4');
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _back() => context.canPop() ? context.pop() : context.go('/notes');

  @override
  Widget build(BuildContext context) {
    return OctoNotesTheme.wrap(
      context: context,
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          final desktop = MediaQuery.sizeOf(context).width >= _kReviewDesktop;
          return AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              return Scaffold(
                backgroundColor: scheme.surface,
                body: SafeArea(
                  child: Column(
                    children: [
                      _ReviewHeader(controller: _c, onBack: _back),
                      Divider(height: 1, color: scheme.outlineVariant),
                      _AudioTimeline(controller: _c),
                      Divider(height: 1, color: scheme.outlineVariant),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (desktop) ...[
                              _LayerNav(controller: _c),
                              VerticalDivider(
                                  width: 1, color: scheme.outlineVariant),
                            ],
                            Expanded(
                                child: _CompareWorkspace(controller: _c)),
                            if (desktop) ...[
                              VerticalDivider(
                                  width: 1, color: scheme.outlineVariant),
                              _RightPanel(controller: _c),
                            ],
                          ],
                        ),
                      ),
                      Divider(height: 1, color: scheme.outlineVariant),
                      _BottomBar(controller: _c, onBack: _back),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ===========================================================================
// Header (spec §6.A)
// ===========================================================================
class _ReviewHeader extends StatelessWidget {
  const _ReviewHeader({required this.controller, required this.onBack});
  final ReviewController controller;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = controller;
    final compact = MediaQuery.sizeOf(context).width < 1180;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CockpitSpacing.md,
        vertical: CockpitSpacing.sm,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: onBack,
          ),
          const SizedBox(width: CockpitSpacing.xs),
          Text('Session Review & Finalize',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const Spacer(),
          if (!compact)
            Column(
              children: [
                Text(c.sessionTitle,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                Text('${c.course} • ${c.week} • ${c.duration}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          const Spacer(),
          _StatusPill(
            icon: Icons.check_circle_rounded,
            color: CockpitColors.brand.success,
            label: 'All Devices Synced',
          ),
          const SizedBox(width: CockpitSpacing.xl),
          _StatusPill(
            icon: Icons.error_outline_rounded,
            color: c.readyToFinalize
                ? CockpitColors.brand.success
                : CockpitColors.brand.warning,
            label: c.readyToFinalize
                ? 'Ready to finalize'
                : 'Review Required • ${c.openIssues} items',
          ),
        ],
      ),
    );
  }
}

/// Status = a small coloured icon + label, grouped by proximity — not a filled
/// pill (DESIGN.md §6).
class _StatusPill extends StatelessWidget {
  const _StatusPill(
      {required this.icon, required this.color, required this.label});
  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: CockpitSpacing.xs),
        Text(label,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ===========================================================================
// Audio timeline (spec §6.D)
// ===========================================================================
class _AudioTimeline extends StatelessWidget {
  const _AudioTimeline({required this.controller});
  final ReviewController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = controller;
    final compact = MediaQuery.sizeOf(context).width < 1180;
    final progress = c.position.inSeconds / c.total.inSeconds;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.lg, vertical: CockpitSpacing.sm),
      child: Row(
        children: [
          IconButton.filledTonal(
            style: IconButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: Colors.white),
            icon: Icon(c.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
            onPressed: c.togglePlay,
          ),
          const SizedBox(width: CockpitSpacing.xs),
          IconButton(
            icon: const Icon(Icons.replay_10_rounded),
            color: scheme.onSurfaceVariant,
            onPressed: () => c.seekBy(-10),
          ),
          IconButton(
            icon: const Icon(Icons.forward_10_rounded),
            color: scheme.onSurfaceVariant,
            onPressed: () => c.seekBy(10),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          Expanded(child: _WaveformBar(progress: progress)),
          const SizedBox(width: CockpitSpacing.md),
          Text('${c.fmt(c.position)} / ${c.fmt(c.total)}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
          const SizedBox(width: CockpitSpacing.md),
          InkWell(
            borderRadius: BorderRadius.circular(CockpitRadii.pill),
            onTap: c.cycleSpeed,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: CockpitSpacing.md, vertical: CockpitSpacing.xs),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(CockpitRadii.pill),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${c.speed}x', style: theme.textTheme.labelMedium),
                Icon(Icons.expand_more_rounded,
                    size: 16, color: scheme.onSurfaceVariant),
              ]),
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: CockpitSpacing.lg),
            Icon(Icons.phone_iphone_rounded,
                size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: CockpitSpacing.xs),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Lecture Audio', style: theme.textTheme.labelMedium),
                Text(c.audioSource,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WaveformBar extends StatelessWidget {
  const _WaveformBar({required this.progress});
  final double progress;

  // A deterministic pseudo-waveform.
  static final List<double> _bars = List.generate(
      120, (i) => 0.25 + 0.75 * (0.5 + 0.5 * _pseudo(i)).abs());
  static double _pseudo(int i) =>
      ((i * 37 % 19) / 19) * 2 - 1 + ((i * 7 % 5) / 5 - 0.5);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, cts) {
      return SizedBox(
        height: 34,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < _bars.length; i++)
              Container(
                width: 2,
                height: 6 + _bars[i].clamp(0, 1) * 26,
                decoration: BoxDecoration(
                  color: (i / _bars.length) <= progress
                      ? scheme.primary
                      : scheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(CockpitRadii.pill),
                ),
              ),
          ],
        ),
      );
    });
  }
}

// ===========================================================================
// Layer navigation (spec §6.B)
// ===========================================================================
class _LayerNav extends StatelessWidget {
  const _LayerNav({required this.controller});
  final ReviewController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = controller;
    return SizedBox(
      width: 244,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(CockpitSpacing.lg,
                CockpitSpacing.lg, CockpitSpacing.lg, CockpitSpacing.sm),
            child: const Eyebrow('Review Layers'),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(
                  horizontal: CockpitSpacing.sm),
              children: [
                for (var i = 0; i < ReviewLayer.values.length; i++)
                  _LayerRow(
                    controller: c,
                    layer: ReviewLayer.values[i],
                    number: i + 1,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(CockpitSpacing.lg),
            child: Text(
              '${c.studentBlockCount} student blocks • '
              '${c.transcriptBlockCount} transcript blocks',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _LayerRow extends StatelessWidget {
  const _LayerRow(
      {required this.controller, required this.layer, required this.number});
  final ReviewController controller;
  final ReviewLayer layer;
  final int number;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = controller.statusOf(layer);
    final open = status == LayerStatus.open;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: OctoHoverRow(
        selected: open,
        padding: const EdgeInsets.symmetric(
            horizontal: CockpitSpacing.md, vertical: CockpitSpacing.md),
        onTap: () => controller.openLayerInNav(layer),
        child: Row(
          children: [
            Icon(layer.icon,
                size: 18,
                color: open ? scheme.primary : scheme.onSurfaceVariant),
            const SizedBox(width: CockpitSpacing.md),
            Expanded(
              child: Text('$number. ${layer.label}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: open ? FontWeight.w700 : FontWeight.w500,
                    color: open ? scheme.primary : scheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: CockpitSpacing.sm),
            _StatusIndicator(
                status: status, count: controller.pendingOf(layer)),
          ],
        ),
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.status, required this.count});
  final LayerStatus status;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case LayerStatus.reviewed:
        return Icon(Icons.check_circle_rounded,
            size: 18, color: CockpitColors.brand.success);
      case LayerStatus.open:
        return Icon(Icons.circle, size: 12, color: CockpitColors.brand.info);
      case LayerStatus.problem:
        return Icon(Icons.error_rounded,
            size: 18, color: scheme.primary);
      case LayerStatus.notProcessed:
        return Icon(Icons.circle_outlined,
            size: 16, color: scheme.onSurfaceVariant.withValues(alpha: 0.5));
      case LayerStatus.pending:
        return Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: CockpitColors.brand.warning.withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          child: Text('$count',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: CockpitColors.brand.warning,
                    fontWeight: FontWeight.w700,
                  )),
        );
    }
  }
}

// ===========================================================================
// Comparison workspace (spec §6.C)
// ===========================================================================
class _CompareWorkspace extends StatelessWidget {
  const _CompareWorkspace({required this.controller});
  final ReviewController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Compare controls.
        Padding(
          padding: const EdgeInsets.fromLTRB(CockpitSpacing.xl,
              CockpitSpacing.lg, CockpitSpacing.xl, CockpitSpacing.md),
          child: Row(
            children: [
              Text('Compare',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(width: CockpitSpacing.sm),
              _LayerDropdown(
                value: c.leftLayer,
                onChanged: c.setLeftLayer,
              ),
              const SizedBox(width: CockpitSpacing.md),
              Text('vs.',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(width: CockpitSpacing.md),
              _LayerDropdown(
                value: c.rightLayer,
                onChanged: c.setRightLayer,
              ),
              const Spacer(),
              Text('Show Changes',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(width: CockpitSpacing.sm),
              Switch(
                value: c.showChanges,
                onChanged: (_) => c.toggleShowChanges(),
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _LayerColumn(
                  controller: c,
                  layer: c.leftLayer,
                  isRightColumn: false,
                ),
              ),
              VerticalDivider(width: 1, color: scheme.outlineVariant),
              Expanded(
                child: _LayerColumn(
                  controller: c,
                  layer: c.rightLayer,
                  isRightColumn: true,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LayerDropdown extends StatelessWidget {
  const _LayerDropdown({required this.value, required this.onChanged});
  final ReviewLayer value;
  final ValueChanged<ReviewLayer> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ReviewLayer>(
          value: value,
          isDense: true,
          borderRadius: BorderRadius.circular(CockpitRadii.md),
          icon: Icon(Icons.expand_more_rounded,
              size: 18, color: scheme.onSurfaceVariant),
          style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurface),
          items: [
            for (final l in ReviewLayer.values)
              DropdownMenuItem(value: l, child: Text(l.label)),
          ],
          onChanged: (l) => l == null ? null : onChanged(l),
        ),
      ),
    );
  }
}

/// One side of the comparison — a titled, scrollable list of layer blocks.
class _LayerColumn extends StatelessWidget {
  const _LayerColumn({
    required this.controller,
    required this.layer,
    required this.isRightColumn,
  });
  final ReviewController controller;
  final ReviewLayer layer;
  final bool isRightColumn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final blocks = controller.blocksFor(layer);
    final (title, subtitle) = _header(layer);
    final smart =
        isRightColumn && (layer == ReviewLayer.smartNotes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(CockpitSpacing.xl,
              CockpitSpacing.md, CockpitSpacing.xl, CockpitSpacing.md),
          child: Row(
            children: [
              Icon(layer.icon,
                  size: 18,
                  color: isRightColumn ? scheme.primary : scheme.onSurface),
              const SizedBox(width: CockpitSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color:
                            isRightColumn ? scheme.primary : scheme.onSurface,
                      )),
                  Text(subtitle,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: blocks.isEmpty
              ? _EmptyLayer(layer: layer)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(CockpitSpacing.xl, 0,
                      CockpitSpacing.xl, CockpitSpacing.lg),
                  children: [
                    for (final b in blocks)
                      _BlockView(controller: controller, block: b),
                  ],
                ),
        ),
        if (smart) _SmartActionBar(controller: controller),
      ],
    );
  }

  (String, String) _header(ReviewLayer l) {
    switch (l) {
      case ReviewLayer.originalSources:
        return ('Original Sources', 'Authentic session materials • Read-only');
      case ReviewLayer.rawTranscript:
        return ('Raw Transcript', 'Faithful chronological transcript');
      case ReviewLayer.studentNotes:
        return ('Student Notes', 'Original student-created content');
      case ReviewLayer.aiAssistance:
        return ('AI Assistance', 'Suggestions awaiting your decision');
      case ReviewLayer.smartNotes:
        return ('Smart Notes', 'AI-organized preview • Not final');
      case ReviewLayer.finalNotes:
        return ('Final Notes', 'Your approved document');
    }
  }
}

class _EmptyLayer extends StatelessWidget {
  const _EmptyLayer({required this.layer});
  final ReviewLayer layer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(CockpitSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.task_alt_outlined,
                size: 32, color: scheme.onSurfaceVariant),
            const SizedBox(height: CockpitSpacing.md),
            Text('Final Notes not created yet',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: CockpitSpacing.xs),
            Text('Approve Smart Notes to build the final document.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// Renders a single block per its kind, with provenance + change chips.
class _BlockView extends StatelessWidget {
  const _BlockView({required this.controller, required this.block});
  final ReviewController controller;
  final ReviewBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final b = block;
    final selected = controller.selectedBlockId == b.id;
    final related = controller.isRelated(b);
    final showChanges = controller.showChanges;

    // Headings render as plain type — grouping via space, not boxes.
    if (b.kind == ReviewBlockKind.h1) {
      return Padding(
        padding: const EdgeInsets.only(top: CockpitSpacing.sm, bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(b.text,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Container(width: 54, height: 3, color: scheme.primary),
          ],
        ),
      );
    }

    if (b.kind == ReviewBlockKind.section) {
      // "Added" reads through colour + a small marker, not a filled box.
      final added = showChanges && b.change == ChangeKind.added;
      final color =
          added ? CockpitColors.brand.success : scheme.onSurface;
      return Padding(
        padding: const EdgeInsets.only(top: CockpitSpacing.lg, bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (added) ...[
              Icon(Icons.circle, size: 8, color: CockpitColors.brand.success),
              const SizedBox(width: CockpitSpacing.sm),
            ],
            Expanded(
              child: Text(b.text,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700, color: color)),
            ),
          ],
        ),
      );
    }

    if (b.kind == ReviewBlockKind.heading) {
      return Padding(
        padding: const EdgeInsets.only(top: CockpitSpacing.md, bottom: 2),
        child: Text(b.text,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
      );
    }

    // A cited/AI/transcript/question card → sanctioned subtle surface.
    final isCard = b.kind == ReviewBlockKind.question ||
        b.kind == ReviewBlockKind.note ||
        b.diagram;

    final chips = _chips(context);

    Widget body;
    if (b.kind == ReviewBlockKind.bullet) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 9, right: CockpitSpacing.md),
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                    color: scheme.onSurfaceVariant, shape: BoxShape.circle),
              ),
            ),
            Expanded(
                child: Text(b.text, style: theme.textTheme.bodyLarge)),
            if (chips.isNotEmpty) ...[
              const SizedBox(width: CockpitSpacing.sm),
              Wrap(spacing: CockpitSpacing.xs, children: chips),
            ],
          ],
        ),
      );
    } else if (isCard) {
      body = _CardBlock(
        controller: controller,
        block: b,
        chips: chips,
        selected: selected || related,
      );
    } else {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(b.text, style: theme.textTheme.bodyLarge),
      );
    }

    // Selection/relation reads as a faint hover-style tint, not an outline.
    final tint = selected
        ? scheme.primary.withValues(alpha: 0.06)
        : related
            ? CockpitColors.brand.info.withValues(alpha: 0.06)
            : Colors.transparent;
    return Material(
      color: tint,
      borderRadius: BorderRadius.circular(CockpitRadii.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(CockpitRadii.sm),
        onTap: () {
          controller.selectBlock(b.id);
          controller.jumpToBlockAudio(b);
        },
        child: body,
      ),
    );
  }

  List<Widget> _chips(BuildContext context) {
    final b = block;
    final showChanges = controller.showChanges;
    final out = <Widget>[];
    // Provenance chip.
    if (b.origin == BlockOrigin.aiOrganized) {
      out.add(const _Chip('AI Organized',
          kind: _ChipKind.ai, icon: Icons.auto_awesome_rounded));
    } else if (b.origin == BlockOrigin.slide) {
      out.add(_Chip(b.provenanceDetail ?? 'Slide',
          kind: _ChipKind.neutral, icon: Icons.slideshow_outlined));
    } else if (b.kind == ReviewBlockKind.question) {
      out.add(const _Chip('Student Typed',
          kind: _ChipKind.neutral, icon: Icons.edit_outlined));
      if (b.audioTimestamp != null) {
        out.add(_Chip(b.audioTimestamp!,
            kind: _ChipKind.neutral, icon: Icons.schedule_rounded));
      }
    } else if (b.origin == BlockOrigin.transcript) {
      out.add(_Chip('Transcript • ${b.provenanceDetail ?? ''}',
          kind: _ChipKind.neutral, icon: Icons.record_voice_over_outlined));
    } else if (b.origin == BlockOrigin.magicPencil) {
      out.add(const _Chip('Magic Pencil • Original Ink',
          kind: _ChipKind.neutral, icon: Icons.gesture_rounded));
    } else if (b.origin == BlockOrigin.externalResearch) {
      out.add(_Chip(b.provenanceDetail ?? 'External',
          kind: _ChipKind.ai, icon: Icons.public_outlined));
    }
    // Change chip.
    if (showChanges && b.change != null) {
      switch (b.change!) {
        case ChangeKind.moved:
          out.add(const _Chip('Moved',
              kind: _ChipKind.moved, icon: Icons.arrow_forward_rounded));
        case ChangeKind.added:
          out.add(const _Chip('Added',
              kind: _ChipKind.added, icon: Icons.arrow_forward_rounded));
        case ChangeKind.excluded:
          out.add(const _Chip('Excluded',
              kind: _ChipKind.excluded, icon: Icons.close_rounded));
        case ChangeKind.edited:
          out.add(const _Chip('Edited', kind: _ChipKind.edited));
        case ChangeKind.aiGenerated:
          out.add(const _Chip('Added',
              kind: _ChipKind.added, icon: Icons.arrow_forward_rounded));
      }
    }
    return out;
  }
}

/// A question / transcript quote / ink / AI note. Borderless: an icon + a
/// coloured [Eyebrow]-style label carry the type; grouping is whitespace, not a
/// filled card (DESIGN.md). Only the ink diagram keeps an earned subtle surface.
class _CardBlock extends StatelessWidget {
  const _CardBlock({
    required this.controller,
    required this.block,
    required this.chips,
    required this.selected,
  });
  final ReviewController controller;
  final ReviewBlock block;
  final List<Widget> chips;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final b = block;
    final showChanges = controller.showChanges;

    // Colour + label by role.
    late final Color tint;
    late final IconData icon;
    late final String label;
    if (b.kind == ReviewBlockKind.question) {
      tint = CockpitColors.brand.info;
      icon = Icons.help_outline_rounded;
      label = 'Student Question';
    } else if (b.change == ChangeKind.aiGenerated && showChanges) {
      tint = scheme.tertiary; // AI-expanded → highlight gold
      icon = Icons.lightbulb_outline_rounded;
      label = 'AI Suggestion';
    } else if (b.origin == BlockOrigin.aiExplanation ||
        b.origin == BlockOrigin.aiOrganized ||
        b.origin == BlockOrigin.externalResearch) {
      tint = scheme.primary;
      icon = Icons.auto_awesome_rounded;
      label = 'AI';
    } else if (b.origin == BlockOrigin.magicPencil) {
      tint = scheme.onSurfaceVariant;
      icon = Icons.gesture_rounded;
      label = 'Magic Pencil';
    } else {
      tint = scheme.onSurfaceVariant;
      icon = Icons.format_quote_rounded;
      label = 'Transcript';
    }

    final excluded = !b.includedInFinal;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: CockpitSpacing.md),
            child: Icon(icon, size: 16, color: tint),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tint,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    )),
                const SizedBox(height: CockpitSpacing.xs),
                b.diagram
                    ? _InkDiagram(text: b.text)
                    : Text(b.text,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          decoration:
                              excluded ? TextDecoration.lineThrough : null,
                          color: excluded ? scheme.onSurfaceVariant : null,
                        )),
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: CockpitSpacing.sm),
                  Wrap(
                    spacing: CockpitSpacing.xs,
                    runSpacing: CockpitSpacing.xs,
                    children: chips,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InkDiagram extends StatelessWidget {
  const _InkDiagram({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
              horizontal: CockpitSpacing.md, vertical: CockpitSpacing.lg),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(CockpitRadii.sm),
          ),
          child: Center(
            child: Text(text,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                )),
          ),
        ),
      ],
    );
  }
}

enum _ChipKind { neutral, ai, moved, added, excluded, edited }

class _Chip extends StatelessWidget {
  const _Chip(this.label, {required this.kind, this.icon});
  final String label;
  final _ChipKind kind;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    late final Color color;
    switch (kind) {
      case _ChipKind.neutral:
        color = scheme.onSurfaceVariant;
      case _ChipKind.ai:
        color = const Color(0xFF8B5CF6); // purple = AI-generated (§8)
      case _ChipKind.moved:
        color = CockpitColors.brand.info; // blue = moved
      case _ChipKind.added:
        color = CockpitColors.brand.success; // green = added
      case _ChipKind.excluded:
        color = scheme.primary; // red = excluded
      case _ChipKind.edited:
        color = CockpitColors.brand.warning; // yellow = edited
    }
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Block-level review actions for the Smart Notes column (spec §7).
class _SmartActionBar extends StatelessWidget {
  const _SmartActionBar({required this.controller});
  final ReviewController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = controller;
    // Act on the selected block, else the first pending AI block.
    final blocks = c.blocksFor(ReviewLayer.smartNotes);
    final target = c.selectedBlockId ??
        blocks
            .firstWhere(
              (b) => b.aiDecision == AiDecision.pending,
              orElse: () => blocks.last,
            )
            .id;

    Widget action(IconData icon, String label, Color color, VoidCallback tap) =>
        TextButton.icon(
          onPressed: tap,
          style: TextButton.styleFrom(foregroundColor: color),
          icon: Icon(icon, size: 16),
          label: Text(label),
        );

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.lg, vertical: CockpitSpacing.xs),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          action(Icons.open_in_new_rounded, 'Open Source',
              scheme.onSurfaceVariant, () {
            _snack(context, 'Opening original source…');
          }),
          action(Icons.check_rounded, 'Accept', CockpitColors.brand.success,
              () {
            c.acceptBlock(target);
            _snack(context, 'Accepted into Final Notes');
          }),
          action(Icons.close_rounded, 'Exclude', scheme.primary, () {
            c.excludeBlock(target);
            _snack(context, 'Excluded from Final Notes');
          }),
        ],
      ),
    );
  }
}

// ===========================================================================
// Right panel: checklist + save destination + originals preserved (spec §6.E)
// ===========================================================================
class _RightPanel extends StatelessWidget {
  const _RightPanel({required this.controller});
  final ReviewController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = controller;
    return SizedBox(
      width: 320,
      child: ListView(
        padding: const EdgeInsets.all(CockpitSpacing.xl),
        children: [
          Text('Review Checklist',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: CockpitSpacing.xs),
          Text('${c.checklistDone} of ${c.checklistTotal} complete',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: CockpitSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(CockpitRadii.pill),
            child: LinearProgressIndicator(
              value: c.checklistDone / c.checklistTotal,
              minHeight: 4,
              backgroundColor: scheme.surfaceContainerHigh,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: CockpitSpacing.lg),
          for (final item in c.checklist)
            _ChecklistRow(controller: c, item: item),
          const SizedBox(height: CockpitSpacing.xxl),
          _SaveDestination(controller: c),
          const SizedBox(height: CockpitSpacing.xl),
          _OriginalsPreserved(),
        ],
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.controller, required this.item});
  final ReviewController controller;
  final ChecklistItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    late final IconData icon;
    late final Color color;
    switch (item.state) {
      case ChecklistState.done:
        icon = Icons.check_circle_rounded;
        color = CockpitColors.brand.success;
      case ChecklistState.warning:
        icon = Icons.error_outline_rounded;
        color = CockpitColors.brand.warning;
      case ChecklistState.info:
        icon = Icons.info_outline_rounded;
        color = CockpitColors.brand.info;
    }
    return OctoHoverRow(
      padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.sm, vertical: CockpitSpacing.sm),
      onTap: item.jumpToLayer == null
          ? null
          : () => controller.openLayerInNav(item.jumpToLayer!),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: CockpitSpacing.md),
          Expanded(
            child: Text(item.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: item.state == ChecklistState.done
                      ? scheme.onSurface
                      : color,
                )),
          ),
          if (item.jumpToLayer != null)
            Icon(Icons.chevron_right_rounded,
                size: 18, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _SaveDestination extends StatelessWidget {
  const _SaveDestination({required this.controller});
  final ReviewController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.folder_outlined, size: 20, color: scheme.onSurfaceVariant),
        const SizedBox(width: CockpitSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Save to The Deck',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(controller.deckPathLabel,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: CockpitSpacing.xs),
              InkWell(
                onTap: () => _snack(context, 'Choose a Deck location…'),
                child: Text('Change',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: scheme.primary)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OriginalsPreserved extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final green = CockpitColors.brand.success;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.verified_outlined, size: 20, color: green),
        const SizedBox(width: CockpitSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Originals Preserved',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700, color: green)),
              const SizedBox(height: 2),
              Text('Audio, transcript, notes and ink remain accessible.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Bottom action bar (spec §11)
// ===========================================================================
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.controller, required this.onBack});
  final ReviewController controller;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = controller;
    final compact = MediaQuery.sizeOf(context).width < 1180;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.lg, vertical: CockpitSpacing.md),
      child: Row(
        children: [
          if (!compact) ...[
            Icon(
              c.draftSaved
                  ? Icons.check_circle_rounded
                  : Icons.cloud_done_outlined,
              size: 16,
              color: CockpitColors.brand.success,
            ),
            const SizedBox(width: CockpitSpacing.xs),
            Text(c.draftSaved ? 'Review draft saved' : 'Autosaving review',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
          const Spacer(),
          TextButton(
            onPressed: onBack,
            style: TextButton.styleFrom(foregroundColor: scheme.onSurface),
            child: const Text('Back to Session'),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          OutlinedButton.icon(
            onPressed: () {
              c.saveDraft();
              _snack(context, 'Review draft saved');
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.onSurface,
              side: BorderSide(color: scheme.outlineVariant),
            ),
            icon: const Icon(Icons.save_outlined, size: 16),
            label: const Text('Save Review Draft'),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => _showFinalPreview(context, c),
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.onSurface,
              side: BorderSide(color: scheme.outlineVariant),
            ),
            icon: const Icon(Icons.description_outlined, size: 16),
            label: const Text('Preview Final Notes'),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          FilledButton.icon(
            onPressed: () => _showFinalizeDialog(context, c),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Finalize & Save'),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Dialogs
// ===========================================================================
void _showFinalPreview(BuildContext context, ReviewController c) {
  showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final blocks = c.blocksFor(ReviewLayer.smartNotes)
          .where((b) => b.includedInFinal)
          .toList();
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
          child: Padding(
            padding: const EdgeInsets.all(CockpitSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.description_outlined, color: scheme.primary),
                    const SizedBox(width: CockpitSpacing.sm),
                    Text('Final Notes preview',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                Text('Clean reading view — no change colouring.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: CockpitSpacing.lg),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final b in blocks)
                          Padding(
                            padding: const EdgeInsets.only(
                                bottom: CockpitSpacing.sm),
                            child: _PreviewLine(block: b),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _PreviewLine extends StatelessWidget {
  const _PreviewLine({required this.block});
  final ReviewBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = block;
    switch (b.kind) {
      case ReviewBlockKind.h1:
        return Text(b.text,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700));
      case ReviewBlockKind.section:
      case ReviewBlockKind.heading:
        return Padding(
          padding: const EdgeInsets.only(top: CockpitSpacing.sm),
          child: Text(b.text,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
        );
      case ReviewBlockKind.bullet:
        return Text('•  ${b.text}', style: theme.textTheme.bodyLarge);
      default:
        return Text(b.text, style: theme.textTheme.bodyLarge);
    }
  }
}

void _showFinalizeDialog(BuildContext pageContext, ReviewController c) {
  showDialog<void>(
    context: pageContext,
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      Widget line(IconData i, String text) => Padding(
            padding: const EdgeInsets.only(bottom: CockpitSpacing.sm),
            child: Row(
              children: [
                Icon(i, size: 16, color: CockpitColors.brand.success),
                const SizedBox(width: CockpitSpacing.sm),
                Expanded(
                    child: Text(text, style: theme.textTheme.bodyMedium)),
              ],
            ),
          );
      return AlertDialog(
        title: Row(
          children: [
            Icon(Icons.verified_rounded, color: CockpitColors.brand.success),
            const SizedBox(width: CockpitSpacing.sm),
            const Text('Ready to finalize'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!c.readyToFinalize)
              Padding(
                padding: const EdgeInsets.only(bottom: CockpitSpacing.md),
                child: Text(
                  '${c.openIssues} items still need review, but you can '
                  'finalize what is approved.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: CockpitColors.brand.warning),
                ),
              ),
            line(Icons.graphic_eq_rounded, '${c.duration} audio preserved'),
            line(Icons.record_voice_over_outlined,
                '${c.transcriptBlockCount} transcript blocks preserved'),
            line(Icons.edit_outlined,
                '${c.studentBlockCount} student-created blocks preserved'),
            line(Icons.auto_awesome_rounded,
                '${c.aiApproved} AI additions approved'),
            line(Icons.block_rounded, '${c.aiRejected} AI suggestions rejected'),
            line(Icons.link_rounded, '${c.sourcesLinked} source materials linked'),
            const SizedBox(height: CockpitSpacing.sm),
            Text('Final Notes will be saved to ${c.deckPathLabel}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Continue Reviewing'),
          ),
          FilledButton(
            onPressed: () {
              c.finalize();
              Navigator.of(context).pop();
              // Panel 13 → Panel 14: open the finalized Final Notes view with
              // Study Studio recommendations.
              pageContext.go('/notes/final');
            },
            child: const Text('Finalize Session'),
          ),
        ],
      );
    },
  );
}

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
  );
}
