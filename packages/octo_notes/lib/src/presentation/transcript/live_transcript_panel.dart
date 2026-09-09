import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';

import '../../domain/notes_controller.dart';
import '../../domain/transcript_controller.dart';
import '../../domain/transcript_models.dart';

/// Panel 7 — the expanded Live Transcript. Three preserved layers (raw /
/// faithful / corrected), Follow Live, an audio player, per-segment markers /
/// slide links / corrections, and transcript-selection actions.
class LiveTranscriptPanel extends StatefulWidget {
  const LiveTranscriptPanel({
    super.key,
    required this.controller,
    required this.notes,
    required this.full,
    required this.onCollapse,
    required this.onToggleFull,
    required this.onSwitchToTypewriter,
  });

  final TranscriptController controller;
  final NotesController notes;
  final bool full;
  final VoidCallback onCollapse;
  final VoidCallback onToggleFull;
  final VoidCallback onSwitchToTypewriter;

  @override
  State<LiveTranscriptPanel> createState() => _LiveTranscriptPanelState();
}

class _LiveTranscriptPanelState extends State<LiveTranscriptPanel> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final atBottom =
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 24;
    if (!atBottom && widget.controller.followLive) {
      widget.controller.pauseFollowFromScroll();
    }
  }

  void _jumpToLive() {
    widget.controller.jumpToLive();
    if (_scroll.hasClients) {
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = widget.controller;
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        return Container(
          color: scheme.surfaceContainerLowest,
          child: Column(
            children: [
              _Header(
                controller: c,
                full: widget.full,
                onCollapse: widget.onCollapse,
                onToggleFull: widget.onToggleFull,
              ),
              Divider(height: 1, color: scheme.outlineVariant),
              _PlayerBar(controller: c),
              Divider(height: 1, color: scheme.outlineVariant),
              Expanded(
                child: Stack(
                  children: [
                    _SegmentList(
                      controller: c,
                      notes: widget.notes,
                      scroll: _scroll,
                      onSwitchToTypewriter: widget.onSwitchToTypewriter,
                    ),
                    if (!c.followLive)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: CockpitSpacing.md,
                        child: Center(child: _JumpToLive(onTap: _jumpToLive)),
                      ),
                  ],
                ),
              ),
              Divider(height: 1, color: scheme.outlineVariant),
              const _BottomStatus(),
            ],
          ),
        );
      },
    );
  }
}

// ===========================================================================
// Header + controls
// ===========================================================================
class _Header extends StatelessWidget {
  const _Header({
    required this.controller,
    required this.full,
    required this.onCollapse,
    required this.onToggleFull,
  });
  final TranscriptController controller;
  final bool full;
  final VoidCallback onCollapse;
  final VoidCallback onToggleFull;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(CockpitSpacing.lg, CockpitSpacing.md,
          CockpitSpacing.lg, CockpitSpacing.sm),
      child: Column(
        children: [
          Row(
            children: [
              Text('Live Transcript', style: theme.textTheme.titleMedium),
              const SizedBox(width: CockpitSpacing.md),
              Icon(Icons.circle, size: 8, color: scheme.primary),
              const SizedBox(width: CockpitSpacing.xs),
              Text('Live · ${controller.delaySeconds} seconds behind',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const Spacer(),
              Icon(Icons.verified_user_rounded,
                  size: 16, color: CockpitColors.brand.success),
              const SizedBox(width: CockpitSpacing.xs),
              Text('Raw Transcript Preserved',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: CockpitSpacing.md),
          Row(
            children: [
              Expanded(child: _SearchField(controller: controller)),
              const SizedBox(width: CockpitSpacing.md),
              _FollowLiveToggle(controller: controller),
              const SizedBox(width: CockpitSpacing.md),
              _FilterButton(controller: controller),
              const SizedBox(width: CockpitSpacing.sm),
              IconButton(
                tooltip: full ? 'Exit full transcript' : 'Collapse',
                icon: Icon(full
                    ? Icons.close_fullscreen_rounded
                    : Icons.keyboard_arrow_down_rounded),
                onPressed: full ? onToggleFull : onCollapse,
              ),
              OutlinedButton.icon(
                onPressed: onToggleFull,
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(color: scheme.outlineVariant)),
                icon: const Icon(Icons.open_in_full_rounded, size: 16),
                label: Text(full ? 'Docked View' : 'Open Full Transcript'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});
  final TranscriptController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: controller.setQuery,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search transcript',
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        contentPadding: const EdgeInsets.symmetric(vertical: CockpitSpacing.sm),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CockpitRadii.sm),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _FollowLiveToggle extends StatelessWidget {
  const _FollowLiveToggle({required this.controller});
  final TranscriptController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(
          value: controller.followLive,
          onChanged: controller.setFollowLive,
          activeThumbColor: Colors.white,
          activeTrackColor: scheme.primary,
        ),
        const SizedBox(width: CockpitSpacing.xs),
        Text('Follow Live', style: theme.textTheme.labelMedium),
      ],
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.controller});
  final TranscriptController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PopupMenuButton<TranscriptFilter>(
      tooltip: 'Filter',
      onSelected: controller.setFilter,
      itemBuilder: (context) => [
        for (final f in TranscriptFilter.values)
          CheckedPopupMenuItem(
            value: f,
            checked: controller.filter == f,
            child: Text(f.label),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: CockpitSpacing.md, vertical: CockpitSpacing.sm),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(CockpitRadii.sm),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_list_rounded,
                size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: CockpitSpacing.xs),
            Text(
                controller.filter == TranscriptFilter.all
                    ? 'Filter'
                    : controller.filter.label,
                style: theme.textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Audio player
// ===========================================================================
class _PlayerBar extends StatelessWidget {
  const _PlayerBar({required this.controller});
  final TranscriptController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = controller.playback;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.lg, vertical: CockpitSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: p.toggle,
                icon: Icon(p.playing
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded),
              ),
              _RoundIcon(
                  icon: Icons.replay_10_rounded,
                  onTap: () => p.nudge(-10)),
              _RoundIcon(
                  icon: Icons.forward_10_rounded, onTap: () => p.nudge(10)),
              const SizedBox(width: CockpitSpacing.md),
              Expanded(child: _Waveform(progress: p.progress, seek: (f) {
                p.seekTo((f * TranscriptPlaybackTotals.total).round());
              })),
              const SizedBox(width: CockpitSpacing.md),
              Text('${p.positionLabel} / ${p.totalLabel}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
              const SizedBox(width: CockpitSpacing.md),
              InkWell(
                borderRadius: BorderRadius.circular(CockpitRadii.sm),
                onTap: p.cycleSpeed,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: CockpitSpacing.sm, vertical: CockpitSpacing.xs),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(CockpitRadii.sm),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Text('${_speedLabel(p.speed)}×',
                      style: theme.textTheme.labelMedium),
                ),
              ),
              const SizedBox(width: CockpitSpacing.sm),
              Icon(Icons.volume_up_rounded,
                  size: 20, color: scheme.onSurfaceVariant),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: CockpitSpacing.xs, left: 4),
            child: Text(
                p.uploadPending
                    ? 'Audio saved on ${controller.segments.first.deviceId} · Upload pending'
                    : 'Audio from ${controller.segments.first.deviceId}',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  static String _speedLabel(double s) =>
      s == s.roundToDouble() ? s.toInt().toString() : s.toString();
}

/// Exposes the playback total for the waveform seek math.
abstract final class TranscriptPlaybackTotals {
  static int get total => 42 * 60 + 16;
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
      onPressed: onTap,
    );
  }
}

class _Waveform extends StatelessWidget {
  const _Waveform({required this.progress, required this.seek});
  final double progress;
  final ValueChanged<double> seek;

  static const int _bars = 60;

  double _amp(int i) {
    final v = (0.5 + 0.5 * (i * 1.7 % 3 - 1).abs()) *
        (0.4 + 0.6 * ((i * 7) % 5) / 5);
    return 0.2 + 0.8 * v.clamp(0, 1);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, constraints) {
      return GestureDetector(
        onTapDown: (d) => seek((d.localPosition.dx / constraints.maxWidth)
            .clamp(0.0, 1.0)),
        child: SizedBox(
          height: 34,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < _bars; i++)
                Expanded(
                  child: Center(
                    child: Container(
                      width: 2,
                      height: _amp(i) * 30,
                      decoration: BoxDecoration(
                        color: (i / _bars) <= progress
                            ? scheme.primary
                            : scheme.outline,
                        borderRadius: BorderRadius.circular(CockpitRadii.pill),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}

// ===========================================================================
// Segment list
// ===========================================================================
class _SegmentList extends StatelessWidget {
  const _SegmentList({
    required this.controller,
    required this.notes,
    required this.scroll,
    required this.onSwitchToTypewriter,
  });
  final TranscriptController controller;
  final NotesController notes;
  final ScrollController scroll;
  final VoidCallback onSwitchToTypewriter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final segs = controller.visibleSegments;

    if (segs.isEmpty && controller.isSearching) {
      return const EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No matching segments',
        message: 'Try a different phrase, speaker, or filter.',
      );
    }

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.sm),
      children: [
        for (final s in segs) ...[
          _SegmentTile(
            controller: controller,
            notes: notes,
            segment: s,
            onSwitchToTypewriter: onSwitchToTypewriter,
          ),
          Divider(height: 1, color: scheme.outlineVariant),
        ],
        if (!controller.isSearching && controller.partial != null)
          _PartialTile(segment: controller.partial!),
      ],
    );
  }
}

class _SegmentTile extends StatelessWidget {
  const _SegmentTile({
    required this.controller,
    required this.notes,
    required this.segment,
    required this.onSwitchToTypewriter,
  });
  final TranscriptController controller;
  final NotesController notes;
  final TranscriptSegment segment;
  final VoidCallback onSwitchToTypewriter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = segment;
    final selected = controller.selectedId == s.id;

    return InkWell(
      onTap: () => controller.select(selected ? null : s.id),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withValues(alpha: 0.05) : null,
          border: selected
              ? Border(left: BorderSide(color: scheme.primary, width: 3))
              : null,
        ),
        padding: EdgeInsets.fromLTRB(selected ? CockpitSpacing.md : CockpitSpacing.lg,
            CockpitSpacing.md, CockpitSpacing.lg, CockpitSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 44,
                  child: Text(s.start,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: selected ? scheme.primary : scheme.onSurfaceVariant,
                        fontWeight: selected ? FontWeight.w700 : null,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
                ),
                const SizedBox(width: CockpitSpacing.sm),
                _SpeakerChip(speaker: s.speaker, unsure: s.speakerUnsure),
                const SizedBox(width: CockpitSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.displayText, style: theme.textTheme.bodyMedium),
                      if (s.isCorrected || s.isLowConfidence) ...[
                        const SizedBox(height: CockpitSpacing.xxs),
                        Row(
                          children: [
                            if (s.isCorrected)
                              _tag(context, Icons.edit_rounded, 'Corrected',
                                  scheme.tertiary),
                            if (s.isLowConfidence)
                              _tag(context, Icons.error_outline_rounded,
                                  'Low confidence', CockpitColors.brand.warning),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: CockpitSpacing.md),
                for (final m in s.markers) ...[
                  _MarkerChip(marker: m),
                  const SizedBox(width: CockpitSpacing.sm),
                ],
                if (s.slide != null) ...[
                  _LinkChip(
                      icon: Icons.link_rounded, label: s.slide!.chipLabel),
                  const SizedBox(width: CockpitSpacing.sm),
                ],
                _SegmentMenu(
                    controller: controller, notes: notes, segment: s),
              ],
            ),
            if (selected) ...[
              const SizedBox(height: CockpitSpacing.md),
              Padding(
                padding: const EdgeInsets.only(left: 52),
                child: Row(
                  children: [
                    _ActionChip(
                      icon: Icons.note_add_outlined,
                      label: 'Add to Notes',
                      onTap: () => _addToNotes(context),
                    ),
                    const SizedBox(width: CockpitSpacing.sm),
                    _ActionChip(
                      icon: Icons.lightbulb_outline_rounded,
                      label: 'Explain',
                      onTap: () => _snack(context, 'Sent to AI (Panel 9)'),
                    ),
                    const SizedBox(width: CockpitSpacing.sm),
                    _ActionChip(
                      icon: Icons.search_rounded,
                      label: 'Research',
                      onTap: () => _snack(context, 'Sent to Research (Panel 10)'),
                    ),
                    const SizedBox(width: CockpitSpacing.sm),
                    _ActionChip(
                      icon: Icons.edit_outlined,
                      label: 'Correct',
                      onTap: () => _correct(context),
                    ),
                    const Spacer(),
                    if (s.typewriterLinked)
                      Row(
                        children: [
                          Icon(Icons.link_rounded,
                              size: 14, color: scheme.onSurfaceVariant),
                          const SizedBox(width: CockpitSpacing.xs),
                          Text('Linked to Typewriter',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tag(BuildContext context, IconData icon, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: CockpitSpacing.sm),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: color)),
        ],
      ),
    );
  }

  void _addToNotes(BuildContext context) {
    notes.addFromTranscript(
        segment.speaker.label, segment.start, segment.displayText);
    controller.markTypewriterLinked(segment.id);
    _snack(context,
        'Added to Typewriter · ${segment.speaker.label} · ${segment.start}');
  }

  Future<void> _correct(BuildContext context) async {
    final tc = TextEditingController(text: segment.displayText);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Correct text'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: tc, autofocus: true, maxLines: null),
            const SizedBox(height: CockpitSpacing.sm),
            Text('Raw ASR text is preserved and can be restored.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(tc.text),
              child: const Text('Save correction')),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      controller.correctText(segment.id, result.trim());
    }
  }
}

class _SpeakerChip extends StatelessWidget {
  const _SpeakerChip({required this.speaker, required this.unsure});
  final Speaker speaker;
  final bool unsure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Color color;
    switch (speaker) {
      case Speaker.professor:
        color = CockpitColors.brand.info;
      case Speaker.student:
        color = CockpitColors.brand.success;
      default:
        color = scheme.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(CockpitRadii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (unsure) ...[
            Icon(Icons.help_outline_rounded, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(speaker.label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _MarkerChip extends StatelessWidget {
  const _MarkerChip({required this.marker});
  final MarkerType marker;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(marker.icon, size: 12, color: scheme.primary),
          const SizedBox(width: 3),
          Text(marker.label,
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.primary)),
        ],
      ),
    );
  }
}

class _LinkChip extends StatelessWidget {
  const _LinkChip({required this.icon, required this.label});
  final IconData icon;
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: scheme.onSurfaceVariant),
          const SizedBox(width: 3),
          Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(CockpitRadii.sm),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: CockpitSpacing.md, vertical: CockpitSpacing.xs),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(CockpitRadii.sm),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: CockpitSpacing.xs),
            Text(label, style: theme.textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

class _SegmentMenu extends StatelessWidget {
  const _SegmentMenu({
    required this.controller,
    required this.notes,
    required this.segment,
  });
  final TranscriptController controller;
  final NotesController notes;
  final TranscriptSegment segment;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Segment actions',
      icon: Icon(Icons.more_vert_rounded,
          size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
      onSelected: (v) => _onSelected(context, v),
      itemBuilder: (context) => [
        _mi('addNotes', Icons.note_add_outlined, 'Add to Notes'),
        _mi('quote', Icons.format_quote_rounded, 'Quote'),
        _mi('explain', Icons.lightbulb_outline_rounded, 'Explain'),
        _mi('summarize', Icons.summarize_rounded, 'Summarize'),
        _mi('research', Icons.search_rounded, 'Research'),
        _mi('important', Icons.star_rounded, 'Mark Important'),
        _mi('question', Icons.help_outline_rounded, 'Create Question'),
        const PopupMenuDivider(),
        _mi('speaker', Icons.record_voice_over_rounded, 'Correct Speaker'),
        if (segment.isCorrected)
          _mi('restore', Icons.restore_rounded, 'Restore Original'),
        _mi('copy', Icons.link_rounded, 'Copy Link'),
      ],
    );
  }

  PopupMenuItem<String> _mi(String v, IconData i, String l) => PopupMenuItem(
        value: v,
        height: 40,
        child: Row(children: [
          Icon(i, size: 18),
          const SizedBox(width: CockpitSpacing.md),
          Text(l),
        ]),
      );

  void _onSelected(BuildContext context, String v) {
    switch (v) {
      case 'addNotes':
      case 'quote':
        notes.addFromTranscript(
            segment.speaker.label, segment.start, segment.displayText);
        controller.markTypewriterLinked(segment.id);
        _snack(context, 'Added to Typewriter');
      case 'explain':
        _snack(context, 'Sent to AI (Panel 9)');
      case 'summarize':
        _snack(context, 'Summarize → AI (Panel 9)');
      case 'research':
        _snack(context, 'Sent to Research (Panel 10)');
      case 'important':
        controller.addMarker(segment.id, MarkerType.important);
      case 'question':
        controller.addMarker(segment.id, MarkerType.question);
      case 'speaker':
        _correctSpeaker(context);
      case 'restore':
        controller.restoreOriginal(segment.id);
        _snack(context, 'Restored raw wording');
      case 'copy':
        _snack(context, 'Segment link copied');
    }
  }

  Future<void> _correctSpeaker(BuildContext context) async {
    final sel = await showDialog<Speaker>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Correct speaker'),
        children: [
          for (final sp in Speaker.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(sp),
              child: Text(sp.label),
            ),
        ],
      ),
    );
    if (sel != null) controller.correctSpeaker(segment.id, sel);
  }
}

/// Partial (still recognizing) text — muted, at the bottom (spec §5).
class _PartialTile extends StatelessWidget {
  const _PartialTile({required this.segment});
  final TranscriptSegment segment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.all(CockpitSpacing.sm),
      padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.md, vertical: CockpitSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CockpitRadii.sm),
        border: Border.all(
            color: scheme.outlineVariant,
            style: BorderStyle.solid),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(segment.start,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          _SpeakerChip(speaker: segment.speaker, unsure: false),
          const SizedBox(width: CockpitSpacing.md),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: '${segment.rawText}… ',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.more_horiz_rounded,
                        size: 14, color: scheme.onSurfaceVariant),
                    const SizedBox(width: CockpitSpacing.xs),
                    Text('Listening…',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ])),
          ),
        ],
      ),
    );
  }
}

class _JumpToLive extends StatelessWidget {
  const _JumpToLive({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary,
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: CockpitSpacing.lg, vertical: CockpitSpacing.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.arrow_downward_rounded,
                  size: 16, color: Colors.white),
              const SizedBox(width: CockpitSpacing.xs),
              Text('Jump to Live',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomStatus extends StatelessWidget {
  const _BottomStatus();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.lg, vertical: CockpitSpacing.sm),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded,
              size: 16, color: CockpitColors.brand.success),
          const SizedBox(width: CockpitSpacing.sm),
          Text('Saved · Live Sync',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const Spacer(),
          Icon(Icons.info_outline_rounded,
              size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: CockpitSpacing.xs),
          Text('Faithful Transcript available after class',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const Spacer(),
          Icon(Icons.sensors_rounded, size: 14, color: CockpitColors.brand.success),
          const SizedBox(width: CockpitSpacing.xs),
          Text('Following Live',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
  );
}
