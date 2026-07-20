import 'dart:math' as math;

import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../widgets/studio_scaffold.dart';

class KnowledgeGraphPage extends ConsumerStatefulWidget {
  const KnowledgeGraphPage({super.key, required this.studioId});

  final String studioId;

  @override
  ConsumerState<KnowledgeGraphPage> createState() => _KnowledgeGraphPageState();
}

class _KnowledgeGraphPageState extends ConsumerState<KnowledgeGraphPage> {
  final TransformationController _tc = TransformationController();
  late final _GraphData _graph = _buildGraph();
  late String _selectedId = _graph.selectedId;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  void _zoomBy(double factor) {
    final next = _tc.value.clone()..scaleByDouble(factor, factor, factor, 1);
    _tc.value = next;
  }

  void _resetView() => _tc.value = Matrix4.identity();

  _GraphNode get _selected =>
      _graph.nodes.firstWhere((n) => n.id == _selectedId);

  @override
  Widget build(BuildContext context) {
    final studioTitle =
        ref.watch(studioProvider(widget.studioId)).valueOrNull?.title ??
            'Study Studio';
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: isDesktop(context) ? 860 : 480),
            child: Column(
              children: [
                _Header(
                  title: studioTitle,
                  connectionCount: _graph.connectionCount,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(
                            CockpitSpacing.lg,
                            CockpitSpacing.xs,
                            CockpitSpacing.lg,
                            CockpitSpacing.sm,
                          ),
                          child: _AiInsightCard(),
                        ),
                        SizedBox(
                          height: 520,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: InteractiveViewer(
                                  transformationController: _tc,
                                  panEnabled: false,
                                  minScale: 0.5,
                                  maxScale: 3,
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final size = Size(
                                        constraints.maxWidth,
                                        constraints.maxHeight,
                                      );
                                      return _GraphCanvas(
                                        graph: _graph,
                                        size: size,
                                        selectedId: _selectedId,
                                        onTapNode: (id) =>
                                            setState(() => _selectedId = id),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              Positioned(
                                right: CockpitSpacing.sm,
                                top: CockpitSpacing.sm,
                                child: _ZoomControls(
                                  onZoomIn: () => _zoomBy(1.2),
                                  onZoomOut: () => _zoomBy(1 / 1.2),
                                  onReset: _resetView,
                                  onFit: _resetView,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _DetailSheet(
                          node: _selected,
                          studioId: widget.studioId,
                        ),
                        const _Legend(),
                        const SizedBox(height: CockpitSpacing.md),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: const _GraphBottomNav(),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.connectionCount});
  final String title;
  final int connectionCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CockpitSpacing.md,
        CockpitSpacing.sm,
        CockpitSpacing.md,
        CockpitSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CircleButton(
            icon: Icons.arrow_back_ios_new,
            onTap: () =>
                context.canPop() ? context.pop() : context.go('/study'),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.hub_rounded, size: 14, color: scheme.primary),
                    const SizedBox(width: CockpitSpacing.xs),
                    Text(
                      'Knowledge Graph',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Text(
                  '$connectionCount AI-discovered concept connections',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: CockpitSpacing.xs),
          _CircleButton(
            icon: Icons.search,
            onTap: () => _soon(context, 'Search'),
          ),
          const SizedBox(width: CockpitSpacing.xs),
          _CircleButton(
            icon: Icons.tune_rounded,
            onTap: () => _soon(context, 'Filter'),
          ),
          const SizedBox(width: CockpitSpacing.xs),
          _CircleButton(
            icon: Icons.more_horiz,
            onTap: () => _soon(context, 'Options'),
          ),
        ],
      ),
    );
  }
}

class _GraphCanvas extends StatelessWidget {
  const _GraphCanvas({
    required this.graph,
    required this.size,
    required this.selectedId,
    required this.onTapNode,
  });

  final _GraphData graph;
  final Size size;
  final String selectedId;
  final ValueChanged<String> onTapNode;

  Offset _center(_GraphNode n) => Offset(n.x * size.width, n.y * size.height);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final positions = {for (final n in graph.nodes) n.id: _center(n)};

    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _EdgePainter(
                graph: graph,
                positions: positions,
                colorFor: (m) => _masteryColor(scheme, m),
              ),
            ),
          ),
          for (final n in graph.nodes)
            _PositionedNode(
              node: n,
              center: positions[n.id]!,
              selected: n.id == selectedId,
              onTap: () => onTapNode(n.id),
            ),
        ],
      ),
    );
  }
}

// Draws the curved connecting lines between the nodes.
class _EdgePainter extends CustomPainter {
  _EdgePainter({
    required this.graph,
    required this.positions,
    required this.colorFor,
  });

  final _GraphData graph;
  final Map<String, Offset> positions;
  final Color Function(_Mastery) colorFor;

  @override
  void paint(Canvas canvas, Size size) {
    for (final e in graph.edges) {
      final a = positions[e.from];
      final b = positions[e.to];
      if (a == null || b == null) continue;

      final toNode = graph.nodes.firstWhere((n) => n.id == e.to);
      final color = colorFor(toNode.mastery).withValues(alpha: 0.35);
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;

      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      final dir = b - a;
      final normal = Offset(-dir.dy, dir.dx);
      final len = normal.distance;
      final unit = len == 0 ? Offset.zero : normal / len;
      final control = mid + unit * (dir.distance * 0.12);

      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(control.dx, control.dy, b.dx, b.dy);

      if (e.dashed) {
        _drawDashed(canvas, path, paint);
      } else {
        canvas.drawPath(path, paint);
      }
    }
  }

  void _drawDashed(Canvas canvas, Path path, Paint paint) {
    const dash = 6.0;
    const gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dash;
        canvas.drawPath(
          metric.extractPath(distance, math.min(next, metric.length)),
          paint,
        );
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EdgePainter oldDelegate) =>
      oldDelegate.positions != positions || oldDelegate.graph != graph;
}

class _PositionedNode extends StatelessWidget {
  const _PositionedNode({
    required this.node,
    required this.center,
    required this.selected,
    required this.onTap,
  });

  final _GraphNode node;
  final Offset center;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = _masteryColor(scheme, node.mastery);
    final diameter = node.radius * 2;
    const boxWidth = 96.0;

    return Positioned(
      left: center.dx - boxWidth / 2,
      top: center.dy - node.radius,
      width: boxWidth,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                shape: BoxShape.circle,
                border: Border.all(
                  color: color.withValues(alpha: selected ? 1 : 0.6),
                  width: selected ? 3 : 1.5,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.35),
                          blurRadius: 16,
                        ),
                      ]
                    : null,
              ),
              child: Icon(node.icon, color: color, size: node.radius * 0.9),
            ),
            const SizedBox(height: 3),
            Text(
              node.label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.05,
                fontSize: 9.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiInsightCard extends StatelessWidget {
  const _AiInsightCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const gains = ['TCP/IP', 'Network Security', 'WAN Design'];
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(CockpitRadii.xl),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [scheme.secondary, scheme.primary],
                  ),
                ),
                child: const Icon(
                  Icons.smart_toy_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: CockpitSpacing.sm),
              Text(
                'AI Insight',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Text.rich(
            TextSpan(
              style: theme.textTheme.bodySmall?.copyWith(height: 1.3),
              children: [
                const TextSpan(text: 'Improving '),
                TextSpan(
                  text: 'Routing',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const TextSpan(text: ' will likely increase your mastery of:'),
              ],
            ),
          ),
          const SizedBox(height: CockpitSpacing.sm),
          for (final g in gains)
            Padding(
              padding: const EdgeInsets.only(bottom: CockpitSpacing.xs),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 14,
                    color: CockpitColors.brand.success,
                  ),
                  const SizedBox(width: CockpitSpacing.xs),
                  Text(g, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          const SizedBox(height: CockpitSpacing.xs),
          Divider(color: scheme.outlineVariant, height: CockpitSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Estimated gain',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Text(
                '+8%',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: CockpitColors.brand.success,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'overall mastery',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.primary,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
    required this.onFit,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.xs),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomButton(icon: Icons.add, label: 'Zoom In', onTap: onZoomIn),
          _ZoomButton(icon: Icons.remove, label: 'Zoom Out', onTap: onZoomOut),
          _ZoomButton(
            icon: Icons.my_location_rounded,
            label: 'Reset View',
            onTap: onReset,
          ),
          _ZoomButton(
            icon: Icons.fit_screen_rounded,
            label: 'Fit to Screen',
            onTap: onFit,
          ),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              shape: BoxShape.circle,
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Icon(icon, size: 17, color: scheme.primary),
          ),
        ),
      ),
    );
  }
}

class _DetailSheet extends StatelessWidget {
  const _DetailSheet({required this.node, required this.studioId});
  final _GraphNode node;
  final String studioId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = _masteryColor(scheme, node.mastery);
    final base = '/study/$studioId';

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CockpitRadii.xl),
        ),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.6)),
                ),
                child: Icon(node.icon, color: color, size: 22),
              ),
              const SizedBox(width: CockpitSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            node.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: CockpitSpacing.sm),
                        TagChip(
                          label: _masteryLabel(node.mastery),
                          color: color,
                          icon: Icons.circle,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      node.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: CockpitSpacing.sm),
              Column(
                children: [
                  ProgressRing(
                    value: node.mastery == _Mastery.mastered ? 0.9 : 0.68,
                    size: 52,
                    stroke: 6,
                    color: color,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Mastery',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.md),
          Divider(color: scheme.outlineVariant, height: 1),
          const SizedBox(height: CockpitSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Related Concepts',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: CockpitSpacing.xs),
                    Wrap(
                      spacing: CockpitSpacing.xs,
                      runSpacing: CockpitSpacing.xs,
                      children: [
                        for (final r in node.related) TagChip(label: r),
                        if (node.relatedMore > 0)
                          TagChip(label: '+${node.relatedMore} more'),
                      ],
                    ),
                  ],
                ),
              ),
              if (node.studyTimeMin != null) ...[
                const SizedBox(width: CockpitSpacing.md),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Study Time',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: CockpitSpacing.xs),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule,
                            size: 14,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: CockpitSpacing.xs),
                          Text(
                            '${node.studyTimeMin} min',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Across all activities',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (node.weakness != null) ...[
                const SizedBox(width: CockpitSpacing.md),
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Weakness',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: CockpitSpacing.xs),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.show_chart_rounded,
                            size: 14,
                            color: scheme.error,
                          ),
                          const SizedBox(width: CockpitSpacing.xs),
                          Expanded(
                            child: Text(
                              node.weakness!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                height: 1.2,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: CockpitSpacing.md),
          Row(
            children: [
              Expanded(
                child: _ModeCard(
                  icon: Icons.school_rounded,
                  color: scheme.primary,
                  title: 'Teach Me',
                  subtitle: 'Learn this topic',
                  onTap: () => context.go('$base/topics'),
                ),
              ),
              const SizedBox(width: CockpitSpacing.sm),
              Expanded(
                child: _ModeCard(
                  icon: Icons.help_rounded,
                  color: CockpitColors.brand.success,
                  title: 'Quiz Me',
                  subtitle: 'Test yourself',
                  onTap: () => context.go('$base/quiz'),
                ),
              ),
              const SizedBox(width: CockpitSpacing.sm),
              Expanded(
                child: _ModeCard(
                  icon: Icons.style_rounded,
                  color: scheme.tertiary,
                  title: 'Flashcards',
                  subtitle: 'Review cards',
                  onTap: () => context.go('$base/flashcards'),
                ),
              ),
              const SizedBox(width: CockpitSpacing.sm),
              Expanded(
                child: _ModeCard(
                  icon: Icons.track_changes_rounded,
                  color: scheme.error,
                  title: 'Scenario',
                  subtitle: 'Apply in context',
                  onTap: () => context.go('$base/topics'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(CockpitRadii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        child: Padding(
          padding: const EdgeInsets.all(CockpitSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: CockpitSpacing.xs),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontSize: 9,
                ),
              ),
              const SizedBox(height: CockpitSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: Icon(Icons.arrow_forward, size: 15, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const items = <(_Mastery, String)>[
      (_Mastery.mastered, 'Mastered'),
      (_Mastery.learning, 'Learning'),
      (_Mastery.needsPractice, 'Needs Practice'),
      (_Mastery.focus, 'Current Focus'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CockpitSpacing.lg,
        vertical: CockpitSpacing.sm,
      ),
      child: Wrap(
        spacing: CockpitSpacing.lg,
        runSpacing: CockpitSpacing.xs,
        children: [
          for (final it in items)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _masteryColor(scheme, it.$1),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: CockpitSpacing.xs),
                Text(it.$2, style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
        ],
      ),
    );
  }
}

class _GraphBottomNav extends StatelessWidget {
  const _GraphBottomNav();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          padding: const EdgeInsets.all(CockpitSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: _NavItem(
                  icon: Icons.format_list_bulleted_rounded,
                  label: 'List View',
                  selected: false,
                  onTap: () => _soon(context, 'List View'),
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.hub_rounded,
                  label: 'Knowledge Graph',
                  selected: true,
                  onTap: () {},
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.track_changes_rounded,
                  label: 'My Weak Areas',
                  selected: false,
                  onTap: () => _soon(context, 'My Weak Areas'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withValues(alpha: 0.10) : null,
          borderRadius: BorderRadius.circular(CockpitRadii.pill),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: CockpitSpacing.xs),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 16, color: scheme.onSurface),
      ),
    );
  }
}

Color _masteryColor(ColorScheme scheme, _Mastery m) {
  switch (m) {
    case _Mastery.mastered:
      return CockpitColors.brand.success;
    case _Mastery.learning:
      return scheme.tertiary;
    case _Mastery.needsPractice:
      return scheme.error;
    case _Mastery.focus:
      return scheme.primary;
  }
}

String _masteryLabel(_Mastery m) {
  switch (m) {
    case _Mastery.mastered:
      return 'Mastered';
    case _Mastery.learning:
      return 'Learning';
    case _Mastery.needsPractice:
      return 'Needs Practice';
    case _Mastery.focus:
      return 'Current Focus';
  }
}

void _soon(BuildContext context, String label) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('$label — coming soon')));
}

enum _Mastery { mastered, learning, needsPractice, focus }

class _GraphNode {
  const _GraphNode({
    required this.id,
    required this.label,
    required this.icon,
    required this.mastery,
    required this.x,
    required this.y,
    this.radius = 22,
    this.description = '',
    this.related = const [],
    this.relatedMore = 0,
    this.studyTimeMin,
    this.weakness,
  });

  final String id;
  final String label;
  final IconData icon;
  final _Mastery mastery;

  // x and y are 0-1 so node positions scale to any screen size.
  final double x;
  final double y;
  final double radius;

  final String description;
  final List<String> related;
  final int relatedMore;
  final int? studyTimeMin;
  final String? weakness;
}

class _GraphEdge {
  const _GraphEdge(this.from, this.to, {this.dashed = false});
  final String from;
  final String to;
  final bool dashed;
}

class _GraphData {
  const _GraphData({
    required this.nodes,
    required this.edges,
    required this.selectedId,
    required this.connectionCount,
  });
  final List<_GraphNode> nodes;
  final List<_GraphEdge> edges;
  final String selectedId;
  final int connectionCount;
}

// The graph's nodes and connections (local mock data).
_GraphData _buildGraph() {
  const nodes = <_GraphNode>[
    _GraphNode(
      id: 'cn',
      label: 'Computer Networks',
      icon: Icons.hub_rounded,
      mastery: _Mastery.focus,
      x: 0.52,
      y: 0.05,
      radius: 26,
    ),
    _GraphNode(
      id: 'osi',
      label: 'OSI Model',
      icon: Icons.layers_rounded,
      mastery: _Mastery.learning,
      x: 0.50,
      y: 0.16,
      radius: 25,
    ),
    _GraphNode(
      id: 'physical',
      label: 'Physical Layer',
      icon: Icons.cable_rounded,
      mastery: _Mastery.mastered,
      x: 0.42,
      y: 0.26,
    ),
    _GraphNode(
      id: 'application',
      label: 'Application Layer',
      icon: Icons.apps_rounded,
      mastery: _Mastery.mastered,
      x: 0.60,
      y: 0.24,
    ),
    _GraphNode(
      id: 'datalink',
      label: 'Data Link Layer',
      icon: Icons.link_rounded,
      mastery: _Mastery.mastered,
      x: 0.30,
      y: 0.38,
    ),
    _GraphNode(
      id: 'network',
      label: 'Network Layer',
      icon: Icons.cloud_rounded,
      mastery: _Mastery.needsPractice,
      x: 0.52,
      y: 0.34,
      radius: 26,
    ),
    _GraphNode(
      id: 'presentation',
      label: 'Presentation Layer',
      icon: Icons.slideshow_rounded,
      mastery: _Mastery.mastered,
      x: 0.74,
      y: 0.34,
    ),
    _GraphNode(
      id: 'session',
      label: 'Session Layer',
      icon: Icons.forum_rounded,
      mastery: _Mastery.learning,
      x: 0.70,
      y: 0.44,
    ),
    _GraphNode(
      id: 'transport',
      label: 'Transport Layer',
      icon: Icons.local_shipping_rounded,
      mastery: _Mastery.learning,
      x: 0.50,
      y: 0.46,
    ),
    _GraphNode(
      id: 'ethernet',
      label: 'Ethernet',
      icon: Icons.settings_ethernet_rounded,
      mastery: _Mastery.learning,
      x: 0.26,
      y: 0.48,
    ),
    _GraphNode(
      id: 'mac',
      label: 'MAC Address',
      icon: Icons.badge_rounded,
      mastery: _Mastery.mastered,
      x: 0.13,
      y: 0.56,
    ),
    _GraphNode(
      id: 'routing',
      label: 'Routing',
      icon: Icons.router_rounded,
      mastery: _Mastery.needsPractice,
      x: 0.50,
      y: 0.62,
      radius: 30,
      description:
          'Determining the best path for data to travel between different networks.',
      related: ['TCP/IP Model', 'Subnetting', 'Routers'],
      relatedMore: 6,
      studyTimeMin: 34,
      weakness: 'Scenario questions and complex routing tables',
    ),
    _GraphNode(
      id: 'ip',
      label: 'IP Addressing',
      icon: Icons.pin_drop_rounded,
      mastery: _Mastery.learning,
      x: 0.69,
      y: 0.56,
    ),
    _GraphNode(
      id: 'switches',
      label: 'Switches',
      icon: Icons.device_hub_rounded,
      mastery: _Mastery.mastered,
      x: 0.15,
      y: 0.66,
    ),
    _GraphNode(
      id: 'subnetting',
      label: 'Subnetting',
      icon: Icons.account_tree_rounded,
      mastery: _Mastery.learning,
      x: 0.85,
      y: 0.62,
    ),
    _GraphNode(
      id: 'routers',
      label: 'Routers',
      icon: Icons.router_outlined,
      mastery: _Mastery.mastered,
      x: 0.30,
      y: 0.72,
    ),
    _GraphNode(
      id: 'tcpip',
      label: 'TCP/IP Model',
      icon: Icons.dns_rounded,
      mastery: _Mastery.mastered,
      x: 0.52,
      y: 0.76,
    ),
    _GraphNode(
      id: 'security',
      label: 'Network Security',
      icon: Icons.shield_rounded,
      mastery: _Mastery.learning,
      x: 0.19,
      y: 0.82,
    ),
    _GraphNode(
      id: 'wan',
      label: 'WAN Design',
      icon: Icons.travel_explore_rounded,
      mastery: _Mastery.needsPractice,
      x: 0.39,
      y: 0.87,
    ),
    _GraphNode(
      id: 'trouble',
      label: 'Troubleshooting',
      icon: Icons.build_rounded,
      mastery: _Mastery.mastered,
      x: 0.72,
      y: 0.80,
    ),
  ];

  const edges = <_GraphEdge>[
    _GraphEdge('cn', 'osi'),
    _GraphEdge('osi', 'physical'),
    _GraphEdge('osi', 'application'),
    _GraphEdge('osi', 'datalink'),
    _GraphEdge('osi', 'network'),
    _GraphEdge('osi', 'presentation'),
    _GraphEdge('osi', 'session'),
    _GraphEdge('osi', 'transport'),
    _GraphEdge('network', 'routing'),
    _GraphEdge('network', 'presentation', dashed: true),
    _GraphEdge('routing', 'transport'),
    _GraphEdge('routing', 'ip'),
    _GraphEdge('routing', 'ethernet', dashed: true),
    _GraphEdge('routing', 'switches', dashed: true),
    _GraphEdge('routing', 'subnetting'),
    _GraphEdge('routing', 'routers'),
    _GraphEdge('routing', 'tcpip'),
    _GraphEdge('routing', 'security', dashed: true),
    _GraphEdge('routing', 'wan'),
    _GraphEdge('routing', 'trouble', dashed: true),
    _GraphEdge('ethernet', 'mac'),
    _GraphEdge('ip', 'subnetting'),
    _GraphEdge('ip', 'trouble', dashed: true),
    _GraphEdge('tcpip', 'trouble'),
    _GraphEdge('tcpip', 'routers'),
    _GraphEdge('cn', 'subnetting', dashed: true),
    _GraphEdge('cn', 'security', dashed: true),
  ];

  return const _GraphData(
    nodes: nodes,
    edges: edges,
    selectedId: 'routing',
    connectionCount: 126,
  );
}
