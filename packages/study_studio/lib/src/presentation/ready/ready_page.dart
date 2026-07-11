import 'dart:math' as math;

import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../building/build_preview.dart';

/// Screen 4 — Your Study Studio Is Ready.
///
/// The reveal / payoff after the build. The AI Core is now calm at the centre
/// of a finished ecosystem of study tools; the user appreciates what was built
/// before tapping into the studio. Same visual language as Screens 1–3 + Outfit.
class ReadyPage extends StatelessWidget {
  const ReadyPage({super.key, required this.studioId});

  final String studioId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      CockpitSpacing.md,
                      CockpitSpacing.sm,
                      0,
                      0,
                    ),
                    child: _CircleButton(
                      icon: Icons.close,
                      onTap: () => context.go('/study'),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      CockpitSpacing.lg,
                      0,
                      CockpitSpacing.lg,
                      CockpitSpacing.lg,
                    ),
                    children: const [
                      _SuccessHeader(),
                      SizedBox(height: CockpitSpacing.lg),
                      _EcosystemHero(),
                      SizedBox(height: CockpitSpacing.xl),
                      _StatGrid(),
                      SizedBox(height: CockpitSpacing.xl),
                      _AiSummaryCard(),
                    ],
                  ),
                ),
                _EnterBar(studioId: studioId),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Success header
// ---------------------------------------------------------------------------

class _SuccessHeader extends StatelessWidget {
  const _SuccessHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      children: [
        // "Build Complete!" pill.
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: CockpitSpacing.md,
            vertical: CockpitSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: scheme.tertiary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(CockpitRadii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 16, color: scheme.tertiary),
              const SizedBox(width: CockpitSpacing.xs),
              Text(
                'Build Complete!',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.tertiary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: CockpitSpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome, size: 18, color: scheme.primary),
            const SizedBox(width: CockpitSpacing.sm),
            Flexible(
              child: Text(
                'Your Study Studio is Ready!',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const SizedBox(width: CockpitSpacing.sm),
            Icon(Icons.auto_awesome, size: 14, color: scheme.primary),
          ],
        ),
        const SizedBox(height: CockpitSpacing.sm),
        Text.rich(
          textAlign: TextAlign.center,
          TextSpan(
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
            children: [
              TextSpan(
                text: BuildPreview.studioName,
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const TextSpan(
                text: ' has been transformed into your personalized '
                    'AI learning environment.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Ecosystem hero — calm AI core ringed by study tools
// ---------------------------------------------------------------------------

class _EcosystemHero extends StatelessWidget {
  const _EcosystemHero();

  // (icon, color, label, angle°) — angle 0 = right, clockwise (screen y-down).
  static const _nodes = <(IconData, Color, String, double)>[
    (Icons.menu_book_rounded, Color(0xFF8B5CF6), 'Topics', -90),
    (Icons.style_rounded, Color(0xFFF76808), 'Flashcards', -45),
    (Icons.help_rounded, Color(0xFFE5484D), 'Quiz', 0),
    (Icons.forum_rounded, Color(0xFF6366F1), 'Scenarios', 45),
    (Icons.insights_rounded, Color(0xFF3B82F6), 'Progress', 90),
    (Icons.lightbulb_rounded, Color(0xFFF5A623), 'Memory Hooks', 135),
    (Icons.hub_rounded, Color(0xFF7C3AED), 'Knowledge\nGraph', 180),
    (Icons.forum_outlined, Color(0xFF30A46C), 'AI Tutor', -135),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 320,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Dashed orbit ring.
          Positioned.fill(
            child: CustomPaint(
              painter: _OrbitPainter(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.8),
              ),
            ),
          ),
          const _CalmOrb(),
          for (final n in _nodes)
            Align(
              alignment: Alignment(
                math.cos(n.$4 * math.pi / 180) * 0.98,
                math.sin(n.$4 * math.pi / 180) * 0.82,
              ),
              child: _ToolNode(icon: n.$1, color: n.$2, label: n.$3),
            ),
        ],
      ),
    );
  }
}

class _CalmOrb extends StatelessWidget {
  const _CalmOrb();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final violet = _shiftHue(scheme.primary, -28);
    return Container(
      width: 130,
      height: 130,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [violet, scheme.primary],
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.4),
            blurRadius: 40,
            spreadRadius: 4,
          ),
        ],
      ),
      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 54),
    );
  }
}

class _ToolNode extends StatelessWidget {
  const _ToolNode({required this.icon, required this.color, required this.label});
  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    // Two concentric dashed ellipses.
    for (final r in [0.62, 0.9]) {
      final rect = Rect.fromCenter(
        center: center,
        width: size.width * r,
        height: size.height * r * 0.86,
      );
      _dashedOval(canvas, rect, paint);
    }
  }

  void _dashedOval(Canvas canvas, Rect rect, Paint paint) {
    final path = Path()..addOval(rect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, (d + 5).clamp(0, metric.length)),
          paint,
        );
        d += 10;
      }
    }
  }

  @override
  bool shouldRepaint(_OrbitPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// What was built — stat grid
// ---------------------------------------------------------------------------

class _StatGrid extends StatelessWidget {
  const _StatGrid();

  static const _stats = <(IconData, Color, int, String)>[
    (Icons.menu_book_rounded, Color(0xFF8B5CF6), BuildPreview.topics, 'Topics'),
    (Icons.bookmark_rounded, Color(0xFF30A46C), BuildPreview.definitions, 'Definitions'),
    (Icons.style_rounded, Color(0xFFF76808), BuildPreview.flashcards, 'Flashcards'),
    (Icons.help_rounded, Color(0xFFE5484D), BuildPreview.quizQuestions, 'Quiz Questions'),
    (Icons.hub_rounded, Color(0xFF6366F1), BuildPreview.connections, 'Connections'),
    (Icons.insights_rounded, Color(0xFF3B82F6), BuildPreview.studyPaths, 'Study Paths'),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _stats.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        mainAxisSpacing: CockpitSpacing.sm,
        crossAxisSpacing: CockpitSpacing.sm,
        mainAxisExtent: 120,
      ),
      itemBuilder: (context, i) {
        final s = _stats[i];
        return _StatCard(icon: s.$1, color: s.$2, value: s.$3, label: s.$4);
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: CockpitSpacing.xs),
          Text(
            '$value',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: CockpitSpacing.xs),
          Container(
            height: 3,
            width: 24,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(CockpitRadii.pill),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AI Summary card
// ---------------------------------------------------------------------------

class _AiSummaryCard extends StatelessWidget {
  const _AiSummaryCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: scheme.primary),
              const SizedBox(width: CockpitSpacing.sm),
              Text(
                'AI Summary',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Text(
            "We've identified the most important topics:",
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Wrap(
            spacing: CockpitSpacing.sm,
            runSpacing: CockpitSpacing.sm,
            children: [
              for (final t in BuildPreview.importantTopics)
                _TopicChip(label: t),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.lg),
            child: Divider(color: scheme.outlineVariant, height: 1),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Expanded(
                child: _SummaryMetric(
                  icon: Icons.schedule,
                  label: 'Estimated Study Time',
                  value: BuildPreview.estimatedStudyTime,
                ),
              ),
              Expanded(
                child: _SummaryMetric(
                  icon: Icons.bar_chart,
                  label: 'Difficulty Level',
                  value: BuildPreview.difficulty,
                  valueColor: Color(0xFF6366F1),
                ),
              ),
              Expanded(
                child: _SummaryMetric(
                  icon: Icons.track_changes,
                  label: 'Confidence to Master',
                  value: BuildPreview.confidence,
                  valueColor: Color(0xFF30A46C),
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.lg),
          Container(
            padding: const EdgeInsets.all(CockpitSpacing.md),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(CockpitRadii.md),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 16, color: scheme.primary),
                const SizedBox(width: CockpitSpacing.sm),
                Expanded(
                  child: Text(
                    'AI Tutor is ready to help you learn, practice, '
                    'and master these topics!',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopicChip extends StatelessWidget {
  const _TopicChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CockpitSpacing.md,
        vertical: CockpitSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check, size: 13, color: scheme.primary),
          const SizedBox(width: CockpitSpacing.xs),
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: scheme.onSurfaceVariant),
            const SizedBox(width: 3),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontSize: 11,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: CockpitSpacing.xs),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: valueColor ?? scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Enter CTA
// ---------------------------------------------------------------------------

class _EnterBar extends StatelessWidget {
  const _EnterBar({required this.studioId});
  final String studioId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final violet = _shiftHue(scheme.primary, -28);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        CockpitSpacing.lg,
        CockpitSpacing.md,
        CockpitSpacing.lg,
        CockpitSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => context.go('/study/$studioId'),
              borderRadius: BorderRadius.circular(CockpitRadii.pill),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(CockpitRadii.pill),
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [scheme.secondary, violet],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const SizedBox(
                  height: 54,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                      SizedBox(width: CockpitSpacing.sm),
                      Text(
                        'Enter Study Studio',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: CockpitSpacing.sm),
                      Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: CockpitSpacing.xs),
          TextButton.icon(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Processing report — coming soon')),
            ),
            icon: const Icon(Icons.description_outlined, size: 16),
            label: const Text('View Processing Report'),
          ),
        ],
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
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: theme.colorScheme.onSurface),
      ),
    );
  }
}

/// Rotates a color's hue to build a same-family gradient companion.
Color _shiftHue(Color base, double degrees) {
  final hsl = HSLColor.fromColor(base);
  final h = (hsl.hue + degrees) % 360;
  return hsl.withHue(h < 0 ? h + 360 : h).toColor();
}
