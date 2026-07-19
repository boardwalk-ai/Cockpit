import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/studio_scaffold.dart';
import 'build_preview.dart';

/// Screen 3 — AI Building Your Study Studio.
///
/// The emotional payoff of the upload flow: not a spinner, but the AI Core from
/// Screen 2 actively assembling a learning environment. A live timeline, live
/// preview counters, and a progress bar all animate off one controller, then
/// the screen transitions into the built studio's dashboard.
class BuildingPage extends StatefulWidget {
  const BuildingPage({super.key, required this.jobId});

  final String jobId;

  @override
  State<BuildingPage> createState() => _BuildingPageState();
}

/// Total simulated build time. Swap for real backend progress later.
const _buildDuration = Duration(seconds: 14);

/// At 100% the flow reveals the "ready" screen (Screen 4) before the dashboard.
const _builtStudioRoute = BuildPreview.readyRoute;

class _BuildingPageState extends State<BuildingPage>
    with TickerProviderStateMixin {
  late final AnimationController _c;
  late final AnimationController _pulse;
  bool _navigated = false;

  // Build steps with the progress fraction at which each finishes.
  static const steps = <(String, double)>[
    ('Reading documents', 0.10),
    ('Transcribing lecture audio', 0.20),
    ('Extracting key concepts', 0.30),
    ('Building topic hierarchy', 0.45),
    ('Linking related ideas', 0.55),
    ('Creating flashcards', 0.65),
    ('Generating quizzes', 0.75),
    ('Creating scenarios', 0.83),
    ('Building knowledge graph', 0.92),
    ('Preparing AI Tutor', 1.0),
  ];

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _c = AnimationController(vsync: this, duration: _buildDuration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && !_navigated && mounted) {
          _navigated = true;
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) context.go(_builtStudioRoute);
          });
        }
      })
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    _pulse.dispose();
    super.dispose();
  }

  /// Index of the step currently in progress (-1 if all done).
  int _activeStep(double p) {
    for (var i = 0; i < steps.length; i++) {
      if (p < steps[i].$2) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktop(context);
    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final p = _c.value;
            final active = _activeStep(p);
            final liveLabel = Text(
              'Live Preview',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            );

            if (desktop) {
              // Viewport-fit: header pinned at top, the progress bar and
              // reassurance note pinned at the bottom, and the core/timeline +
              // live preview fill the middle (scrolling only if the window is
              // unusually short) so the page itself never scrolls.
              return Padding(
                padding: const EdgeInsets.fromLTRB(40, 24, 40, 20),
                child: ContentColumn(
                  maxWidth: 1080,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Header(onBack: () => context.go('/study/upload')),
                      const SizedBox(height: CockpitSpacing.lg),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: _CoreStage(pulse: _pulse)),
                                  const SizedBox(width: 40),
                                  Expanded(
                                    child: _TimelineCard(
                                      progress: p,
                                      activeStep: active,
                                      pulse: _pulse,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: CockpitSpacing.lg),
                              liveLabel,
                              const SizedBox(height: CockpitSpacing.md),
                              _LivePreviewRow(progress: p),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: CockpitSpacing.lg),
                      _ProgressSection(progress: p),
                      const SizedBox(height: CockpitSpacing.md),
                      const _ReassuranceNote(),
                    ],
                  ),
                ),
              );
            }

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    CockpitSpacing.lg,
                    CockpitSpacing.sm,
                    CockpitSpacing.lg,
                    CockpitSpacing.xxl,
                  ),
                  children: [
                    _Header(onBack: () => context.go('/study/upload')),
                    const SizedBox(height: CockpitSpacing.lg),
                    _CoreStage(pulse: _pulse),
                    const SizedBox(height: CockpitSpacing.xl),
                    _TimelineCard(progress: p, activeStep: active, pulse: _pulse),
                    const SizedBox(height: CockpitSpacing.xl),
                    liveLabel,
                    const SizedBox(height: CockpitSpacing.md),
                    _LivePreviewRow(progress: p),
                    const SizedBox(height: CockpitSpacing.xl),
                    _ProgressSection(progress: p),
                    const SizedBox(height: CockpitSpacing.lg),
                    const _ReassuranceNote(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onBack,
              borderRadius: BorderRadius.circular(CockpitRadii.pill),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.arrow_back_ios_new,
                    size: 18, color: theme.colorScheme.onSurface),
              ),
            ),
            const SizedBox(width: CockpitSpacing.sm),
            Expanded(
              child: Column(
                children: [
                  Text(
                    'Building Your Study Studio',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: CockpitSpacing.xs),
                  Text(
                    'AI is analyzing your materials and creating your '
                    'personalized learning environment.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 48), // balances the back button
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// AI Core stage — files converge into the glowing core
// ---------------------------------------------------------------------------

class _CoreStage extends StatelessWidget {
  const _CoreStage({required this.pulse});
  final Animation<double> pulse;

  // Source files (from Screen 2) shown converging into the core.
  static const _files = <(IconData, Color, String, String)>[
    (Icons.picture_as_pdf, Color(0xFFE5484D), 'Lecture 5.pdf', '124 pages'),
    (Icons.slideshow, Color(0xFFF76808), 'Midterm Slides.pptx', '58 slides'),
    (Icons.graphic_eq, Color(0xFF8B5CF6), 'Lecture Recording.mp3', '1h 42m'),
  ];

  // Satellite outputs on the right.
  static const _sats = <(IconData, Color)>[
    (Icons.image, Color(0xFF30A46C)),
    (Icons.description, Color(0xFF3B82F6)),
    (Icons.videocam, Color(0xFF30A46C)),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 250,
      child: Stack(
        children: [
          // Faint light trails behind everything.
          Positioned.fill(
            child: CustomPaint(
              painter: _TrailsPainter(color: scheme.primary.withValues(alpha: 0.20)),
            ),
          ),
          // The glowing AI core, centered.
          Align(
            alignment: Alignment.center,
            child: _Orb(pulse: pulse),
          ),
          // Source-file cards down the left.
          for (var i = 0; i < _files.length; i++)
            Align(
              alignment: Alignment(-1, -0.62 + i * 0.62),
              child: _FloatingFileCard(
                icon: _files[i].$1,
                color: _files[i].$2,
                name: _files[i].$3,
                meta: _files[i].$4,
              ),
            ),
          // Satellite output icons down the right.
          for (var i = 0; i < _sats.length; i++)
            Align(
              alignment: Alignment(1, -0.5 + i * 0.5),
              child: _SatIcon(icon: _sats[i].$1, color: _sats[i].$2),
            ),
        ],
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.pulse});
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final violet = _shiftHue(scheme.primary, -28);
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        final t = pulse.value; // 0..1
        return SizedBox(
          width: 150,
          height: 150,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Expanding pulse ring.
              Container(
                width: 110 + t * 36,
                height: 110 + t * 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.25 * (1 - t)),
                    width: 1.5,
                  ),
                ),
              ),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [violet, scheme.primary],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.35 + t * 0.2),
                      blurRadius: 34,
                      spreadRadius: 2 + t * 4,
                    ),
                  ],
                ),
                child: const Icon(Icons.auto_awesome,
                    color: Colors.white, size: 42),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FloatingFileCard extends StatelessWidget {
  const _FloatingFileCard({
    required this.icon,
    required this.color,
    required this.name,
    required this.meta,
  });

  final IconData icon;
  final Color color;
  final String name;
  final String meta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 168,
      padding: const EdgeInsets.all(CockpitSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(CockpitRadii.sm),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  meta,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 2),
          Icon(Icons.check_circle, size: 16, color: theme.colorScheme.tertiary),
        ],
      ),
    );
  }
}

class _SatIcon extends StatelessWidget {
  const _SatIcon({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

/// Draws faint curved light trails from the centre toward the file cards
/// (left) and satellite icons (right).
class _TrailsPainter extends CustomPainter {
  _TrailsPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    Offset at(double ax, double ay) =>
        Offset((ax + 1) / 2 * size.width, (ay + 1) / 2 * size.height);

    final targets = <Offset>[
      at(-0.75, -0.62), at(-0.75, 0), at(-0.75, 0.62), // left cards
      at(0.86, -0.5), at(0.86, 0), at(0.86, 0.5), // right sats
    ];
    for (final t in targets) {
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..quadraticBezierTo(
          (center.dx + t.dx) / 2,
          center.dy + (t.dy - center.dy) * 0.15,
          t.dx,
          t.dy,
        );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_TrailsPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Live build timeline
// ---------------------------------------------------------------------------

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({
    required this.progress,
    required this.activeStep,
    required this.pulse,
  });

  final double progress;
  final int activeStep;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final steps = _BuildingPageState.steps;

    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
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
              Icon(Icons.auto_awesome, size: 18, color: scheme.primary),
              const SizedBox(width: CockpitSpacing.sm),
              Text(
                'AI is building your study studio',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.md),
          for (var i = 0; i < steps.length; i++)
            _TimelineRow(
              label: steps[i].$1,
              status: progress >= steps[i].$2
                  ? _StepStatus.completed
                  : (i == activeStep
                      ? _StepStatus.inProgress
                      : _StepStatus.pending),
              isLast: i == steps.length - 1,
              pulse: pulse,
            ),
        ],
      ),
    );
  }
}

enum _StepStatus { completed, inProgress, pending }

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.label,
    required this.status,
    required this.isLast,
    required this.pulse,
  });

  final String label;
  final _StepStatus status;
  final bool isLast;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final Widget marker;
    final String trailing;
    final Color labelColor;
    final FontWeight labelWeight;

    switch (status) {
      case _StepStatus.completed:
        marker = Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(color: scheme.tertiary, shape: BoxShape.circle),
          child: const Icon(Icons.check, size: 15, color: Colors.white),
        );
        trailing = 'Completed';
        labelColor = scheme.onSurface;
        labelWeight = FontWeight.w500;
      case _StepStatus.inProgress:
        marker = AnimatedBuilder(
          animation: pulse,
          builder: (context, _) => Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.15 + pulse.value * 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: scheme.primary, width: 2),
            ),
            child: Icon(Icons.graphic_eq, size: 13, color: scheme.primary),
          ),
        );
        trailing = 'In progress...';
        labelColor = scheme.primary;
        labelWeight = FontWeight.w700;
      case _StepStatus.pending:
        marker = Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: scheme.outlineVariant, width: 2),
          ),
        );
        trailing = 'Pending';
        labelColor = scheme.onSurfaceVariant;
        labelWeight = FontWeight.w400;
    }

    final done = status == _StepStatus.completed;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              marker,
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: done
                        ? scheme.tertiary.withValues(alpha: 0.4)
                        : scheme.outlineVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(width: CockpitSpacing.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2, bottom: CockpitSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: labelColor, fontWeight: labelWeight),
                    ),
                  ),
                  Text(
                    trailing,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: status == _StepStatus.inProgress
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                      fontWeight: status == _StepStatus.inProgress
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Live preview cards
// ---------------------------------------------------------------------------

class _LivePreviewRow extends StatelessWidget {
  const _LivePreviewRow({required this.progress});
  final double progress;

  static const _stats = <(IconData, Color, int, String, String)>[
    (Icons.menu_book_rounded, Color(0xFF3B82F6), BuildPreview.topics, 'Topics', 'Identified'),
    (Icons.bookmark_rounded, Color(0xFF30A46C), BuildPreview.definitions, 'Key Definitions', 'Extracted'),
    (Icons.style_rounded, Color(0xFFF76808), BuildPreview.flashcards, 'Flashcards', 'Generated'),
    (Icons.help_rounded, Color(0xFFE5484D), BuildPreview.quizQuestions, 'Quiz Questions', 'Created'),
    (Icons.hub_rounded, Color(0xFF3B82F6), BuildPreview.connections, 'Connections', 'Mapped'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 146,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: _stats.length,
        separatorBuilder: (_, _) => const SizedBox(width: CockpitSpacing.md),
        itemBuilder: (context, i) {
          final s = _stats[i];
          return _StatCard(
            icon: s.$1,
            color: s.$2,
            value: (s.$3 * progress).round(),
            title: s.$4,
            subtitle: s.$5,
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final int value;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 120,
      padding: const EdgeInsets.all(CockpitSpacing.md),
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Text(
            '$value',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: CockpitSpacing.xs),
          Container(
            height: 3,
            width: 28,
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
// Progress + ETA
// ---------------------------------------------------------------------------

class _ProgressSection extends StatelessWidget {
  const _ProgressSection({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final violet = _shiftHue(scheme.primary, -28);
    final pct = (progress * 100).round();
    final remaining = ((1 - progress) * _buildDuration.inSeconds).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                'Building Study Studio...',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '$pct',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.primary,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '%',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: CockpitSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(CockpitRadii.pill),
          child: Stack(
            children: [
              Container(
                height: 10,
                color: scheme.surfaceContainerHighest,
              ),
              FractionallySizedBox(
                widthFactor: progress.clamp(0, 1).toDouble(),
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [violet, scheme.primary]),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: CockpitSpacing.sm),
        Row(
          children: [
            Icon(Icons.schedule, size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: CockpitSpacing.xs),
            Text(
              progress >= 1
                  ? 'Finalizing...'
                  : 'Estimated time remaining: $remaining seconds',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Reassurance note
// ---------------------------------------------------------------------------

class _ReassuranceNote extends StatelessWidget {
  const _ReassuranceNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, size: 20, color: scheme.primary),
          const SizedBox(width: CockpitSpacing.md),
          Expanded(
            child: Text(
              'Your original files remain unchanged. Study Studio creates an '
              'interactive learning environment from copies of your materials.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
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
