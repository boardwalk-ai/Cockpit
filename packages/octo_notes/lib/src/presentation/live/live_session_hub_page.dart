import 'dart:async';

import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/ink_controller.dart';
import '../../domain/notes_controller.dart';
import '../../theme/octo_notes_theme.dart';
import '../magic_pencil/magic_pencil_workspace.dart';
import '../widgets/octo_widgets.dart';

/// Width at/above which the hub lays the two workspace cards side by side.
const double _kHubDesktop = 820;

/// Which surface fills the hub's middle region.
enum _HubView { cards, typewriter, pencil }

/// Panel 3 (redesign) — **Live Session Hub**.
///
/// The simplified session shell the boss/team asked for: a persistent Live
/// Transcription strip (On/Off) with an animated single-line subtitle across the
/// top, and Summarize / Finalize across the bottom. The middle region swaps
/// **in place** between two big workspace cards, the full Typewriter editor
/// (search + right add-to-note panel + upload), and the Magic Pencil canvas — a
/// Close button returns to the cards. No recording header; Finalize replaces
/// Finish Session. Borderless (`DESIGN.md`). See `docs/panel-03-live-workspace.md`.
class LiveSessionHubPage extends StatefulWidget {
  const LiveSessionHubPage({super.key});

  @override
  State<LiveSessionHubPage> createState() => _LiveSessionHubPageState();
}

class _LiveSessionHubPageState extends State<LiveSessionHubPage> {
  bool _transcriptionOn = true;
  bool _subExpanded = false;
  int _line = 0;
  Timer? _timer;

  _HubView _view = _HubView.cards;

  // Controllers for the embedded Magic Pencil canvas.
  late final InkController _ink;
  late final NotesController _notes;

  // Sample rolling transcript lines (mock live speech).
  static const _lines = <String>[
    'Glycolysis occurs in the cytoplasm and does not require oxygen.',
    'The net result is two ATP and two NADH.',
    'Pyruvate then enters the mitochondria for the next stage.',
    'The electron transport chain builds a proton gradient.',
    'Oxygen accepts electrons at the end of the transport chain.',
  ];

  @override
  void initState() {
    super.initState();
    _ink = InkController();
    _notes = NotesController(sessionId: 'sess-bio101-w4');
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ink.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    if (!_transcriptionOn) return;
    _timer = Timer.periodic(const Duration(milliseconds: 2600), (_) {
      if (!mounted) return;
      setState(() => _line = (_line + 1) % _lines.length);
    });
  }

  void _toggle(bool on) {
    setState(() {
      _transcriptionOn = on;
      if (!on) _timer?.cancel();
    });
    if (on) _startTimer();
  }

  void _setView(_HubView v) => setState(() => _view = v);

  void _back() => context.canPop() ? context.pop() : context.go('/notes');

  @override
  Widget build(BuildContext context) {
    return OctoNotesTheme.wrap(
      context: context,
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          final desktop = MediaQuery.sizeOf(context).width >= _kHubDesktop;
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
                        _TopBar(onBack: _back),
                        const SizedBox(height: CockpitSpacing.lg),
                        _TranscriptionStrip(
                          on: _transcriptionOn,
                          onChanged: _toggle,
                          lines: _lines,
                          current: _line,
                          expanded: _subExpanded,
                          onToggleExpand: () =>
                              setState(() => _subExpanded = !_subExpanded),
                        ),
                        const SizedBox(height: CockpitSpacing.lg),
                        Expanded(child: _middle(context, desktop)),
                        const SizedBox(height: CockpitSpacing.lg),
                        _BottomActions(
                          showUpload: _view == _HubView.typewriter,
                          onUpload: _upload,
                          onSummarize: () =>
                              _snack(context, 'Summarizing this session…'),
                          onFinalize: () => context.go('/notes/finalize'),
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

  Widget _middle(BuildContext context, bool desktop) {
    switch (_view) {
      case _HubView.cards:
        final cards = [
          _WorkspaceCard(
            icon: Icons.keyboard_rounded,
            title: 'Typewriter',
            subtitle: 'Type your notes',
            onTap: () => _setView(_HubView.typewriter),
          ),
          _WorkspaceCard(
            icon: Icons.gesture_rounded,
            title: 'Magic Pencil',
            subtitle: 'Free pencil drawing',
            onTap: () => _setView(_HubView.pencil),
          ),
        ];
        return desktop
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: CockpitSpacing.xl),
                  Expanded(child: cards[1]),
                ],
              )
            : Column(
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(height: CockpitSpacing.xl),
                  Expanded(child: cards[1]),
                ],
              );
      case _HubView.typewriter:
        return _TypewriterView(
          key: const ValueKey('tw'),
          onClose: () => _setView(_HubView.cards),
        );
      case _HubView.pencil:
        return _PencilView(
          ink: _ink,
          notes: _notes,
          onClose: () => _setView(_HubView.cards),
        );
    }
  }

  void _upload() {
    _snack(context, 'Uploaded existing notes into the Typewriter');
  }
}

// ===========================================================================
// Top bar — page identity only (no recording controls)
// ===========================================================================
class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: onBack,
        ),
        const SizedBox(width: CockpitSpacing.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Cellular Respiration Lecture',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            Text('Biology 101 • Week 4',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
        const Spacer(),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 8, color: CockpitColors.brand.success),
            const SizedBox(width: CockpitSpacing.xs),
            Text('All devices synced',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }
}

// ===========================================================================
// Live Transcription strip + animated subtitle
// ===========================================================================
class _TranscriptionStrip extends StatelessWidget {
  const _TranscriptionStrip({
    required this.on,
    required this.onChanged,
    required this.lines,
    required this.current,
    required this.expanded,
    required this.onToggleExpand,
  });
  final bool on;
  final ValueChanged<bool> onChanged;
  final List<String> lines;
  final int current;
  final bool expanded;
  final VoidCallback onToggleExpand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OctoSurface(
          padding: const EdgeInsets.symmetric(
              horizontal: CockpitSpacing.xl, vertical: CockpitSpacing.lg),
          child: Row(
            children: [
              Icon(Icons.graphic_eq_rounded,
                  size: 20,
                  color: on ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(width: CockpitSpacing.md),
              Text('Live Transcription',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              _OnOffToggle(on: on, onChanged: onChanged),
            ],
          ),
        ),
        const SizedBox(height: CockpitSpacing.sm),
        // Subtitles bar — one line collapsed, ~5 lines expanded. The chevron on
        // the right toggles it.
        OctoSurface(
          padding: const EdgeInsets.symmetric(
              horizontal: CockpitSpacing.xl, vertical: CockpitSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: !on
                    ? const _SubtitleOff()
                    : expanded
                        ? _SubtitleHistory(lines: lines, current: current)
                        : _SubtitleLine(text: lines[current]),
              ),
              const SizedBox(width: CockpitSpacing.md),
              InkWell(
                borderRadius: BorderRadius.circular(CockpitRadii.pill),
                onTap: onToggleExpand,
                child: Padding(
                  padding: const EdgeInsets.all(CockpitSpacing.xxs),
                  child: Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SubtitleOff extends StatelessWidget {
  const _SubtitleOff();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 26,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text('Subtitles paused',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ),
    );
  }
}

/// The collapsed single subtitle line, sliding up as it changes.
class _SubtitleLine extends StatelessWidget {
  const _SubtitleLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      height: 26,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        transitionBuilder: (child, anim) {
          final slide = Tween<Offset>(
            begin: const Offset(0, 0.9),
            end: Offset.zero,
          ).animate(anim);
          return ClipRect(
            child: SlideTransition(
              position: slide,
              child: FadeTransition(opacity: anim, child: child),
            ),
          );
        },
        child: Row(
          key: ValueKey(text),
          children: [
            Icon(Icons.circle, size: 8, color: scheme.primary),
            const SizedBox(width: CockpitSpacing.md),
            Expanded(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurface, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The expanded view — the last ~5 lines, newest (current) at the bottom.
class _SubtitleHistory extends StatelessWidget {
  const _SubtitleHistory({required this.lines, required this.current});
  final List<String> lines;
  final int current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final n = lines.length < 5 ? lines.length : 5;
    // A rolling window of the last n lines, ending at the current line.
    final window = [
      for (var i = n - 1; i >= 0; i--)
        lines[(current - i + lines.length) % lines.length],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < window.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Icon(Icons.circle,
                      size: 6,
                      color: i == window.length - 1
                          ? scheme.primary
                          : scheme.onSurfaceVariant.withValues(alpha: 0.4)),
                ),
                const SizedBox(width: CockpitSpacing.md),
                Expanded(
                  child: Text(window[i],
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: i == window.length - 1
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                        fontWeight: i == window.length - 1
                            ? FontWeight.w500
                            : FontWeight.w400,
                      )),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A borderless On/Off segmented toggle.
class _OnOffToggle extends StatelessWidget {
  const _OnOffToggle({required this.on, required this.onChanged});
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget seg(String label, bool value) {
      final selected = on == value;
      return InkWell(
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
        onTap: () => onChanged(value),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: CockpitSpacing.lg, vertical: CockpitSpacing.sm),
          decoration: BoxDecoration(
            color: selected
                ? (value ? scheme.primary : scheme.surfaceContainerHighest)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(CockpitRadii.pill),
          ),
          child: Text(label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: selected
                    ? (value ? Colors.white : scheme.onSurface)
                    : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              )),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.xxs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [seg('On', true), seg('Off', false)],
      ),
    );
  }
}

// ===========================================================================
// Big workspace card (tap → open in place)
// ===========================================================================
class _WorkspaceCard extends StatefulWidget {
  const _WorkspaceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  State<_WorkspaceCard> createState() => _WorkspaceCardState();
}

class _WorkspaceCardState extends State<_WorkspaceCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.01 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Material(
          color: _hover ? scheme.surfaceContainer : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(CockpitRadii.lg),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(CockpitSpacing.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(widget.icon, size: 30, color: scheme.primary),
                      const Spacer(),
                      Icon(Icons.north_east_rounded,
                          size: 20, color: scheme.onSurfaceVariant),
                    ],
                  ),
                  const Spacer(),
                  Text(widget.title,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: CockpitSpacing.xs),
                  Text(widget.subtitle,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: CockpitSpacing.lg),
                  Row(
                    children: [
                      Text('Open',
                          style: theme.textTheme.labelLarge
                              ?.copyWith(color: scheme.primary)),
                      const SizedBox(width: CockpitSpacing.xs),
                      Icon(Icons.arrow_forward_rounded,
                          size: 16, color: scheme.primary),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A subtle title + Close(×) header shared by the two editor views.
class _EditorHeader extends StatelessWidget {
  const _EditorHeader({required this.title, required this.onClose});
  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Text(title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const Spacer(),
        IconButton(
          tooltip: 'Close',
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
              backgroundColor: scheme.surfaceContainerHigh),
          icon: const Icon(Icons.close_rounded, size: 18),
          onPressed: onClose,
        ),
      ],
    );
  }
}

// ===========================================================================
// Typewriter view (search + main editor + right add-to-note panel)
// ===========================================================================
class _TypewriterView extends StatefulWidget {
  const _TypewriterView({super.key, required this.onClose});
  final VoidCallback onClose;

  @override
  State<_TypewriterView> createState() => _TypewriterViewState();
}

class _TypewriterViewState extends State<_TypewriterView> {
  final TextEditingController _note = TextEditingController(
      text: 'Cellular Respiration\n\n1. Glycolysis\n- Occurs in the cytoplasm\n');
  String _query = '';

  // Relevant data the student can pull into the note (spec: search / upload →
  // "add to note"). Mock course sources.
  static const _data = <({String source, String text})>[
    (source: 'Transcript • 18:32', text: 'The net result is two ATP and two NADH.'),
    (source: 'Week 4 Slides • Slide 7', text: 'Oxygen acts as the final electron acceptor.'),
    (source: 'Transcript • 18:25', text: 'Glycolysis occurs in the cytoplasm.'),
    (source: 'Definition', text: 'Glycolysis — the breakdown of glucose into pyruvate.'),
    (source: 'AI Explanation', text: 'ATP synthase uses the proton gradient to make ATP.'),
    (source: 'Week 4 Slides • Slide 4', text: 'Glucose is split into two pyruvate molecules.'),
  ];

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _addToNote(String text) {
    final base = _note.text.trimRight();
    _note.text = base.isEmpty ? '- $text\n' : '$base\n- $text\n';
    _note.selection =
        TextSelection.collapsed(offset: _note.text.length);
    _snack(context, 'Added to note');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final results = _query.trim().isEmpty
        ? _data
        : _data
            .where((d) =>
                d.text.toLowerCase().contains(_query.toLowerCase()) ||
                d.source.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EditorHeader(title: 'Typewriter Editor', onClose: widget.onClose),
        const SizedBox(height: CockpitSpacing.md),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Main editor + search.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search transcript, slides, definitions…',
                        prefixIcon: Icon(Icons.search_rounded,
                            color: scheme.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(height: CockpitSpacing.md),
                    Expanded(
                      child: OctoSurface(
                        padding: const EdgeInsets.all(CockpitSpacing.lg),
                        child: TextField(
                          controller: _note,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          style: theme.textTheme.bodyLarge,
                          cursorColor: scheme.primary,
                          decoration: const InputDecoration(
                            isCollapsed: true,
                            filled: false,
                            border: InputBorder.none,
                            hintText: 'Type your notes…',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: CockpitSpacing.lg),
              // Right: relevant data → Add to note.
              SizedBox(
                width: 280,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Eyebrow('Relevant Data'),
                    const SizedBox(height: CockpitSpacing.md),
                    Expanded(
                      child: results.isEmpty
                          ? Center(
                              child: Text('No matches',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant)),
                            )
                          : ListView.separated(
                              padding: EdgeInsets.zero,
                              itemCount: results.length,
                              separatorBuilder: (_, _) => const SizedBox(
                                  height: CockpitSpacing.sm),
                              itemBuilder: (context, i) => _DataCard(
                                source: results[i].source,
                                text: results[i].text,
                                onAdd: () => _addToNote(results[i].text),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DataCard extends StatelessWidget {
  const _DataCard(
      {required this.source, required this.text, required this.onAdd});
  final String source;
  final String text;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return OctoSurface(
      padding: const EdgeInsets.all(CockpitSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(source,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: CockpitSpacing.xs),
          Text(text, style: theme.textTheme.bodyMedium),
          const SizedBox(height: CockpitSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onAdd,
              style: TextButton.styleFrom(
                foregroundColor: scheme.primary,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                    horizontal: CockpitSpacing.sm),
              ),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add to note'),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Magic Pencil view (reuses the drawing workspace)
// ===========================================================================
class _PencilView extends StatelessWidget {
  const _PencilView(
      {required this.ink, required this.notes, required this.onClose});
  final InkController ink;
  final NotesController notes;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EditorHeader(title: 'Magic Pencil', onClose: onClose),
        const SizedBox(height: CockpitSpacing.md),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(CockpitRadii.lg),
            child: Material(
              color: scheme.surfaceContainerLow,
              child: MagicPencilWorkspace(
                ink: ink,
                notes: notes,
                workspaceToggle: const SizedBox.shrink(),
                onSwitchToTypewriter: onClose,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Bottom actions — Upload (left, typewriter only) · Summarize · Finalize
// ===========================================================================
class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.showUpload,
    required this.onUpload,
    required this.onSummarize,
    required this.onFinalize,
  });
  final bool showUpload;
  final VoidCallback onUpload;
  final VoidCallback onSummarize;
  final VoidCallback onFinalize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: showUpload
                ? OutlinedButton.icon(
                    onPressed: onUpload,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.onSurface,
                      side: BorderSide(color: scheme.outlineVariant),
                      padding: const EdgeInsets.symmetric(
                          horizontal: CockpitSpacing.lg,
                          vertical: CockpitSpacing.md),
                    ),
                    icon: const Icon(Icons.upload_file_outlined, size: 18),
                    label: const Text('Upload'),
                  )
                : const SizedBox.shrink(),
          ),
        ),
        OutlinedButton.icon(
          onPressed: onSummarize,
          style: OutlinedButton.styleFrom(
            foregroundColor: scheme.onSurface,
            side: BorderSide(color: scheme.outlineVariant),
            padding: const EdgeInsets.symmetric(
                horizontal: CockpitSpacing.xl, vertical: CockpitSpacing.md),
          ),
          icon: const Icon(Icons.auto_awesome_rounded, size: 18),
          label: const Text('Summarize'),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: onFinalize,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: CockpitSpacing.xl, vertical: CockpitSpacing.md),
              ),
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Finalize'),
            ),
          ),
        ),
      ],
    );
  }
}

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
  );
}
