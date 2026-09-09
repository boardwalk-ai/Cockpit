import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../domain/ai_assistant_controller.dart';
import '../../domain/ink_controller.dart';
import '../../domain/materials_controller.dart';
import '../../domain/notes_controller.dart';
import '../../domain/notes_models.dart';
import '../../domain/organization_controller.dart';
import '../../domain/research_controller.dart';
import '../../domain/transcript_controller.dart';
import '../../theme/octo_notes_theme.dart';
import '../ai/ai_assistant_panel.dart';
import '../devices/connected_devices_panel.dart';
import '../magic_pencil/magic_pencil_workspace.dart';
import '../materials/materials_panel.dart';
import '../organization/organize_panel.dart';
import '../research/research_panel.dart';
import '../transcript/live_transcript_panel.dart';

/// Width at/above which the session screen uses the desktop editor + rail
/// layout.
const double _kSessionDesktop = 1000;

/// OctoNotes — live note-taking session, **Typewriter** workspace (Panel 5).
///
/// Backed by a [NotesController]: the student's typed blocks are the
/// authoritative layer, AI produces separate suggestions that must be approved,
/// and every edit commits to memory immediately. See
/// `docs/panel-05-typewriter.md`.
class OctoNotesSessionPage extends StatefulWidget {
  const OctoNotesSessionPage({super.key, this.startInPencil = false});

  /// When opened from the Live Session Hub's Magic Pencil card, start on the
  /// Magic Pencil canvas instead of the Typewriter.
  final bool startInPencil;

  @override
  State<OctoNotesSessionPage> createState() => _OctoNotesSessionPageState();
}

class _OctoNotesSessionPageState extends State<OctoNotesSessionPage> {
  late final NotesController _c;
  late final InkController _ink;
  late final TranscriptController _t;
  late final MaterialsController _mat;
  late final AiAssistantController _ai;
  late final ResearchController _research;
  late final OrganizationController _org;
  int _rail = -1; // open rail panel: -1 none, 0 Materials, 1 AI, 2 Research, 3 Organize
  bool _transcriptOpen = false;
  bool _transcriptFull = false;

  @override
  void initState() {
    super.initState();
    _c = NotesController(sessionId: 'sess-bio101-w4');
    _ink = InkController();
    _t = TranscriptController(sessionId: 'sess-bio101-w4');
    _mat = MaterialsController(sessionId: 'sess-bio101-w4');
    _ai = AiAssistantController();
    _research = ResearchController();
    _org = OrganizationController();
    if (widget.startInPencil) _c.setMagicPencil(true);
  }

  @override
  void dispose() {
    _c.dispose();
    _ink.dispose();
    _t.dispose();
    _mat.dispose();
    _ai.dispose();
    _research.dispose();
    _org.dispose();
    super.dispose();
  }

  void _end() => context.canPop() ? context.pop() : context.go('/notes');

  void _finish() => context.go('/notes/review');

  @override
  Widget build(BuildContext context) {
    return OctoNotesTheme.wrap(
      context: context,
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          final desktop = MediaQuery.sizeOf(context).width >= _kSessionDesktop;
          return AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              return Scaffold(
                backgroundColor: scheme.surface,
                body: SafeArea(
                  child: Column(
                    children: [
                      _SessionTopBar(
                          controller: _c, onBack: _end, onFinish: _finish),
                      Divider(height: 1, color: scheme.outlineVariant),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _c.magicPencil
                                  ? MagicPencilWorkspace(
                                      ink: _ink,
                                      notes: _c,
                                      workspaceToggle: _WorkspaceToggle(
                                        magicPencil: true,
                                        onChanged: _c.setMagicPencil,
                                      ),
                                      onSwitchToTypewriter: () =>
                                          _c.setMagicPencil(false),
                                    )
                                  : _Editor(controller: _c),
                            ),
                            if (desktop && !_c.magicPencil) ...[
                              if (_rail != -1) ...[
                                VerticalDivider(
                                    width: 1, color: scheme.outlineVariant),
                                SizedBox(
                                  width: 500,
                                  child: switch (_rail) {
                                    0 => MaterialsPanel(
                                        controller: _mat,
                                        notes: _c,
                                        onClose: () =>
                                            setState(() => _rail = -1),
                                        onAnnotate: () {
                                          _c.setMagicPencil(true);
                                          setState(() => _rail = -1);
                                        },
                                        onOpenTranscript: () => setState(
                                            () => _transcriptOpen = true),
                                      ),
                                    1 => AiAssistantPanel(
                                        controller: _ai,
                                        notes: _c,
                                        onClose: () =>
                                            setState(() => _rail = -1),
                                        onResearch: () =>
                                            setState(() => _rail = 2),
                                      ),
                                    2 => ResearchPanel(
                                        controller: _research,
                                        notes: _c,
                                        onClose: () =>
                                            setState(() => _rail = -1),
                                      ),
                                    3 => OrganizePanel(
                                        controller: _org,
                                        onClose: () =>
                                            setState(() => _rail = -1),
                                      ),
                                    _ => const SizedBox.shrink(),
                                  },
                                ),
                              ],
                              VerticalDivider(
                                  width: 1, color: scheme.outlineVariant),
                              _RightRail(
                                controller: _c,
                                selected: _rail,
                                onSelect: (i) => setState(
                                    () => _rail = _rail == i ? -1 : i),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Divider(height: 1, color: scheme.outlineVariant),
                      _StatusFooter(controller: _c),
                      Divider(height: 1, color: scheme.outlineVariant),
                      if (_transcriptOpen)
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height *
                              (_transcriptFull ? 0.82 : 0.46),
                          child: LiveTranscriptPanel(
                            controller: _t,
                            notes: _c,
                            full: _transcriptFull,
                            onCollapse: () => setState(() {
                              _transcriptOpen = false;
                              _transcriptFull = false;
                            }),
                            onToggleFull: () => setState(
                                () => _transcriptFull = !_transcriptFull),
                            onSwitchToTypewriter: () =>
                                _c.setMagicPencil(false),
                          ),
                        )
                      else
                        _CollapsedTranscriptBar(
                          controller: _t,
                          onExpand: () =>
                              setState(() => _transcriptOpen = true),
                        ),
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
// Top bar
// ===========================================================================
class _SessionTopBar extends StatelessWidget {
  const _SessionTopBar({
    required this.controller,
    required this.onBack,
    required this.onFinish,
  });
  final NotesController controller;
  final VoidCallback onBack;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Cellular Respiration Lecture',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
                Text('Biology 101 • Week 4',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: CockpitSpacing.md),
          const _LiveBadge(),
          const Spacer(),
          if (!compact) ...[
            Icon(Icons.phone_iphone_rounded, size: 16, color: scheme.primary),
            const SizedBox(width: CockpitSpacing.xs),
            Text("Recording on Hein's iPhone",
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(width: CockpitSpacing.md),
            Text('42:16',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
            const SizedBox(width: CockpitSpacing.md),
          ],
          const _LiveSyncButton(),
          const SizedBox(width: CockpitSpacing.sm),
          IconButton.filledTonal(
            icon: const Icon(Icons.pause_rounded),
            onPressed: () {},
          ),
          const SizedBox(width: CockpitSpacing.xs),
          IconButton.filledTonal(
            style: IconButton.styleFrom(
              backgroundColor: scheme.primary.withValues(alpha: 0.16),
            ),
            icon: Icon(Icons.stop_rounded, color: scheme.primary),
            onPressed: () {},
          ),
          const SizedBox(width: CockpitSpacing.sm),
          Badge(
            label: const Text('3'),
            backgroundColor: scheme.primary,
            child: IconButton(
              icon: const Icon(Icons.notifications_none_rounded),
              onPressed: () {},
            ),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.primary,
              side: BorderSide(color: scheme.primary),
            ),
            onPressed: onFinish,
            child: const Text('Finish Session'),
          ),
        ],
      ),
    );
  }
}

/// Tappable "Live Sync" indicator → opens Panel 12 (Connected Devices & Sync).
class _LiveSyncButton extends StatelessWidget {
  const _LiveSyncButton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
      onTap: () => showConnectedDevicesDialog(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.sm,
          vertical: CockpitSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 8, color: CockpitColors.brand.success),
            const SizedBox(width: CockpitSpacing.xs),
            Text('Live Sync', style: theme.textTheme.labelMedium),
            Icon(Icons.expand_more_rounded,
                size: 16, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CockpitSpacing.md,
        vertical: CockpitSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, size: 8, color: Colors.white),
          const SizedBox(width: CockpitSpacing.xs),
          Text('LIVE',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  )),
        ],
      ),
    );
  }
}

// ===========================================================================
// Editor
// ===========================================================================
class _Editor extends StatelessWidget {
  const _Editor({required this.controller});
  final NotesController controller;

  @override
  Widget build(BuildContext context) {
    final blocks = controller.blocks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(CockpitSpacing.md),
          child: Center(
            child: _WorkspaceToggle(
              magicPencil: controller.magicPencil,
              onChanged: controller.setMagicPencil,
            ),
          ),
        ),
        _EditorToolbar(controller: controller),
        if (controller.selectedCount > 1)
          _MultiSelectBar(controller: controller),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: blocks.isEmpty
                  ? _EmptyCanvas(controller: controller)
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.fromLTRB(
                        CockpitSpacing.lg,
                        CockpitSpacing.lg,
                        CockpitSpacing.xl,
                        CockpitSpacing.md,
                      ),
                      header: Padding(
                        padding: const EdgeInsets.only(
                            left: 34, bottom: CockpitSpacing.lg),
                        child: _DocTitleField(controller: controller),
                      ),
                      footer: Padding(
                        padding: const EdgeInsets.only(
                            left: 34, top: CockpitSpacing.md),
                        child: _MagicBar(controller: controller),
                      ),
                      itemCount: blocks.length,
                      onReorderItem: controller.reorder,
                      proxyDecorator: (child, index, animation) =>
                          Material(color: Colors.transparent, child: child),
                      itemBuilder: (context, i) {
                        final b = blocks[i];
                        return _BlockRow(
                          key: ValueKey(b.id),
                          controller: controller,
                          block: b,
                          index: i,
                        );
                      },
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WorkspaceToggle extends StatelessWidget {
  const _WorkspaceToggle({required this.magicPencil, required this.onChanged});
  final bool magicPencil;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const items = [
      (Icons.keyboard_rounded, 'Typewriter'),
      (Icons.auto_fix_high_rounded, 'Magic Pencil'),
    ];
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.xxs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++)
            InkWell(
              borderRadius: BorderRadius.circular(CockpitRadii.pill),
              onTap: () => onChanged(i == 1),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: CockpitSpacing.lg,
                  vertical: CockpitSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: (magicPencil ? i == 1 : i == 0)
                      ? scheme.surfaceContainerLowest
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(CockpitRadii.pill),
                  border: Border.all(
                    color: (magicPencil ? i == 1 : i == 0)
                        ? scheme.outlineVariant
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(items[i].$1,
                        size: 18,
                        color: (magicPencil ? i == 1 : i == 0)
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant),
                    const SizedBox(width: CockpitSpacing.sm),
                    Text(items[i].$2,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: (magicPencil ? i == 1 : i == 0)
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        )),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({required this.controller});
  final NotesController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final focused = controller.focusedId;

    void applyType(BlockType t) {
      if (focused != null) {
        controller.setType(focused, t);
      } else {
        controller.addBlockAtEnd(type: t);
      }
    }

    Widget iconBtn(IconData i, VoidCallback onTap, {bool enabled = true}) =>
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(i,
              size: 20,
              color: enabled ? scheme.onSurfaceVariant : scheme.outlineVariant),
          onPressed: enabled ? onTap : null,
        );
    Widget sep() => Container(
          width: 1,
          height: 20,
          margin: const EdgeInsets.symmetric(horizontal: CockpitSpacing.xs),
          color: scheme.outlineVariant,
        );
    Widget dropdown(String label, BlockType type) => InkWell(
          borderRadius: BorderRadius.circular(CockpitRadii.sm),
          onTap: () => applyType(type),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CockpitSpacing.sm,
              vertical: CockpitSpacing.xs,
            ),
            child: Text(label, style: theme.textTheme.labelLarge),
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CockpitSpacing.lg,
        vertical: CockpitSpacing.xs,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: scheme.outlineVariant),
          bottom: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Row(
            children: [
              dropdown('H1', BlockType.h1),
              dropdown('H2', BlockType.h2),
              dropdown('H3', BlockType.h3),
              sep(),
              iconBtn(Icons.format_bold_rounded, () {}),
              iconBtn(Icons.format_italic_rounded, () {}),
              sep(),
              iconBtn(Icons.format_list_bulleted_rounded,
                  () => applyType(BlockType.bulleted)),
              iconBtn(Icons.format_list_numbered_rounded,
                  () => applyType(BlockType.numbered)),
              iconBtn(Icons.checklist_rounded,
                  () => applyType(BlockType.checklist)),
              iconBtn(Icons.format_quote_rounded,
                  () => applyType(BlockType.quote)),
              sep(),
              iconBtn(Icons.table_chart_outlined,
                  () => applyType(BlockType.table)),
              iconBtn(Icons.image_outlined, () => applyType(BlockType.image)),
              iconBtn(Icons.functions_rounded,
                  () => applyType(BlockType.formula)),
              sep(),
              iconBtn(Icons.undo_rounded, controller.undo,
                  enabled: controller.canUndo),
              iconBtn(Icons.redo_rounded, controller.redo,
                  enabled: controller.canRedo),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => _showBlockTypePicker(context, applyType),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: scheme.outlineVariant),
                ),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Insert Block'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A grouped picker over all block types (spec §4).
Future<void> _showBlockTypePicker(
    BuildContext context, ValueChanged<BlockType> onPick) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      Widget group(String title, List<BlockType> types) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    CockpitSpacing.lg, CockpitSpacing.md, CockpitSpacing.lg, 0),
                child: Text(title,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
              Wrap(
                spacing: CockpitSpacing.sm,
                runSpacing: CockpitSpacing.sm,
                children: [
                  for (final t in types)
                    ActionChip(
                      avatar: Icon(t.icon, size: 16),
                      label: Text(t.label),
                      onPressed: () {
                        Navigator.of(context).pop();
                        onPick(t);
                      },
                    ),
                ],
              ),
            ],
          );
      return SingleChildScrollView(
        padding: const EdgeInsets.all(CockpitSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Insert block', style: theme.textTheme.titleMedium),
            group('Text', const [
              BlockType.paragraph,
              BlockType.h1,
              BlockType.h2,
              BlockType.h3,
              BlockType.bulleted,
              BlockType.numbered,
              BlockType.checklist,
              BlockType.quote,
            ]),
            const SizedBox(height: CockpitSpacing.sm),
            group('Academic', const [
              BlockType.definition,
              BlockType.keyIdea,
              BlockType.formula,
              BlockType.example,
              BlockType.question,
              BlockType.examHint,
              BlockType.warning,
              BlockType.assignment,
              BlockType.summary,
            ]),
            const SizedBox(height: CockpitSpacing.sm),
            group('Rich content', const [
              BlockType.table,
              BlockType.image,
              BlockType.diagram,
              BlockType.slideRef,
              BlockType.pdfExcerpt,
              BlockType.transcriptExcerpt,
              BlockType.audioTimestamp,
              BlockType.divider,
            ]),
          ],
        ),
      );
    },
  );
}

class _DocTitleField extends StatefulWidget {
  const _DocTitleField({required this.controller});
  final NotesController controller;

  @override
  State<_DocTitleField> createState() => _DocTitleFieldState();
}

class _DocTitleFieldState extends State<_DocTitleField> {
  late final TextEditingController _tc =
      TextEditingController(text: widget.controller.docTitle);

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: _tc,
      onChanged: (v) => widget.controller.docTitle = v,
      style: theme.textTheme.headlineMedium
          ?.copyWith(fontWeight: FontWeight.w700),
      decoration: const InputDecoration(
        isCollapsed: true,
        filled: false,
        border: InputBorder.none,
        hintText: 'Untitled note',
      ),
    );
  }
}

// ===========================================================================
// Block row: gutter (handle + hover menu) + content + suggestions
// ===========================================================================
class _BlockRow extends StatefulWidget {
  const _BlockRow({
    super.key,
    required this.controller,
    required this.block,
    required this.index,
  });
  final NotesController controller;
  final TypedBlock block;
  final int index;

  @override
  State<_BlockRow> createState() => _BlockRowState();
}

class _BlockRowState extends State<_BlockRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = widget.controller;
    final b = widget.block;
    final selected = c.isSelected(b.id);
    final focused = c.focusedId == b.id;
    final active = _hover || selected || focused;
    final sugg = c.suggestionsFor(b.id);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Padding(
        padding: const EdgeInsets.only(bottom: CockpitSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (focused && b.type.isTextEditable)
              Padding(
                padding: const EdgeInsets.only(left: 34, bottom: 4),
                child: _BlockActionBar(controller: c, block: b),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Gutter: 6-dot drag handle (subtle until active) + menu.
                SizedBox(
                  width: 30,
                  child: AnimatedOpacity(
                    opacity: active ? 1 : 0,
                    duration: const Duration(milliseconds: 120),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ReorderableDragStartListener(
                          index: widget.index,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.grab,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Icon(Icons.drag_indicator,
                                  size: 18, color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                        _BlockMenuButton(controller: c, block: b),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    decoration: b.isAi
                        ? BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.05),
                            borderRadius:
                                BorderRadius.circular(CockpitRadii.sm),
                            border: Border(
                              left: BorderSide(color: scheme.primary, width: 2),
                            ),
                          )
                        : selected
                            ? BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.06),
                                borderRadius:
                                    BorderRadius.circular(CockpitRadii.sm),
                              )
                            : null,
                    padding: b.isAi
                        ? const EdgeInsets.fromLTRB(
                            CockpitSpacing.md, CockpitSpacing.xs,
                            CockpitSpacing.sm, CockpitSpacing.xs)
                        : EdgeInsets.zero,
                    child: _BlockContent(
                      controller: c,
                      block: b,
                      showMeta: active,
                    ),
                  ),
                ),
              ],
            ),
            if (c.showsKeywordExpand(b))
              Padding(
                padding: const EdgeInsets.only(left: 34, top: 4),
                child: _KeywordExpandChip(
                  onTap: () => c.requestSuggestion(
                      b.id, AiAction.expandKeywords),
                ),
              ),
            for (final s in sugg)
              Padding(
                padding: const EdgeInsets.only(
                    left: 34, top: CockpitSpacing.sm),
                child: _SuggestionCard(controller: c, suggestion: s),
              ),
          ],
        ),
      ),
    );
  }
}

/// The tappable block-controls menu (spec §6).
class _BlockMenuButton extends StatelessWidget {
  const _BlockMenuButton({required this.controller, required this.block});
  final NotesController controller;
  final TypedBlock block;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: 'Block actions',
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_horiz_rounded,
          size: 16, color: scheme.onSurfaceVariant),
      onSelected: (v) => _onSelected(context, v),
      itemBuilder: (context) => [
        _mi('duplicate', Icons.copy_rounded, 'Duplicate'),
        _mi('convert', Icons.swap_horiz_rounded, 'Convert type…'),
        _mi('sendAi', Icons.auto_awesome_rounded, 'Send to AI'),
        _mi('study', Icons.school_rounded,
            block.studyStudioSelected
                ? 'Remove from Study Studio'
                : 'Add to Study Studio selection'),
        _mi('linkSlide', Icons.link_rounded, 'Link to slide'),
        _mi('linkTranscript', Icons.record_voice_over_rounded,
            'Link to transcript'),
        const PopupMenuDivider(),
        _mi('indent', Icons.format_indent_increase_rounded, 'Indent'),
        _mi('outdent', Icons.format_indent_decrease_rounded, 'Outdent'),
        _mi('up', Icons.arrow_upward_rounded, 'Move up'),
        _mi('down', Icons.arrow_downward_rounded, 'Move down'),
        _mi('select', Icons.check_box_outlined, 'Select block'),
        _mi('history', Icons.history_rounded, 'View block history'),
        const PopupMenuDivider(),
        _mi('delete', Icons.delete_outline_rounded, 'Delete'),
      ],
    );
  }

  PopupMenuItem<String> _mi(String v, IconData i, String label) =>
      PopupMenuItem(
        value: v,
        height: 40,
        child: Row(
          children: [
            Icon(i, size: 18),
            const SizedBox(width: CockpitSpacing.md),
            Text(label),
          ],
        ),
      );

  void _onSelected(BuildContext context, String v) {
    final c = controller;
    switch (v) {
      case 'duplicate':
        c.duplicateBlock(block.id);
      case 'convert':
        _showBlockTypePicker(context, (t) => c.setType(block.id, t));
      case 'sendAi':
        c.requestSuggestion(block.id, AiAction.expand);
      case 'study':
        c.toggleStudyStudioSelection(block.id);
      case 'linkSlide':
        c.setSource(block.id,
            const SourceRef(material: 'Week 4 Slides', location: 'Slide 7'));
      case 'linkTranscript':
        _snack(context, 'Linked to transcript 18:44');
      case 'indent':
        c.indent(block.id, 1);
      case 'outdent':
        c.indent(block.id, -1);
      case 'up':
        c.moveUp(block.id);
      case 'down':
        c.moveDown(block.id);
      case 'select':
        c.toggleSelect(block.id);
      case 'history':
        _showBlockHistory(context, block);
      case 'delete':
        c.deleteBlock(block.id);
    }
  }
}

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
  );
}

void _showBlockHistory(BuildContext context, TypedBlock b) {
  showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      Widget row(String k, String v) => Padding(
            padding: const EdgeInsets.only(bottom: CockpitSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                    width: 120,
                    child: Text(k,
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant))),
                Expanded(child: Text(v, style: theme.textTheme.bodyMedium)),
              ],
            ),
          );
      return AlertDialog(
        title: const Text('Block history'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            row('Block ID', b.id),
            row('Type', b.type.label),
            row('Origin',
                b.isAi ? 'AI, inserted by student' : 'Student written'),
            row('Revision', 'v${b.revision}'),
            row('Created', b.createdAt.toString().split('.').first),
            row('Modified', b.modifiedAt.toString().split('.').first),
            row('Device', b.device),
            if (b.audioTimestamp != null) row('Audio', b.audioTimestamp!),
            if (b.source != null) row('Source', b.source!.chipLabel),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close')),
        ],
      );
    },
  );
}

/// Compact contextual toolbar shown above the focused block (spec §12).
class _BlockActionBar extends StatelessWidget {
  const _BlockActionBar({required this.controller, required this.block});
  final NotesController controller;
  final TypedBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget action(IconData icon, String label, AiAction a) => InkWell(
          borderRadius: BorderRadius.circular(CockpitRadii.sm),
          onTap: () => controller.requestSuggestion(block.id, a),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: CockpitSpacing.sm, vertical: CockpitSpacing.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: scheme.onSurfaceVariant),
                const SizedBox(width: CockpitSpacing.xs),
                Text(label, style: theme.textTheme.labelMedium),
              ],
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.xxs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(CockpitRadii.sm),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          action(Icons.lightbulb_outline_rounded, 'Explain', AiAction.explain),
          action(Icons.open_in_full_rounded, 'Expand', AiAction.expand),
          action(Icons.compress_rounded, 'Simplify', AiAction.simplify),
          action(Icons.search_rounded, 'Research', AiAction.research),
        ],
      ),
    );
  }
}

// ===========================================================================
// Block content (per type) with an editable field
// ===========================================================================
class _BlockContent extends StatelessWidget {
  const _BlockContent({
    required this.controller,
    required this.block,
    required this.showMeta,
  });
  final NotesController controller;
  final TypedBlock block;
  final bool showMeta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (block.type == BlockType.divider) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.md),
        child: Divider(color: scheme.outline),
      );
    }

    if (!block.type.isTextEditable) {
      return _RichPlaceholder(block: block);
    }

    final field = _BlockField(
      key: ValueKey('f_${block.id}'),
      controller: controller,
      block: block,
    );

    Widget withMeta(Widget child) {
      final chips = <Widget>[
        if (block.isAi) const _AiTag(),
        if (block.studyStudioSelected)
          const _MetaChip(icon: Icons.school_rounded, label: 'Study'),
        if (block.source != null)
          _MetaChip(icon: Icons.link_rounded, label: block.source!.chipLabel),
        if (showMeta && block.audioTimestamp != null)
          _MetaChip(
              icon: Icons.schedule_rounded, label: block.audioTimestamp!),
      ];
      if (chips.isEmpty) return child;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: child),
          const SizedBox(width: CockpitSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(spacing: CockpitSpacing.xs, children: chips),
          ),
        ],
      );
    }

    // Academic blocks: tinted callout with an accent + icon.
    if (block.type.category == BlockCategory.academic) {
      final accent = _academicColor(block.type, scheme);
      return withMeta(Container(
        padding: const EdgeInsets.symmetric(
            horizontal: CockpitSpacing.md, vertical: CockpitSpacing.sm),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(CockpitRadii.sm),
          border: Border(left: BorderSide(color: accent, width: 3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6, right: CockpitSpacing.sm),
              child: Icon(block.type.icon, size: 18, color: accent),
            ),
            Expanded(child: field),
          ],
        ),
      ));
    }

    // List blocks: leading marker.
    if (block.type == BlockType.bulleted ||
        block.type == BlockType.numbered ||
        block.type == BlockType.checklist) {
      Widget marker;
      if (block.type == BlockType.checklist) {
        marker = Padding(
          padding: const EdgeInsets.only(top: 2, right: CockpitSpacing.sm),
          child: GestureDetector(
            onTap: () => controller.toggleChecked(block.id),
            child: Icon(
                block.checked
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                size: 20,
                color: block.checked ? scheme.primary : scheme.onSurfaceVariant),
          ),
        );
      } else if (block.type == BlockType.bulleted) {
        marker = Padding(
          padding: const EdgeInsets.only(top: 9, right: CockpitSpacing.md),
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
                color: scheme.onSurfaceVariant, shape: BoxShape.circle),
          ),
        );
      } else {
        marker = Padding(
          padding: const EdgeInsets.only(top: 2, right: CockpitSpacing.sm),
          child: Text('•',
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        );
      }
      return withMeta(Padding(
        padding: EdgeInsets.only(left: block.indent * 20.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [marker, Expanded(child: field)],
        ),
      ));
    }

    // Quote: left bar.
    if (block.type == BlockType.quote) {
      return withMeta(Container(
        padding: const EdgeInsets.only(left: CockpitSpacing.md),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: scheme.outline, width: 3)),
        ),
        child: field,
      ));
    }

    return withMeta(field);
  }
}

Color _academicColor(BlockType t, ColorScheme scheme) {
  switch (t) {
    case BlockType.definition:
      return scheme.tertiary;
    case BlockType.keyIdea:
      return scheme.tertiary;
    case BlockType.formula:
      return scheme.secondary;
    case BlockType.example:
      return CockpitColors.brand.success;
    case BlockType.question:
      return scheme.onSurfaceVariant;
    case BlockType.examHint:
      return scheme.primary;
    case BlockType.warning:
      return CockpitColors.brand.warning;
    case BlockType.assignment:
      return CockpitColors.brand.info;
    case BlockType.summary:
      return scheme.tertiary;
    default:
      return scheme.primary;
  }
}

/// The actual editable text field for a block, with markdown + slash + Enter /
/// Backspace behavior and a selection context menu of AI actions.
class _BlockField extends StatefulWidget {
  const _BlockField({super.key, required this.controller, required this.block});
  final NotesController controller;
  final TypedBlock block;

  @override
  State<_BlockField> createState() => _BlockFieldState();
}

class _BlockFieldState extends State<_BlockField> {
  late final TextEditingController _tc =
      TextEditingController(text: widget.block.text);
  late final FocusNode _fn = FocusNode(onKeyEvent: _onKey);
  String _slash = '';

  @override
  void initState() {
    super.initState();
    _maybeAutofocus();
  }

  @override
  void didUpdateWidget(covariant _BlockField old) {
    super.didUpdateWidget(old);
    // Sync external (undo / replace-selection) text changes when unfocused.
    if (widget.block.text != _tc.text && !_fn.hasFocus) {
      _tc.text = widget.block.text;
    }
    _maybeAutofocus();
  }

  void _maybeAutofocus() {
    if (widget.controller.focusedId == widget.block.id && !_fn.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_fn.hasFocus) _fn.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _tc.dispose();
    _fn.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final c = widget.controller;
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      if (_slash.isNotEmpty) return KeyEventResult.ignored;
      c.insertBlockAfter(widget.block.id);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        _tc.text.isEmpty) {
      final blocks = c.blocks;
      final i = blocks.indexWhere((b) => b.id == widget.block.id);
      if (i > 0) {
        c.setFocused(blocks[i - 1].id);
        c.deleteBlock(widget.block.id);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _onChanged(String v) {
    final c = widget.controller;
    // Slash command menu.
    if (v.startsWith('/')) {
      setState(() => _slash = v.substring(1));
      c.updateText(widget.block.id, v);
      return;
    } else if (_slash.isNotEmpty) {
      setState(() => _slash = '');
    }
    // Markdown shortcuts (only from a plain paragraph, at line start).
    final t = _markdownType(v);
    if (t != null && widget.block.type == BlockType.paragraph) {
      final stripped = v.substring(t.$2);
      _tc.value = TextEditingValue(
        text: stripped,
        selection: TextSelection.collapsed(offset: stripped.length),
      );
      c.setType(widget.block.id, t.$1);
      c.updateText(widget.block.id, stripped);
      return;
    }
    c.updateText(widget.block.id, v);
  }

  /// Returns (type, prefixLength) if [v] starts with a markdown shortcut.
  (BlockType, int)? _markdownType(String v) {
    if (v.startsWith('### ')) return (BlockType.h3, 4);
    if (v.startsWith('## ')) return (BlockType.h2, 3);
    if (v.startsWith('# ')) return (BlockType.h1, 2);
    if (v.startsWith('- ') || v.startsWith('* ')) return (BlockType.bulleted, 2);
    if (v.startsWith('1. ')) return (BlockType.numbered, 3);
    if (v.startsWith('[] ')) return (BlockType.checklist, 3);
    if (v.startsWith('[ ] ')) return (BlockType.checklist, 4);
    if (v.startsWith('> ')) return (BlockType.quote, 2);
    return null;
  }

  TextStyle? _style(BuildContext context) {
    final t = Theme.of(context).textTheme;
    switch (widget.block.type) {
      case BlockType.h1:
        return t.headlineSmall?.copyWith(fontWeight: FontWeight.w700);
      case BlockType.h2:
        return t.titleLarge?.copyWith(fontWeight: FontWeight.w700);
      case BlockType.h3:
        return t.titleMedium?.copyWith(fontWeight: FontWeight.w700);
      case BlockType.quote:
        return t.bodyLarge?.copyWith(fontStyle: FontStyle.italic);
      case BlockType.formula:
        return t.bodyLarge?.copyWith(fontFeatures: const []);
      default:
        return t.bodyLarge;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final checked = widget.block.type == BlockType.checklist && widget.block.checked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _tc,
          focusNode: _fn,
          maxLines: null,
          onChanged: _onChanged,
          onTap: () {
            widget.controller.setFocused(widget.block.id);
            widget.controller.selectOnly(widget.block.id);
          },
          style: _style(context)?.copyWith(
            decoration: checked ? TextDecoration.lineThrough : null,
            color: checked ? scheme.onSurfaceVariant : null,
          ),
          cursorColor: scheme.primary,
          decoration: InputDecoration(
            isCollapsed: true,
            filled: false,
            border: InputBorder.none,
            hintText: widget.block.type.placeholder,
            hintStyle: TextStyle(color: scheme.onSurfaceVariant),
          ),
          contextMenuBuilder: _selectionMenu,
        ),
        if (_slash.isNotEmpty) _SlashMenu(query: _slash, onPick: _pickSlash),
      ],
    );
  }

  void _pickSlash(BlockType type) {
    _tc.clear();
    setState(() => _slash = '');
    widget.controller.setType(widget.block.id, type);
    widget.controller.updateText(widget.block.id, '');
  }

  Widget _selectionMenu(BuildContext context, EditableTextState state) {
    final value = state.textEditingValue;
    final sel = value.selection.textInside(value.text);
    final items = <ContextMenuButtonItem>[...state.contextMenuButtonItems];
    if (sel.trim().isNotEmpty) {
      for (final a in const [
        AiAction.explain,
        AiAction.expand,
        AiAction.simplify,
        AiAction.define,
        AiAction.research,
      ]) {
        items.add(ContextMenuButtonItem(
          label: a.label,
          onPressed: () {
            state.hideToolbar();
            widget.controller
                .requestSuggestion(widget.block.id, a, selectedText: sel);
          },
        ));
      }
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: items,
    );
  }
}

class _SlashMenu extends StatelessWidget {
  const _SlashMenu({required this.query, required this.onPick});
  final String query;
  final ValueChanged<BlockType> onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = query.toLowerCase();
    final matches = BlockType.values
        .where((t) => t.label.toLowerCase().contains(q))
        .take(6)
        .toList();
    if (matches.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: const BoxConstraints(maxWidth: 280),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(CockpitRadii.sm),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final t in matches)
            InkWell(
              onTap: () => onPick(t),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: CockpitSpacing.md, vertical: CockpitSpacing.sm),
                child: Row(
                  children: [
                    Icon(t.icon, size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: CockpitSpacing.md),
                    Text(t.label,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RichPlaceholder extends StatelessWidget {
  const _RichPlaceholder({required this.block});
  final TypedBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(block.type.icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: CockpitSpacing.md),
          Expanded(
            child: Text(
              block.text.isEmpty ? block.type.label : block.text,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          if (block.source != null) _MetaChip(
              icon: Icons.link_rounded, label: block.source!.chipLabel),
        ],
      ),
    );
  }
}

class _AiTag extends StatelessWidget {
  const _AiTag();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.sm, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 11, color: scheme.primary),
          const SizedBox(width: 3),
          Text('AI',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.primary, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.sm, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: scheme.onSurfaceVariant),
          const SizedBox(width: 3),
          Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _KeywordExpandChip extends StatelessWidget {
  const _KeywordExpandChip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: CockpitSpacing.md, vertical: CockpitSpacing.xs),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(CockpitRadii.pill),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded, size: 14, color: scheme.primary),
            const SizedBox(width: CockpitSpacing.xs),
            Text('Expand these keywords?',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: scheme.primary)),
          ],
        ),
      ),
    );
  }
}

/// A pending AI suggestion card. Distinct, tinted, non-mutating (spec §14).
class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.controller, required this.suggestion});
  final NotesController controller;
  final AiSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = suggestion;
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        border: Border(left: BorderSide(color: scheme.primary, width: 3)),
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
              const SizedBox(width: CockpitSpacing.sm),
              Flexible(
                child: Text(s.contextLabel,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.md),
          Text(s.body, style: theme.textTheme.bodyLarge),
          if (s.sources.isNotEmpty) ...[
            const SizedBox(height: CockpitSpacing.sm),
            Wrap(
              spacing: CockpitSpacing.xs,
              children: [
                for (final src in s.sources)
                  _MetaChip(icon: Icons.link_rounded, label: src.chipLabel),
              ],
            ),
          ],
          const SizedBox(height: CockpitSpacing.lg),
          Wrap(
            spacing: CockpitSpacing.sm,
            runSpacing: CockpitSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                onPressed: () => controller.approveInsertBelow(s),
                child: const Text('Insert Below'),
              ),
              OutlinedButton(
                onPressed: () => controller.approveAddAsExplanation(s),
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: scheme.outline)),
                child: const Text('Add as Explanation'),
              ),
              OutlinedButton(
                onPressed: () => controller.approveReplaceSelection(s),
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: scheme.outline)),
                child: const Text('Replace Selection'),
              ),
              TextButton.icon(
                onPressed: () => controller.dismissSuggestion(s.id),
                style: TextButton.styleFrom(
                    foregroundColor: scheme.onSurfaceVariant),
                icon: const Icon(Icons.cancel_outlined, size: 16),
                label: const Text('Dismiss'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MagicBar extends StatelessWidget {
  const _MagicBar({required this.controller});
  final NotesController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ctx = controller.selectedCount > 1
        ? '${controller.selectedCount} blocks'
        : controller.focusedId != null
            ? 'current block'
            : 'whole note';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: CockpitSpacing.md, vertical: CockpitSpacing.md),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(CockpitRadii.md),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: CockpitSpacing.md),
              Expanded(
                child: Text('Ask OctoNotes or type a command…',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: CockpitSpacing.sm, vertical: CockpitSpacing.xxs),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(CockpitRadii.sm),
                ),
                child: Text('⌘ K', style: theme.textTheme.labelMedium),
              ),
              const SizedBox(width: CockpitSpacing.sm),
              Icon(Icons.send_rounded, size: 18, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: CockpitSpacing.xs, left: 4),
          child: Text('Context to send: $ctx',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}

class _MultiSelectBar extends StatelessWidget {
  const _MultiSelectBar({required this.controller});
  final NotesController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      color: scheme.primary.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.lg, vertical: CockpitSpacing.sm),
      child: Row(
        children: [
          Text('${controller.selectedCount} blocks selected',
              style: theme.textTheme.labelLarge),
          const Spacer(),
          TextButton.icon(
            onPressed: () {
              for (final id in controller.selected.toList()) {
                controller.toggleStudyStudioSelection(id);
              }
            },
            icon: const Icon(Icons.school_rounded, size: 16),
            label: const Text('Add to Study Studio'),
          ),
          TextButton.icon(
            onPressed: controller.clearSelection,
            icon: const Icon(Icons.close_rounded, size: 16),
            label: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _EmptyCanvas extends StatelessWidget {
  const _EmptyCanvas({required this.controller});
  final NotesController controller;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.edit_note_rounded,
      title: 'Start your note',
      message: "Type '/' for commands, or use the toolbar to add a block.",
      action: FilledButton.icon(
        onPressed: () => controller.addBlockAtEnd(),
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Add first block'),
      ),
    );
  }
}

// ===========================================================================
// Status footer (autosave / sync / offline / study studio)
// ===========================================================================
class _StatusFooter extends StatelessWidget {
  const _StatusFooter({required this.controller});
  final NotesController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sync = controller.sync;

    Color color;
    IconData icon;
    switch (sync) {
      case SyncState.saved:
      case SyncState.synced:
        color = CockpitColors.brand.success;
        icon = Icons.check_circle_rounded;
      case SyncState.saving:
        color = scheme.onSurfaceVariant;
        icon = Icons.sync_rounded;
      case SyncState.offline:
        color = CockpitColors.brand.warning;
        icon = Icons.cloud_off_rounded;
      case SyncState.reconnecting:
        color = CockpitColors.brand.info;
        icon = Icons.sync_rounded;
      case SyncState.conflict:
        color = scheme.primary;
        icon = Icons.error_outline_rounded;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.xl, vertical: CockpitSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: CockpitSpacing.sm),
          Text(sync.label,
              style: theme.textTheme.bodySmall?.copyWith(color: color)),
          if (sync == SyncState.conflict) ...[
            const SizedBox(width: CockpitSpacing.sm),
            TextButton(
              onPressed: controller.resolveConflictKeepBoth,
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                      horizontal: CockpitSpacing.sm)),
              child: const Text('Keep both'),
            ),
          ],
          const SizedBox(width: CockpitSpacing.md),
          Text('Block-level autosave',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const Spacer(),
          if (controller.studyStudioCount > 0) ...[
            Icon(Icons.school_rounded, size: 14, color: scheme.tertiary),
            const SizedBox(width: CockpitSpacing.xs),
            Text('${controller.studyStudioCount} for Study Studio',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(width: CockpitSpacing.md),
          ],
          // Offline toggle to demonstrate the offline / reconnect states.
          TextButton.icon(
            onPressed: controller.offline
                ? controller.reconnect
                : controller.goOffline,
            style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: scheme.onSurfaceVariant),
            icon: Icon(
                controller.offline
                    ? Icons.wifi_off_rounded
                    : Icons.wifi_rounded,
                size: 16),
            label: Text(controller.offline ? 'Reconnect' : 'Go offline'),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Right rail + slide-out panel
// ===========================================================================
class _RightRail extends StatelessWidget {
  const _RightRail({
    required this.controller,
    required this.selected,
    required this.onSelect,
  });
  final NotesController controller;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, int)>[
      (Icons.menu_book_rounded, 'Materials', 0),
      (Icons.auto_awesome_rounded, 'AI', controller.suggestions.length),
      (Icons.search_rounded, 'Research', 0),
      (Icons.folder_open_rounded, 'Organize', controller.organizationChangesReady),
    ];
    return Container(
      width: 84,
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.lg),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _RailItem(
              icon: items[i].$1,
              label: items[i].$2,
              badge: items[i].$3,
              selected: selected == i,
              onTap: () => onSelect(i),
            ),
            const SizedBox(height: CockpitSpacing.lg),
          ],
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.label,
    required this.badge,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final int badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(CockpitRadii.md),
      onTap: onTap,
      child: Container(
        width: 60,
        padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.sm),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(CockpitRadii.md),
        ),
        child: Column(
          children: [
            Badge(
              isLabelVisible: badge > 0,
              label: Text('$badge'),
              backgroundColor: scheme.primary,
              child: Icon(icon, size: 22, color: color),
            ),
            const SizedBox(height: CockpitSpacing.xs),
            Text(label,
                style: theme.textTheme.labelSmall?.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Collapsed transcript bar (docked one-liner; expands to Panel 7)
// ===========================================================================
class _CollapsedTranscriptBar extends StatelessWidget {
  const _CollapsedTranscriptBar({
    required this.controller,
    required this.onExpand,
  });
  final TranscriptController controller;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final latest = controller.segments.isNotEmpty
            ? controller.segments.last
            : null;
        return InkWell(
          onTap: onExpand,
          child: Container(
            color: scheme.surfaceContainerLowest,
            padding: const EdgeInsets.fromLTRB(CockpitSpacing.lg,
                CockpitSpacing.sm, CockpitSpacing.lg, CockpitSpacing.sm),
            child: Row(
              children: [
                Icon(Icons.keyboard_arrow_up_rounded,
                    color: scheme.onSurfaceVariant),
                const SizedBox(width: CockpitSpacing.xs),
                Text('Live Transcript', style: theme.textTheme.titleSmall),
                const SizedBox(width: CockpitSpacing.md),
                Icon(Icons.circle, size: 7, color: scheme.primary),
                const SizedBox(width: CockpitSpacing.xs),
                Text('${controller.delaySeconds}s behind',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                if (latest != null) ...[
                  const SizedBox(width: CockpitSpacing.md),
                  Text('${latest.start} · ',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  Expanded(
                    child: Text(latest.displayText,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                ] else
                  const Spacer(),
                const SizedBox(width: CockpitSpacing.md),
                Icon(Icons.sensors_rounded,
                    size: 14, color: CockpitColors.brand.success),
                const SizedBox(width: CockpitSpacing.xs),
                Text('Following Live',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        );
      },
    );
  }
}
