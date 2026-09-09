import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';

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
    final desktop = MediaQuery.sizeOf(context).width >= 1000;
    return AnimatedBuilder(
      animation: ink,
      builder: (context, _) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(CockpitSpacing.md),
              child: Center(child: workspaceToggle),
            ),
            _PencilToolbar(ink: ink),
            Divider(height: 1, color: scheme.outlineVariant),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PageRail(ink: ink),
                  VerticalDivider(width: 1, color: scheme.outlineVariant),
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
  const _PencilToolbar({required this.ink});
  final InkController ink;

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

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.md, vertical: CockpitSpacing.xs),
      child: Row(
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
          const Spacer(),
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
      ),
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
  });
  final InkController ink;
  final NotesController notes;
  final VoidCallback onSwitchToTypewriter;

  @override
  State<_InkCanvas> createState() => _InkCanvasState();
}

class _InkCanvasState extends State<_InkCanvas> {
  List<Offset> _current = [];
  List<double> _pressures = [];
  List<Offset> _lasso = [];
  Offset? _shapeStart;
  Offset? _moveAnchor;

  InkController get ink => widget.ink;

  double _pressure(double raw) => raw <= 0 ? 1.0 : raw.clamp(0.1, 1.0);

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
        setState(() => _lasso = []);
      case InkTool.pointer:
        _moveAnchor = null;
      case InkTool.eraser:
      case InkTool.text:
        break;
    }
  }

  Stroke _stroke(List<Offset> pts, List<double> pr, InkTool t) => Stroke(
        id: 'k${DateTime.now().microsecondsSinceEpoch}',
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
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: _up,
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
          if (sel != null) ...[
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
