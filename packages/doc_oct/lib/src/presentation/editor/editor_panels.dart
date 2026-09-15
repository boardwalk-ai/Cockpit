import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';

enum PanelSide { left, right }

/// A collapsible, drag-resizable side panel — mirrors the web editor's Outline /
/// Tools panels: a default width, draggable wider (up to half the viewport),
/// and a collapse/expand toggle. Borderless: a soft fill sets it off from the
/// paper canvas, the resize seam is a hairline that thickens on hover.
class SidePanel extends StatelessWidget {
  const SidePanel({
    super.key,
    required this.side,
    required this.open,
    required this.width,
    required this.defaultWidth,
    required this.title,
    required this.child,
    required this.onToggle,
    required this.onResize,
    this.minWidth = 220,
    this.maxWidth = 560,
  });

  final PanelSide side;
  final bool open;
  final double width;

  /// The resting width the drag magnetically snaps back to.
  final double defaultWidth;
  final String title;
  final Widget child;
  final VoidCallback onToggle;
  final ValueChanged<double> onResize;
  final double minWidth;
  final double maxWidth;

  bool get _isLeft => side == PanelSide.left;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!open) return _CollapsedRail(isLeft: _isLeft, onExpand: onToggle);

    final panel = SizedBox(
      width: width.clamp(minWidth, maxWidth),
      child: ColoredBox(
        color: scheme.surfaceContainerLow,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, scheme),
            Expanded(child: child),
          ],
        ),
      ),
    );

    final handle = _ResizeHandle(
      width: width,
      isLeft: _isLeft,
      minWidth: minWidth,
      maxWidth: maxWidth,
      snapTo: defaultWidth,
      onResize: onResize,
    );

    return Row(
      children: _isLeft ? [panel, handle] : [handle, panel],
    );
  }

  Widget _header(BuildContext context, ColorScheme scheme) {
    final collapse = IconButton(
      onPressed: onToggle,
      icon: Icon(_isLeft ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
          size: 18),
      color: scheme.onSurfaceVariant,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      splashRadius: 16,
    );
    final label = Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w700,
          ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          CockpitSpacing.lg, CockpitSpacing.md, CockpitSpacing.sm, CockpitSpacing.sm),
      child: Row(
        children: _isLeft
            ? [Expanded(child: label), collapse]
            : [collapse, const SizedBox(width: CockpitSpacing.sm), Expanded(child: label)],
      ),
    );
  }
}

class _CollapsedRail extends StatelessWidget {
  const _CollapsedRail({required this.isLeft, required this.onExpand});
  final bool isLeft;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 32,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: CockpitSpacing.md),
          child: IconButton(
            onPressed: onExpand,
            icon: Icon(
                isLeft ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
                size: 18),
            color: scheme.onSurfaceVariant,
            style: IconButton.styleFrom(
              backgroundColor: scheme.surfaceContainerLow,
              minimumSize: const Size(28, 28),
              padding: EdgeInsets.zero,
            ),
          ),
        ),
      ),
    );
  }
}

class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({
    required this.width,
    required this.isLeft,
    required this.minWidth,
    required this.maxWidth,
    required this.snapTo,
    required this.onResize,
  });

  final double width;
  final bool isLeft;
  final double minWidth;
  final double maxWidth;
  final double snapTo;
  final ValueChanged<double> onResize;

  /// Magnetic-snap radius (px) around [snapTo].
  static const double snapRadius = 36;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  bool _hover = false;
  bool _dragging = false;
  double _startWidth = 0;
  double _startX = 0;

  void _update(double globalX) {
    // Absolute tracking against the drag origin — follows the pointer exactly,
    // regardless of the handle moving as the panel resizes.
    final delta = (widget.isLeft ? 1 : -1) * (globalX - _startX);
    var w = (_startWidth + delta).clamp(widget.minWidth, widget.maxWidth);
    // Magnetic snap to the default width.
    if ((w - widget.snapTo).abs() <= _ResizeHandle.snapRadius) w = widget.snapTo;
    widget.onResize(w);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = _hover || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (d) {
          _startWidth = widget.width;
          _startX = d.globalPosition.dx;
          setState(() => _dragging = true);
        },
        onHorizontalDragUpdate: (d) => _update(d.globalPosition.dx),
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        onHorizontalDragCancel: () => setState(() => _dragging = false),
        child: SizedBox(
          width: 8,
          child: Center(
            child: Container(
              width: active ? 2 : 1,
              color: active
                  ? scheme.primary.withValues(alpha: 0.6)
                  : scheme.onSurface.withValues(alpha: 0.08),
            ),
          ),
        ),
      ),
    );
  }
}

/// Left panel body — the Outline, empty until the wizard/analysis fills it.
class OutlinePanel extends StatelessWidget {
  const OutlinePanel({super.key});

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
            Icon(Icons.segment_rounded,
                size: 26, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: CockpitSpacing.md),
            Text('Nothing here yet',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: CockpitSpacing.xs),
            Text(
              'Analyze your assignment and generate an outline in the setup '
              'wizard — both show up here as you write.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }
}

