import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../application/ink_sync.dart';
import '../../data/api/notes_api_client.dart';
import '../../domain/ink_controller.dart';
import '../../domain/ink_models.dart';
import '../../domain/notes_controller.dart';

/// Panel 6 — Magic Pencil Canvas. A real vector-ink surface: draw, highlight,
/// erase, lasso-select, add shapes/text across multiple pages; a separate
/// recognition + AI layer never touches the original ink (spec §3).
class MagicPencilWorkspace extends StatelessWidget {
  const MagicPencilWorkspace({
    super.key,
    required this.ink,
    required this.notes,
    required this.workspaceToggle,
    required this.onSwitchToTypewriter,
  });

  final InkController ink;
  final NotesController notes;
  final Widget workspaceToggle;
  final VoidCallback onSwitchToTypewriter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= 1000;
    // A phone: the toolbar scrolls sideways and the page rail is left out.
    final phone = width < 600;
    return AnimatedBuilder(
      animation: ink,
      builder: (context, _) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(CockpitSpacing.md),
              child: Center(child: workspaceToggle),
            ),
            _PencilToolbar(ink: ink, compact: phone),
            Divider(height: 1, color: scheme.outlineVariant),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!phone) ...[
                    _PageRail(ink: ink),
                    VerticalDivider(width: 1, color: scheme.outlineVariant),
                  ],
                  Expanded(
                    child: _InkCanvas(
                      ink: ink,
                      notes: notes,
                      onSwitchToTypewriter: onSwitchToTypewriter,
                    ),
                  ),
                  if (desktop) ...[
                    VerticalDivider(width: 1, color: scheme.outlineVariant),
                    SizedBox(
                      width: 300,
                      child: _RecognitionPanel(
                        ink: ink,
                        notes: notes,
                        onSwitchToTypewriter: onSwitchToTypewriter,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ===========================================================================
// Toolbar
// ===========================================================================
class _PencilToolbar extends StatelessWidget {
  const _PencilToolbar({required this.ink, this.compact = false});
  final InkController ink;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget tool(InkTool t) {
      final selected = ink.tool == t;
      return IconButton(
        visualDensity: VisualDensity.compact,
        isSelected: selected,
        onPressed: () => ink.setTool(t),
        style: IconButton.styleFrom(
          backgroundColor:
              selected ? scheme.primary.withValues(alpha: 0.14) : null,
          foregroundColor: selected ? scheme.primary : scheme.onSurfaceVariant,
        ),
        icon: Icon(t.icon, size: 20),
      );
    }

    Widget sep() => Container(
          width: 1,
          height: 20,
          margin: const EdgeInsets.symmetric(horizontal: CockpitSpacing.xs),
          color: scheme.outlineVariant,
        );

    final row = Row(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          tool(InkTool.pen),
          tool(InkTool.pencil),
          tool(InkTool.highlighter),
          tool(InkTool.eraser),
          tool(InkTool.lasso),
          sep(),
          tool(InkTool.rect),
          tool(InkTool.circle),
          tool(InkTool.text),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () {},
            icon: Icon(Icons.image_outlined,
                size: 20, color: scheme.onSurfaceVariant),
          ),
          tool(InkTool.line),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () {},
            icon: Icon(Icons.functions_rounded,
                size: 20, color: scheme.onSurfaceVariant),
          ),
          sep(),
          _ColorButton(ink: ink),
          _WidthButton(ink: ink),
          sep(),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: ink.canUndo ? ink.undo : null,
            icon: Icon(Icons.undo_rounded,
                size: 20,
                color: ink.canUndo ? scheme.onSurfaceVariant : scheme.outlineVariant),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: ink.canRedo ? ink.redo : null,
            icon: Icon(Icons.redo_rounded,
                size: 20,
                color: ink.canRedo ? scheme.onSurfaceVariant : scheme.outlineVariant),
          ),
          if (compact) const SizedBox(width: CockpitSpacing.md) else const Spacer(),
          OutlinedButton.icon(
            onPressed: ink.addPage,
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              side: BorderSide(color: scheme.outlineVariant),
            ),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Add Page'),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          _PageMenu(ink: ink),
        ],
      );
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.md, vertical: CockpitSpacing.xs),
      child: compact ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: row) : row,
    );
  }
}

class _ColorButton extends StatelessWidget {
  const _ColorButton({required this.ink});
  final InkController ink;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<Color>(
      tooltip: 'Color',
      onSelected: ink.setColor,
      itemBuilder: (context) => [
        for (final c in InkController.palette)
          PopupMenuItem(
            value: c,
            height: 40,
            child: Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                ),
                const SizedBox(width: CockpitSpacing.md),
                Text(_name(c)),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(CockpitSpacing.sm),
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: ink.color,
            shape: BoxShape.circle,
            border: Border.all(color: scheme.outlineVariant),
          ),
        ),
      ),
    );
  }

  static String _name(Color c) {
    if (c == InkController.palette[0]) return 'Ink';
    if (c == InkController.palette[1]) return 'Blue';
    if (c == InkController.palette[2]) return 'Red';
    if (c == InkController.palette[3]) return 'Green';
    return 'Gold';
  }
}

class _WidthButton extends StatelessWidget {
  const _WidthButton({required this.ink});
  final InkController ink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<double>(
      tooltip: 'Stroke width',
      onSelected: ink.setWidth,
      itemBuilder: (context) => [
        for (final w in InkController.widths)
          PopupMenuItem(value: w, height: 40, child: Text('${w.toInt()} px')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: CockpitSpacing.sm, vertical: CockpitSpacing.xs),
        child: Row(
          children: [
            Text('${ink.width.toInt()}', style: theme.textTheme.labelLarge),
            const Icon(Icons.arrow_drop_down_rounded),
          ],
        ),
      ),
    );
  }
}

class _PageMenu extends StatelessWidget {
  const _PageMenu({required this.ink});
  final InkController ink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PopupMenuButton<String>(
      tooltip: 'Pages & background',
      onSelected: (v) {
        if (v.startsWith('bg:')) {
          ink.setBackground(PaperBackground.values.byName(v.substring(3)));
        } else if (v.startsWith('pg:')) {
          ink.setPage(int.parse(v.substring(3)));
        }
      },
      itemBuilder: (context) => [
        for (var i = 0; i < ink.pageCount; i++)
          PopupMenuItem(value: 'pg:$i', height: 38, child: Text('Page ${i + 1}')),
        const PopupMenuDivider(),
        for (final bg in PaperBackground.values)
          PopupMenuItem(
            value: 'bg:${bg.name}',
            height: 38,
            child: Row(
              children: [
                Icon(
                    ink.page.background == bg
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 16),
                const SizedBox(width: CockpitSpacing.sm),
                Text(bg.label),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: CockpitSpacing.md, vertical: CockpitSpacing.xs),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(CockpitRadii.sm),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Text('Page ${ink.pageIndex + 1} of ${ink.pageCount}',
                style: theme.textTheme.labelLarge),
            const Icon(Icons.arrow_drop_down_rounded),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Page rail (thumbnails)
// ===========================================================================
class _PageRail extends StatelessWidget {
  const _PageRail({required this.ink});
  final InkController ink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: 116,
      color: scheme.surface,
      child: ListView.builder(
        padding: const EdgeInsets.all(CockpitSpacing.sm),
        itemCount: ink.pageCount,
        itemBuilder: (context, i) {
          final selected = i == ink.pageIndex;
          final p = ink.pages[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: CockpitSpacing.md),
            child: Column(
              children: [
                InkWell(
                  onTap: () => ink.setPage(i),
                  child: Container(
                    height: 92,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(CockpitRadii.sm),
                      border: Border.all(
                        color: selected ? scheme.primary : scheme.outlineVariant,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: CustomPaint(
                      painter: _ThumbPainter(p),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                const SizedBox(height: CockpitSpacing.xs),
                Text('${i + 1}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: selected ? scheme.primary : scheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w700 : null,
                    )),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.page);
  final InkPage page;

  @override
  void paint(Canvas canvas, Size size) {
    // Assume a ~1000px logical page width; scale to the thumbnail.
    final scale = size.width / 1000;
    canvas.scale(scale);
    for (final s in page.strokes) {
      _paintStroke(canvas, s, thumbnail: true);
    }
  }

  @override
  bool shouldRepaint(covariant _ThumbPainter old) => true;
}

// ===========================================================================
// Canvas
// ===========================================================================
class _InkCanvas extends StatefulWidget {
  const _InkCanvas({
    required this.ink,
    required this.notes,
    required this.onSwitchToTypewriter,
    this.onFormula,
  });
  final InkController ink;

  /// Reads the selection as a formula (a saved page only).
  final ValueChanged<List<Stroke>>? onFormula;
  final NotesController notes;
  final VoidCallback onSwitchToTypewriter;

  @override
  State<_InkCanvas> createState() => _InkCanvasState();
}

class _InkCanvasState extends State<_InkCanvas> {
  // The finger that draws; a second finger means a pinch, not a stroke.
  final Set<int> _fingers = {};
  int? _drawer;
  List<Offset> _current = [];
  List<double> _pressures = [];
  List<Offset> _lasso = [];
  Offset? _shapeStart;
  Offset? _moveAnchor;

  InkController get ink => widget.ink;

  double _pressure(double raw) => raw <= 0 ? 1.0 : raw.clamp(0.1, 1.0);

  void _pointerDown(PointerDownEvent e) {
    _fingers.add(e.pointer);
    if (_fingers.length > 1) {
      // Pinch: drop the stroke the first finger began.
      _drawer = null;
      setState(() {
        _current = [];
        _pressures = [];
        _lasso = [];
        _shapeStart = null;
      });
      return;
    }
    _drawer = e.pointer;
    _down(e);
  }

  void _pointerMove(PointerMoveEvent e) {
    if (e.pointer == _drawer) _move(e);
  }

  void _pointerUp(PointerUpEvent e) {
    _fingers.remove(e.pointer);
    if (e.pointer != _drawer) return;
    _drawer = null;
    _up(e);
  }

  void _pointerCancel(PointerCancelEvent e) {
    _fingers.remove(e.pointer);
    if (e.pointer != _drawer) return;
    _drawer = null;
    setState(() {
      _current = [];
      _pressures = [];
      _lasso = [];
      _shapeStart = null;
    });
  }

  void _down(PointerDownEvent e) {
    final p = e.localPosition;
    final pr = _pressure(e.pressure);
    switch (ink.tool) {
      case InkTool.pen:
      case InkTool.pencil:
      case InkTool.highlighter:
        ink.beginEdit();
        setState(() {
          _current = [p];
          _pressures = [pr];
        });
      case InkTool.eraser:
        ink.beginEdit();
        ink.eraseAt(p);
      case InkTool.lasso:
        setState(() => _lasso = [p]);
      case InkTool.rect:
      case InkTool.circle:
      case InkTool.line:
        ink.beginEdit();
        setState(() {
          _shapeStart = p;
          _current = [p, p];
        });
      case InkTool.text:
        _addText(p);
      case InkTool.pointer:
        final b = ink.selectionBounds;
        if (b != null && b.contains(p)) {
          _moveAnchor = p;
        } else {
          ink.clearSelection();
        }
    }
  }

  void _move(PointerMoveEvent e) {
    final p = e.localPosition;
    final pr = _pressure(e.pressure);
    switch (ink.tool) {
      case InkTool.pen:
      case InkTool.pencil:
      case InkTool.highlighter:
        setState(() {
          _current.add(p);
          _pressures.add(pr);
        });
      case InkTool.eraser:
        ink.eraseAt(p);
      case InkTool.lasso:
        setState(() => _lasso.add(p));
      case InkTool.rect:
      case InkTool.circle:
      case InkTool.line:
        setState(() => _current = [_shapeStart!, p]);
      case InkTool.pointer:
        if (_moveAnchor != null) {
          ink.moveSelection(p - _moveAnchor!);
          _moveAnchor = p;
        }
      case InkTool.text:
        break;
    }
  }

  void _up(PointerUpEvent e) {
    switch (ink.tool) {
      case InkTool.pen:
      case InkTool.pencil:
      case InkTool.highlighter:
        if (_current.length > 1) {
          ink.addStroke(_stroke(_current, _pressures, ink.tool));
        }
        setState(() {
          _current = [];
          _pressures = [];
        });
      case InkTool.rect:
      case InkTool.circle:
      case InkTool.line:
        if (_shapeStart != null && _current.length == 2) {
          ink.addStroke(_stroke(_current, const [1, 1], ink.tool));
        }
        setState(() {
          _shapeStart = null;
          _current = [];
        });
      case InkTool.lasso:
        ink.applyLasso(_lasso);
        if (ink.hasSelection) HapticFeedback.mediumImpact();
        setState(() => _lasso = []);
      case InkTool.pointer:
        _moveAnchor = null;
      case InkTool.eraser:
      case InkTool.text:
        break;
    }
  }

  Stroke _stroke(List<Offset> pts, List<double> pr, InkTool t) => Stroke(
        id: ink.newStrokeId(),
        tool: t,
        points: List.of(pts),
        pressures: List.of(pr),
        color: ink.color,
        width: ink.width,
        pageId: ink.page.id,
        audioTimestamp: ink.nextAudioTime(),
      );

  Future<void> _addText(Offset at) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Text box'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Type text…'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Add')),
        ],
      ),
    );
    if (text != null && text.trim().isNotEmpty) ink.addText(at, text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sel = ink.selectionBounds;
    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _pointerDown,
              onPointerMove: _pointerMove,
              onPointerUp: _pointerUp,
              onPointerCancel: _pointerCancel,
              child: MouseRegion(
                cursor: ink.tool == InkTool.pointer
                    ? SystemMouseCursors.grab
                    : SystemMouseCursors.precise,
                child: CustomPaint(
                  painter: _InkPainter(
                    page: ink.page,
                    current: _current,
                    currentTool: ink.tool,
                    currentColor: ink.color,
                    currentWidth: ink.width,
                    lasso: _lasso,
                    selectionBounds: sel,
                    selectedIds: ink.selected,
                    surface: scheme.surfaceContainerLowest,
                    grid: scheme.outlineVariant,
                    accent: scheme.primary,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          // Lasso context menu + source chips (spec §8).
          if (sel != null && ink.live)
            Positioned(
              left: sel.left.clamp(0, 10000),
              top: (sel.top - 52).clamp(0, 10000),
              child: _LiveLassoMenu(ink: ink, onFormula: widget.onFormula),
            ),
          if (sel != null && !ink.live) ...[
            Positioned(
              left: sel.left.clamp(0, 10000),
              top: (sel.top - 52).clamp(0, 10000),
              child: _LassoMenu(
                ink: ink,
                notes: widget.notes,
                onSwitchToTypewriter: widget.onSwitchToTypewriter,
              ),
            ),
            Positioned(
              left: (sel.right + 8).clamp(0, 10000),
              top: sel.top.clamp(0, 10000),
              child: const _SelectionChips(),
            ),
          ],
          // "Original Ink Preserved" (spec §3).
          if (!ink.live)
          Positioned(
            left: CockpitSpacing.md,
            bottom: CockpitSpacing.md,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: CockpitSpacing.md, vertical: CockpitSpacing.sm),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(CockpitRadii.pill),
                border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_user_rounded,
                      size: 16, color: CockpitColors.brand.success),
                  const SizedBox(width: CockpitSpacing.sm),
                  Text('Original Ink Preserved',
                      style: Theme.of(context).textTheme.labelMedium),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The lasso on a saved page: what's real for a selection.
class _LiveLassoMenu extends StatelessWidget {
  const _LiveLassoMenu({required this.ink, this.onFormula});
  final InkController ink;
  final ValueChanged<List<Stroke>>? onFormula;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget action(IconData icon, String tip, VoidCallback onTap) => IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          icon: Icon(icon, size: 19),
          onPressed: () {
            HapticFeedback.selectionClick();
            onTap();
          },
        );
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
      color: scheme.surface,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onFormula != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: TextButton.icon(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  onFormula!(ink.selectedStrokes);
                },
                icon: const Icon(Icons.functions_rounded, size: 18),
                label: const Text('Read as formula'),
              ),
            ),
          action(Icons.copy_rounded, 'Duplicate', ink.duplicateSelection),
          action(Icons.delete_outline_rounded, 'Delete', ink.deleteSelection),
          action(Icons.close_rounded, 'Done', ink.clearSelection),
        ],
      ),
    );
  }
}

class _LassoMenu extends StatelessWidget {
  const _LassoMenu({
    required this.ink,
    required this.notes,
    required this.onSwitchToTypewriter,
  });
  final InkController ink;
  final NotesController notes;
  final VoidCallback onSwitchToTypewriter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget action(IconData icon, String label, VoidCallback onTap) => InkWell(
          borderRadius: BorderRadius.circular(CockpitRadii.sm),
          onTap: onTap,
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
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(CockpitRadii.md),
      color: scheme.surface,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(CockpitRadii.md),
          border: Border.all(color: scheme.outlineVariant),
        ),
        padding: const EdgeInsets.all(CockpitSpacing.xxs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            action(Icons.lightbulb_outline_rounded, 'Explain',
                ink.requestAiExplain),
            action(Icons.open_in_full_rounded, 'Expand', ink.requestAiExplain),
            action(Icons.text_fields_rounded, 'Convert to Text', () {
              final text = ink.convertSelectionToText();
              notes.addConvertedFromInk(text,
                  backlink: 'Page ${ink.pageIndex + 1} · 18:32');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  content: Text('Converted "$text" → Typewriter'),
                ),
              );
            }),
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: Icon(Icons.more_vert_rounded,
                  size: 18, color: scheme.onSurfaceVariant),
              onSelected: (v) {
                switch (v) {
                  case 'duplicate':
                    ink.duplicateSelection();
                  case 'delete':
                    ink.deleteSelection();
                  case 'study':
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        behavior: SnackBarBehavior.floating,
                        content: Text('Added to Study Studio selection'),
                      ),
                    );
                  case 'timestamp':
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        behavior: SnackBarBehavior.floating,
                        content: Text('Linked to transcript 18:32'),
                      ),
                    );
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                PopupMenuItem(value: 'timestamp', child: Text('Link Timestamp')),
                PopupMenuItem(
                    value: 'study', child: Text('Add to Study Studio')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionChips extends StatelessWidget {
  const _SelectionChips();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget chip(Widget child, Color border) => Container(
          margin: const EdgeInsets.only(bottom: CockpitSpacing.xs),
          padding: const EdgeInsets.symmetric(
              horizontal: CockpitSpacing.sm, vertical: 2),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(CockpitRadii.sm),
            border: Border.all(color: border),
          ),
          child: child,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        chip(
          Text('18:32',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700)),
          scheme.primary.withValues(alpha: 0.4),
        ),
        chip(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.link_rounded, size: 12, color: scheme.onSurfaceVariant),
              const SizedBox(width: 3),
              Text('Week 4 Slides · Slide 7',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
          scheme.outlineVariant,
        ),
      ],
    );
  }
}

// ===========================================================================
// Painter
// ===========================================================================
class _InkPainter extends CustomPainter {
  _InkPainter({
    required this.page,
    required this.current,
    required this.currentTool,
    required this.currentColor,
    required this.currentWidth,
    required this.lasso,
    required this.selectionBounds,
    required this.selectedIds,
    required this.surface,
    required this.grid,
    required this.accent,
  });

  final InkPage page;
  final List<Offset> current;
  final InkTool currentTool;
  final Color currentColor;
  final double currentWidth;
  final List<Offset> lasso;
  final Rect? selectionBounds;
  final Set<String> selectedIds;
  final Color surface;
  final Color grid;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = surface);
    _paintBackground(canvas, size);

    for (final s in page.strokes) {
      _paintStroke(canvas, s);
      if (selectedIds.contains(s.id)) {
        canvas.drawRect(
          s.bounds,
          Paint()
            ..color = accent.withValues(alpha: 0.06)
            ..style = PaintingStyle.fill,
        );
      }
    }

    if (current.isNotEmpty) {
      _paintStroke(
        canvas,
        Stroke(
          id: '_cur',
          tool: currentTool,
          points: current,
          pressures: const [],
          color: currentColor,
          width: currentWidth,
          pageId: page.id,
        ),
      );
    }

    if (lasso.length > 1) {
      _paintDashedPath(canvas, lasso, accent);
    }

    if (selectionBounds != null) {
      _paintDashedRect(canvas, selectionBounds!, accent);
    }
  }

  void _paintBackground(Canvas canvas, Size size) {
    final dot = Paint()..color = grid;
    switch (page.background) {
      case PaperBackground.blank:
        break;
      case PaperBackground.dotted:
        for (double y = 24; y < size.height; y += 24) {
          for (double x = 24; x < size.width; x += 24) {
            canvas.drawCircle(Offset(x, y), 1, dot);
          }
        }
      case PaperBackground.grid:
        final p = Paint()
          ..color = grid
          ..strokeWidth = 0.5;
        for (double x = 24; x < size.width; x += 24) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
        }
        for (double y = 24; y < size.height; y += 24) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
      case PaperBackground.lined:
        final p = Paint()
          ..color = grid
          ..strokeWidth = 0.5;
        for (double y = 40; y < size.height; y += 32) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
    }
  }

  @override
  bool shouldRepaint(covariant _InkPainter old) => true;
}

/// Shared stroke rendering (used by canvas + thumbnails).
void _paintStroke(Canvas canvas, Stroke s, {bool thumbnail = false}) {
  if (s.tool == InkTool.text) {
    final tp = TextPainter(
      text: TextSpan(
        text: s.text ?? '',
        style: TextStyle(
          color: s.color,
          fontSize: thumbnail ? 22 : 22,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 900);
    tp.paint(canvas, s.points.isNotEmpty ? s.points.first : Offset.zero);
    return;
  }

  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  switch (s.tool) {
    case InkTool.highlighter:
      paint
        ..color = s.color.withValues(alpha: 0.30)
        ..strokeWidth = s.width * 5
        ..blendMode = BlendMode.multiply;
    case InkTool.pencil:
      paint
        ..color = s.color.withValues(alpha: 0.8)
        ..strokeWidth = s.width * 0.9;
    default:
      paint
        ..color = s.color
        ..strokeWidth = s.width * 1.2;
  }

  if (s.tool == InkTool.rect && s.points.length == 2) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromPoints(s.points[0], s.points[1]), const Radius.circular(6)),
      paint,
    );
    return;
  }
  if (s.tool == InkTool.circle && s.points.length == 2) {
    canvas.drawOval(Rect.fromPoints(s.points[0], s.points[1]), paint);
    return;
  }
  if (s.tool == InkTool.line && s.points.length == 2) {
    canvas.drawLine(s.points[0], s.points[1], paint);
    return;
  }

  if (s.points.length < 2) {
    if (s.points.isNotEmpty) {
      canvas.drawPoints(PointMode.points, s.points,
          paint..strokeCap = StrokeCap.round);
    }
    return;
  }
  final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
  for (var i = 1; i < s.points.length; i++) {
    final prev = s.points[i - 1];
    final cur = s.points[i];
    final mid = Offset((prev.dx + cur.dx) / 2, (prev.dy + cur.dy) / 2);
    path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
  }
  canvas.drawPath(path, paint);
}

void _paintDashedPath(Canvas canvas, List<Offset> pts, Color color) {
  final paint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  for (var i = 1; i < pts.length; i++) {
    if (i.isEven) canvas.drawLine(pts[i - 1], pts[i], paint);
  }
}

void _paintDashedRect(Canvas canvas, Rect r, Color color) {
  final paint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  const dash = 6.0, gap = 4.0;
  void edge(Offset a, Offset b) {
    final total = (b - a).distance;
    final dir = (b - a) / total;
    double d = 0;
    while (d < total) {
      final s = a + dir * d;
      final e = a + dir * math.min(d + dash, total);
      canvas.drawLine(s, e, paint);
      d += dash + gap;
    }
  }

  edge(r.topLeft, r.topRight);
  edge(r.topRight, r.bottomRight);
  edge(r.bottomRight, r.bottomLeft);
  edge(r.bottomLeft, r.topLeft);
}

// ===========================================================================
// Recognition / AI panel (separate layer)
// ===========================================================================
class _RecognitionPanel extends StatefulWidget {
  const _RecognitionPanel({
    required this.ink,
    required this.notes,
    required this.onSwitchToTypewriter,
  });
  final InkController ink;
  final NotesController notes;
  final VoidCallback onSwitchToTypewriter;

  @override
  State<_RecognitionPanel> createState() => _RecognitionPanelState();
}

class _RecognitionPanelState extends State<_RecognitionPanel> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 0; i < 2; i++)
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _tab = i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: CockpitSpacing.md),
                    child: Column(
                      children: [
                        Text(i == 0 ? 'Recognition' : 'AI',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: _tab == i
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                              fontWeight: _tab == i
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            )),
                        const SizedBox(height: CockpitSpacing.xs),
                        Container(
                          height: 2,
                          color:
                              _tab == i ? scheme.primary : Colors.transparent,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(CockpitSpacing.lg),
            children: [
              if (_tab == 0) _recognitionBody(context) else _aiBody(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _recognitionBody(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ink = widget.ink;
    final r = ink.recognition;

    if (r == null) {
      return const EmptyState(
        icon: Icons.draw_rounded,
        title: 'Ink Recognition',
        message: 'Lasso-select handwriting to recognize it. Your ink is never '
            'changed.',
      );
    }
    final confColor = r.isHigh
        ? CockpitColors.brand.success
        : r.isMedium
            ? CockpitColors.brand.warning
            : scheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.draw_rounded, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: CockpitSpacing.sm),
            Text('Ink Recognition', style: theme.textTheme.titleSmall),
          ],
        ),
        const SizedBox(height: CockpitSpacing.md),
        if (!ink.recognitionComplete)
          Row(
            children: [
              const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: CockpitSpacing.sm),
              Text('Recognizing…',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          )
        else ...[
          Text.rich(TextSpan(children: [
            TextSpan(
                text: 'Recognized: ',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            TextSpan(
                text: r.text,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ])),
          const SizedBox(height: CockpitSpacing.xs),
          Text('${(r.confidence * 100).round()}% confidence',
              style: theme.textTheme.labelMedium?.copyWith(color: confColor)),
          const SizedBox(height: CockpitSpacing.lg),
          Row(
            children: [
              FilledButton(
                onPressed: ink.confirmRecognition,
                child: const Text('Confirm'),
              ),
              const SizedBox(width: CockpitSpacing.sm),
              OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: scheme.outline)),
                child: const Text('Correct'),
              ),
            ],
          ),
        ],
        if (ink.aiExplanation != null) ...[
          const SizedBox(height: CockpitSpacing.xl),
          _aiExplanationCard(context),
        ],
      ],
    );
  }

  Widget _aiBody(BuildContext context) {
    final ink = widget.ink;
    if (ink.aiExplanation == null) {
      return EmptyState(
        icon: Icons.auto_awesome_rounded,
        title: 'AI Explanation',
        message: 'Lasso-select ink, then Explain or Expand.',
        action: ink.hasSelection
            ? FilledButton(
                onPressed: ink.requestAiExplain,
                child: const Text('Explain selection'),
              )
            : null,
      );
    }
    return _aiExplanationCard(context);
  }

  Widget _aiExplanationCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ink = widget.ink;
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 16, color: scheme.primary),
              const SizedBox(width: CockpitSpacing.sm),
              Text('AI Explanation',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: scheme.primary)),
            ],
          ),
          const SizedBox(height: CockpitSpacing.xs),
          Text('Based on nearby ink, transcript, and Slide 7',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: CockpitSpacing.md),
          Text(ink.aiExplanation!, style: theme.textTheme.bodyMedium),
          const SizedBox(height: CockpitSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                widget.notes.addConvertedFromInk(ink.aiExplanation!,
                    backlink: 'Page ${ink.pageIndex + 1} · 18:32');
                ink.dismissAi();
                _snack(context, 'Added as typed note');
              },
              child: const Text('Add as Typed Note'),
            ),
          ),
          const SizedBox(height: CockpitSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                widget.notes.addConvertedFromInk(ink.aiExplanation!,
                    backlink: 'Page ${ink.pageIndex + 1} · 18:32');
                ink.dismissAi();
                widget.onSwitchToTypewriter();
              },
              child: const Text('Send to Typewriter'),
            ),
          ),
          const SizedBox(height: CockpitSpacing.sm),
          TextButton.icon(
            onPressed: ink.dismissAi,
            style: TextButton.styleFrom(
                foregroundColor: scheme.onSurfaceVariant),
            icon: const Icon(Icons.cancel_outlined, size: 16),
            label: const Text('Dismiss'),
          ),
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

// ===========================================================================
// Phone, landscape: tools down the left, colours down the right, the page
// in between (edge to edge, system bars hidden).
// ===========================================================================

/// Magic Pencil for a phone held sideways. [top] floats over the page (who
/// records, the live transcript line).
class PhoneMagicPencil extends StatefulWidget {
  const PhoneMagicPencil({
    super.key,
    required this.ink,
    required this.notes,
    required this.onClose,
    this.top,
    this.sync,
  });

  final InkController ink;

  /// Saves the pages and reads each line; null without a server.
  final InkSync? sync;
  final NotesController notes;
  final VoidCallback onClose;
  final Widget? top;

  @override
  State<PhoneMagicPencil> createState() => _PhoneMagicPencilState();
}

class _PhoneMagicPencilState extends State<PhoneMagicPencil> {
  InkController get ink => widget.ink;
  final _zoom = TransformationController();
  int _fingers = 0;
  bool _notesOpen = false;
  int _lineCount = 0;

  void _synced() {
    final n = widget.sync == null ? 0 : widget.sync!.linesOf(ink.page).length;
    // A new line read: a light tap, and the tab's count bumps.
    if (n > _lineCount) HapticFeedback.lightImpact();
    if (mounted) setState(() => _lineCount = n);
  }

  Future<void> _formula(List<Stroke> strokes) async {
    if (strokes.isEmpty) return;
    ink.clearSelection();
    setState(() => _notesOpen = true);
    try {
      await widget.sync!.readFormula(strokes);
      unawaited(HapticFeedback.mediumImpact());
    } on Object catch (e) {
      if (!mounted) return;
      unawaited(HapticFeedback.heavyImpact());
      final msg = e is NotesApiException ? e.message : "Couldn't read that formula.";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(msg)));
    }
  }

  void _fitPage() {
    HapticFeedback.selectionClick();
    _zoom.value = Matrix4.identity();
  }

  @override
  void initState() {
    super.initState();
    widget.sync?.addListener(_synced);
    ink.addListener(_synced);
    // Turned sideways: a firm tap says "ready to draw".
    HapticFeedback.mediumImpact();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    widget.sync?.removeListener(_synced);
    ink.removeListener(_synced);
    _zoom.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _tool(InkTool t) {
    if (ink.tool == t) return;
    HapticFeedback.selectionClick();
    ink.setTool(t);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: AnimatedBuilder(
        animation: ink,
        builder: (context, _) => SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Rail(
                children: [
                  _RailButton(icon: Icons.arrow_back_rounded, tooltip: 'Back', onTap: () {
                    HapticFeedback.lightImpact();
                    widget.onClose();
                  }),
                  const SizedBox(height: CockpitSpacing.sm),
                  for (final t in const [InkTool.pen, InkTool.pencil, InkTool.highlighter, InkTool.eraser, InkTool.lasso])
                    _RailButton(icon: t.icon, tooltip: t.name, selected: ink.tool == t, onTap: () => _tool(t)),
                  _ShapeButton(ink: ink, onPick: _tool),
                ],
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(CockpitRadii.lg),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        // One finger draws; two pinch to zoom and move the page.
                        child: Listener(
                          onPointerDown: (_) => setState(() => _fingers++),
                          onPointerUp: (_) => setState(() => _fingers = math.max(0, _fingers - 1)),
                          onPointerCancel: (_) => setState(() => _fingers = math.max(0, _fingers - 1)),
                          child: InteractiveViewer(
                            transformationController: _zoom,
                            minScale: 1,
                            maxScale: 4,
                            panEnabled: _fingers >= 2,
                            child: Material(
                              color: scheme.surfaceContainerLow,
                              child: _InkCanvas(
                                ink: ink,
                                notes: widget.notes,
                                onSwitchToTypewriter: widget.onClose,
                                onFormula: widget.sync == null ? null : _formula,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (widget.top != null)
                        Positioned(left: CockpitSpacing.sm, right: CockpitSpacing.sm, top: CockpitSpacing.sm, child: widget.top!),
                      Positioned(left: CockpitSpacing.sm, bottom: CockpitSpacing.sm, child: _ZoomPill(zoom: _zoom, onFit: _fitPage)),
                      if (widget.sync != null)
                        _NotesDrawer(
                          sync: widget.sync!,
                          page: ink.page,
                          open: _notesOpen,
                          onToggle: () {
                            HapticFeedback.selectionClick();
                            setState(() => _notesOpen = !_notesOpen);
                          },
                        ),
                    ],
                  ),
                ),
              ),
              _Rail(
                children: [
                  for (final c in InkController.palette)
                    _ColorDot(color: c, selected: ink.color == c && ink.tool != InkTool.eraser, onTap: () {
                      HapticFeedback.selectionClick();
                      ink.setColor(c);
                      if (!ink.tool.isDrawing) ink.setTool(InkTool.pen);
                    }),
                  const SizedBox(height: CockpitSpacing.xs),
                  _WidthDial(ink: ink),
                  const Spacer(),
                  _RailButton(
                    icon: Icons.undo_rounded,
                    tooltip: 'Undo',
                    onTap: ink.canUndo
                        ? () {
                            HapticFeedback.lightImpact();
                            ink.undo();
                          }
                        : null,
                  ),
                  _RailButton(
                    icon: Icons.redo_rounded,
                    tooltip: 'Redo',
                    onTap: ink.canRedo
                        ? () {
                            HapticFeedback.lightImpact();
                            ink.redo();
                          }
                        : null,
                  ),
                  _RailButton(
                    icon: Icons.note_add_outlined,
                    tooltip: 'Add page',
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      ink.addPage();
                    },
                  ),
                  _RailButton(
                    icon: Icons.keyboard_arrow_up_rounded,
                    tooltip: 'Previous page',
                    onTap: ink.pageIndex > 0
                        ? () {
                            HapticFeedback.selectionClick();
                            ink.setPage(ink.pageIndex - 1);
                          }
                        : null,
                  ),
                  _PageBadge(ink: ink),
                  _RailButton(
                    icon: Icons.keyboard_arrow_down_rounded,
                    tooltip: 'Next page',
                    onTap: ink.pageIndex < ink.pageCount - 1
                        ? () {
                            HapticFeedback.selectionClick();
                            ink.setPage(ink.pageIndex + 1);
                          }
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 56,
        // A phone on its side is short: the rail scrolls when it doesn't fit.
        child: LayoutBuilder(
          builder: (_, c) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.sm),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight - 2 * CockpitSpacing.sm),
              child: IntrinsicHeight(child: Column(children: children)),
            ),
          ),
        ),
      );
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.icon, required this.tooltip, required this.onTap, this.selected = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          selected: selected,
          label: tooltip,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              width: 42,
              height: 40,
              decoration: BoxDecoration(
                color: selected ? scheme.primary.withValues(alpha: 0.18) : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: AnimatedScale(
                scale: selected ? 1.12 : 1,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                child: Icon(
                  icon,
                  size: 21,
                  color: onTap == null
                      ? scheme.outlineVariant
                      : selected
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rectangle / circle / line behind one button.
class _ShapeButton extends StatelessWidget {
  const _ShapeButton({required this.ink, required this.onPick});
  final InkController ink;
  final ValueChanged<InkTool> onPick;

  static const _shapes = [InkTool.rect, InkTool.circle, InkTool.line];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = _shapes.contains(ink.tool) ? ink.tool : null;
    return PopupMenuButton<InkTool>(
      tooltip: 'Shapes',
      position: PopupMenuPosition.under,
      onOpened: HapticFeedback.selectionClick,
      onSelected: onPick,
      itemBuilder: (_) => [
        for (final s in _shapes)
          PopupMenuItem(value: s, height: 40, child: Row(children: [Icon(s.icon, size: 18), const SizedBox(width: 10), Text(s.name)])),
      ],
      child: Container(
        width: 42,
        height: 40,
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: current != null ? scheme.primary.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(current?.icon ?? Icons.category_outlined, size: 21, color: current != null ? scheme.primary : scheme.onSurfaceVariant),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.selected, required this.onTap});
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ring = Theme.of(context).colorScheme.onSurface;
    // The near-black ink reads as white on the dark rail.
    final shown = color.computeLuminance() < 0.05 ? const Color(0xFFECEDED) : color;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Colour',
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            width: selected ? 26 : 20,
            height: selected ? 26 : 20,
            decoration: BoxDecoration(
              color: shown,
              shape: BoxShape.circle,
              border: Border.all(color: selected ? ring : Colors.transparent, width: 2.5),
              boxShadow: selected ? [BoxShadow(color: shown.withValues(alpha: 0.5), blurRadius: 10)] : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Tap to step through the stroke widths; the dot shows the size.
class _WidthDial extends StatelessWidget {
  const _WidthDial({required this.ink});
  final InkController ink;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const widths = InkController.widths;
    return Tooltip(
      message: 'Stroke width',
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.selectionClick();
          ink.setWidth(widths[(widths.indexOf(ink.width) + 1) % widths.length]);
        },
        child: SizedBox(
          width: 42,
          height: 40,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              width: 4 + ink.width * 2,
              height: 4 + ink.width * 2,
              decoration: BoxDecoration(color: scheme.onSurface, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageBadge extends StatelessWidget {
  const _PageBadge({required this.ink});
  final InkController ink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<int>(
      tooltip: 'Pages',
      onOpened: HapticFeedback.selectionClick,
      onSelected: (i) {
        HapticFeedback.selectionClick();
        ink.setPage(i);
      },
      itemBuilder: (_) => [
        for (var i = 0; i < ink.pageCount; i++) PopupMenuItem(value: i, height: 38, child: Text('Page ${i + 1}')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.xs),
        child: Text('${ink.pageIndex + 1}/${ink.pageCount}',
            style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
      ),
    );
  }
}


/// "150%" while zoomed in; a tap fits the page again.
class _ZoomPill extends StatelessWidget {
  const _ZoomPill({required this.zoom, required this.onFit});
  final TransformationController zoom;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<Matrix4>(
      valueListenable: zoom,
      builder: (_, m, _) {
        final z = m.getMaxScaleOnAxis();
        return AnimatedScale(
          scale: z > 1.02 ? 1 : 0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: Semantics(
            button: true,
            label: 'Fit the page',
            child: GestureDetector(
              onTap: onFit,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xEE1D1E20), borderRadius: BorderRadius.circular(99)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.zoom_out_map_rounded, size: 14, color: Colors.white),
                    const SizedBox(width: 6),
                    Text('${(z * 100).round()}%', style: theme.textTheme.labelSmall?.copyWith(color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The page's handwriting as text: a gold tab on the right edge with the
/// count; it slides open into a list, newest last.
class _NotesDrawer extends StatelessWidget {
  const _NotesDrawer({required this.sync, required this.page, required this.open, required this.onToggle});
  final InkSync sync;
  final InkPage page;
  final bool open;
  final VoidCallback onToggle;

  static const _w = 230.0;
  static const _gold = Color(0xFFE8B84B);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lines = sync.linesOf(page);
    const curve = Curves.easeOutCubic;
    const d = Duration(milliseconds: 420);
    String time(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Positioned.fill(
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: d,
            curve: curve,
            top: 0,
            bottom: 0,
            right: open ? 0 : -_w,
            width: _w,
            child: Material(
              color: scheme.surface,
              elevation: 6,
              child: SafeArea(
                left: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text('This page, as text', style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant))),
                          if (sync.reading) const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: lines.isEmpty
                            ? Text('Write a line. It lands here a moment after you lift the pen.',
                                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant))
                            : ListView(
                                padding: EdgeInsets.zero,
                                reverse: true,
                                children: [
                                  for (final l in lines.reversed)
                                    TweenAnimationBuilder<double>(
                                      key: ValueKey(l),
                                      tween: Tween(begin: 0, end: 1),
                                      duration: const Duration(milliseconds: 420),
                                      curve: curve,
                                      builder: (_, t, child) => Opacity(
                                        opacity: t,
                                        child: Transform.translate(offset: Offset((1 - t) * 16, 0), child: child),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 7),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            _LineText(text: l.text, style: theme.textTheme.bodyMedium),
                                            Text(time(l.at), style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
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
              ),
            ),
          ),
          AnimatedPositioned(
            duration: d,
            curve: curve,
            right: open ? _w : 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: Semantics(
                button: true,
                label: open ? 'Close the notes' : 'Open the notes, ${lines.length} lines',
                child: GestureDetector(
                  onTap: onToggle,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                    decoration: const BoxDecoration(
                      color: _gold,
                      borderRadius: BorderRadius.horizontal(left: Radius.circular(12)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const RotatedBox(
                          quarterTurns: 1,
                          child: Text('Notes', style: TextStyle(color: Color(0xFF412402), fontWeight: FontWeight.w700, fontSize: 12)),
                        ),
                        const SizedBox(height: 6),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 380),
                          transitionBuilder: (c, a) => ScaleTransition(scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack), child: c),
                          child: Container(
                            key: ValueKey(lines.length),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(color: const Color(0xFFE11D2E), borderRadius: BorderRadius.circular(99)),
                            child: Text('${lines.length}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// A line of the page as text; a formula (`$$…$$`) is drawn as maths.
class _LineText extends StatelessWidget {
  const _LineText({required this.text, this.style});
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final formula = text.length > 4 && text.startsWith(r'$$') && text.endsWith(r'$$');
    if (!formula) return Text(text, style: style);
    final tex = text.substring(2, text.length - 2);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Math.tex(
        tex,
        textStyle: style?.copyWith(fontSize: (style?.fontSize ?? 14) + 2),
        onErrorFallback: (_) => Text(tex, style: style?.copyWith(fontFamily: 'monospace')),
      ),
    );
  }
}
