import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../domain/entities/studio.dart';
import '../../domain/entities/topic.dart';
import '../format.dart';
import '../widgets/studio_scaffold.dart';

/// Screen 5 — Inside Your Study Studio.
///
/// Not an analytics dashboard: entering a studio should feel like entering the
/// course itself. An AI companion greets the user with a recommendation, the
/// learning modes take centre stage, and small cards resume the last session
/// and surface the knowledge snapshot. Driven entirely by the [Studio] so it
/// works for any course. Same visual language as Screens 1–4 + Outfit.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key, required this.studioId});

  final String studioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(studioProvider(studioId));

    return StudioShell(
      selectedIndex: 1,
      child: SafeArea(
        bottom: false,
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (studio) => isDesktop(context)
              ? _DashboardDesktop(studio: studio)
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: _DashboardBody(studio: studio),
                  ),
                ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Desktop / web layout
// ---------------------------------------------------------------------------

class _DashboardDesktop extends StatelessWidget {
  const _DashboardDesktop({required this.studio});
  final Studio studio;

  @override
  Widget build(BuildContext context) {
    final topics = studio.topics;
    final weakest = topics.isEmpty
        ? null
        : topics.reduce((a, b) => a.mastery <= b.mastery ? a : b);
    final strongest = topics.isEmpty
        ? null
        : topics.reduce((a, b) => a.mastery >= b.mastery ? a : b);
    final connected = topics.isEmpty
        ? null
        : topics.reduce((a, b) =>
            a.relatedTopicIds.length >= b.relatedTopicIds.length ? a : b);
    final base = '/study/${studio.id}';

    // Viewport-fit: the header and AI companion stay pinned at the top; the
    // learning modes (laid out in a fixed 3-column grid) and the resume/snapshot
    // cards fill the rest and only scroll internally on unusually short windows.
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 12, 40, 16),
      child: ContentColumn(
        maxWidth: 1180,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(studio: studio),
            const SizedBox(height: CockpitSpacing.sm),
            _CompanionCard(studio: studio, recommended: weakest, compact: true),
            const SizedBox(height: CockpitSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Choose How You Want to Learn',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => context.go('$base/topics'),
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.chevron_right, size: 18),
                  label: const Text('Explore All'),
                ),
              ],
            ),
            const SizedBox(height: CockpitSpacing.md),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: CockpitSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _LearningModeGrid(
                      studio: studio,
                      recommended: weakest,
                      crossAxisCount: 3,
                    ),
                    const SizedBox(height: CockpitSpacing.sm),
                    if (weakest != null &&
                        strongest != null &&
                        connected != null)
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _ContinueCard(
                                topic: weakest,
                                lastStudied: studio.lastStudied,
                                onTap: () =>
                                    context.go('$base/teach/${weakest.id}'),
                              ),
                            ),
                            const SizedBox(width: CockpitSpacing.lg),
                            Expanded(
                              child: _KnowledgeSnapshot(
                                connected: connected,
                                weakest: weakest,
                                strongest: strongest,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.studio});
  final Studio studio;

  @override
  Widget build(BuildContext context) {
    final base = '/study/${studio.id}';
    final topics = studio.topics;

    // Derive the study companion's recommendation from the real study objects.
    final weakest = topics.isEmpty
        ? null
        : topics.reduce((a, b) => a.mastery <= b.mastery ? a : b);
    final strongest = topics.isEmpty
        ? null
        : topics.reduce((a, b) => a.mastery >= b.mastery ? a : b);
    final connected = topics.isEmpty
        ? null
        : topics.reduce((a, b) =>
            a.relatedTopicIds.length >= b.relatedTopicIds.length ? a : b);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _Header(studio: studio),
        const SizedBox(height: CockpitSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
          child: _CompanionCard(studio: studio, recommended: weakest),
        ),
        const SizedBox(height: CockpitSpacing.xl),
        _SectionHeader(
          title: 'Choose How You Want to Learn',
          trailing: TextButton.icon(
            onPressed: () => context.go('$base/topics'),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.chevron_right, size: 18),
            label: const Text('Explore All'),
          ),
        ),
        const SizedBox(height: CockpitSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
          child: _LearningModeGrid(studio: studio, recommended: weakest),
        ),
        const SizedBox(height: CockpitSpacing.xl),
        if (weakest != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
            child: _ContinueCard(
              topic: weakest,
              lastStudied: studio.lastStudied,
              onTap: () => context.go('$base/teach/${weakest.id}'),
            ),
          ),
        const SizedBox(height: CockpitSpacing.lg),
        if (weakest != null && strongest != null && connected != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
            child: _KnowledgeSnapshot(
              connected: connected,
              weakest: weakest,
              strongest: strongest,
            ),
          ),
        const SizedBox(height: CockpitSpacing.xl),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.studio});
  final Studio studio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CockpitSpacing.md,
        CockpitSpacing.sm,
        CockpitSpacing.md,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CircleButton(
            icon: Icons.arrow_back_ios_new,
            onTap: () => context.go('/study'),
          ),
          const SizedBox(width: CockpitSpacing.xs),
          Expanded(
            child: Column(
              children: [
                Text(
                  studio.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  '${studio.topicCount} Topics  •  ${studio.flashcardCount} '
                  'Flashcards  •  ${studio.quizCount} Quizzes',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: CockpitSpacing.xs),
          _CircleButton(
            icon: Icons.search,
            onTap: () => context.go('/study/${studio.id}/topics'),
          ),
          const SizedBox(width: CockpitSpacing.xs),
          _StudioMenu(studio: studio),
        ],
      ),
    );
  }
}

class _StudioMenu extends StatelessWidget {
  const _StudioMenu({required this.studio});
  final Studio studio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: PopupMenuButton<String>(
        icon: Icon(Icons.more_horiz, size: 20, color: theme.colorScheme.onSurface),
        onSelected: (v) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$v — coming soon')),
        ),
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'Rename', child: Text('Rename')),
          PopupMenuItem(value: 'Duplicate', child: Text('Duplicate')),
          PopupMenuItem(value: 'Export notes', child: Text('Export notes')),
          PopupMenuItem(value: 'Rebuild Studio', child: Text('Rebuild Studio')),
          PopupMenuItem(value: 'Delete', child: Text('Delete')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AI companion hero
// ---------------------------------------------------------------------------

class _CompanionCard extends StatelessWidget {
  const _CompanionCard({
    required this.studio,
    required this.recommended,
    this.compact = false,
  });
  final Studio studio;
  final Topic? recommended;

  /// Desktop packs the companion into a single dense band so the whole studio
  /// fits the viewport without scrolling.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = '/study/${studio.id}';
    final rec = recommended;
    final retention =
        rec == null ? 70 : (40 + (1 - rec.mastery) * 50).clamp(0, 95).round();
    final session = rec?.estimatedStudyTimeMinutes ?? 15;

    if (compact) {
      return Container(
        padding: const EdgeInsets.all(CockpitSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(CockpitRadii.xl),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primary.withValues(alpha: 0.10),
              scheme.secondary.withValues(alpha: 0.06),
            ],
          ),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            const _RobotAvatar(),
            const SizedBox(width: CockpitSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 15, color: scheme.primary),
                      const SizedBox(width: CockpitSpacing.xs),
                      Text(
                        'Welcome back 👋',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Your Study Studio is ready.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  if (rec != null) ...[
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        children: [
                          const TextSpan(text: "You're "),
                          TextSpan(
                            text: '$retention%',
                            style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const TextSpan(text: ' likely to improve by reviewing '),
                          TextSpan(
                            text: rec.title,
                            style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(text: '  •  ~$session min'),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: CockpitSpacing.lg),
            SizedBox(
              width: 196,
              child: _GradientButton(
                icon: Icons.play_circle_outline,
                label: 'Continue Learning',
                onTap: () => context.go(
                  rec != null ? '$base/teach/${rec.id}' : '$base/topics',
                ),
              ),
            ),
            const SizedBox(width: CockpitSpacing.sm),
            _OutlineButton(
              icon: Icons.chat_bubble_outline,
              label: 'Ask AI',
              onTap: () => context.go(
                rec != null ? '$base/teach/${rec.id}' : '$base/topics',
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CockpitRadii.xl),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: 0.10),
            scheme.secondary.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_awesome, size: 16, color: scheme.primary),
                        const SizedBox(width: CockpitSpacing.xs),
                        Text(
                          'Welcome back 👋',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: CockpitSpacing.sm),
                    Text(
                      'Your Study Studio\nis ready.',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800, height: 1.1),
                    ),
                    const SizedBox(height: CockpitSpacing.sm),
                    if (rec != null)
                      Text.rich(
                        TextSpan(
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                          children: [
                            const TextSpan(text: "You're "),
                            TextSpan(
                              text: '$retention%',
                              style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const TextSpan(
                                text: ' likely to improve retention by '
                                    'reviewing '),
                            TextSpan(
                              text: rec.title,
                              style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const TextSpan(text: ' first.'),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: CockpitSpacing.sm),
              const _RobotAvatar(),
            ],
          ),
          const SizedBox(height: CockpitSpacing.md),
          Row(
            children: [
              Icon(Icons.schedule, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: CockpitSpacing.xs),
              Text(
                'Estimated session: $session minutes',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _GradientButton(
                  icon: Icons.play_circle_outline,
                  label: 'Continue Learning',
                  onTap: () => context.go(
                    rec != null ? '$base/teach/${rec.id}' : '$base/topics',
                  ),
                ),
              ),
              const SizedBox(width: CockpitSpacing.md),
              _OutlineButton(
                icon: Icons.chat_bubble_outline,
                label: 'Ask AI',
                onTap: () => context.go(
                  rec != null ? '$base/teach/${rec.id}' : '$base/topics',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RobotAvatar extends StatelessWidget {
  const _RobotAvatar();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final violet = _shiftHue(scheme.primary, -28);
    return Container(
      width: 78,
      height: 78,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [violet, scheme.primary],
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 40),
    );
  }
}

// ---------------------------------------------------------------------------
// Learning modes
// ---------------------------------------------------------------------------

class _LearningModeGrid extends StatelessWidget {
  const _LearningModeGrid({
    required this.studio,
    required this.recommended,
    this.crossAxisCount,
  });
  final Studio studio;
  final Topic? recommended;

  /// When set (desktop), lays the modes out in exactly this many columns so the
  /// whole grid keeps to a fixed number of rows and stays inside the viewport.
  final int? crossAxisCount;

  @override
  Widget build(BuildContext context) {
    final base = '/study/${studio.id}';
    final recId = (recommended ?? studio.topics.firstOrNull)?.id;
    void soon(String label) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label — Phase 2')),
        );

    final modes = <_Mode>[
      _Mode(
        icon: Icons.school_rounded,
        color: const Color(0xFF8B5CF6),
        title: 'Teach Me',
        desc: 'Learn any topic with AI explanations and follow-up questions.',
        count: '${studio.topicCount} topics',
        onTap: () => context.go(
          recId != null ? '$base/teach/$recId' : '$base/topics',
        ),
      ),
      _Mode(
        icon: Icons.help_rounded,
        color: const Color(0xFFE5484D),
        title: 'Quiz Me',
        desc: 'AI-generated quizzes to test your understanding.',
        count: '${studio.quizCount} quizzes',
        onTap: () => context.go('$base/quiz'),
      ),
      _Mode(
        icon: Icons.bolt_rounded,
        color: const Color(0xFFF5A623),
        title: 'Lightning Recall',
        desc: 'Rapid-fire questions for quick recall practice.',
        count: '${studio.flashcardCount + studio.quizCount} questions',
        onTap: () => soon('Lightning Recall'),
      ),
      _Mode(
        icon: Icons.style_rounded,
        color: const Color(0xFF30A46C),
        title: 'Flashcards',
        desc: 'Smart flashcards spaced for long-term retention.',
        count: '${studio.flashcardCount} flashcards',
        onTap: () => context.go('$base/flashcards'),
      ),
      _Mode(
        icon: Icons.theater_comedy_rounded,
        color: const Color(0xFF3B82F6),
        title: 'Scenario Mode',
        desc: 'Real-world scenarios to apply your knowledge.',
        count: '${studio.topicCount} scenarios',
        onTap: () => soon('Scenario Mode'),
      ),
      _Mode(
        icon: Icons.view_in_ar_rounded,
        color: const Color(0xFF7C3AED),
        title: 'Visualize',
        desc: 'Diagrams, concept maps, and interactive visuals.',
        count: '${studio.topicCount} visuals',
        onTap: () => soon('Visualize'),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: modes.length,
      gridDelegate: crossAxisCount != null
          ? SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount!,
              mainAxisSpacing: CockpitSpacing.sm,
              crossAxisSpacing: CockpitSpacing.md,
              mainAxisExtent: 142,
            )
          : const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 230,
              mainAxisSpacing: CockpitSpacing.md,
              crossAxisSpacing: CockpitSpacing.md,
              mainAxisExtent: 188,
            ),
      itemBuilder: (context, i) => _ModeCard(mode: modes[i]),
    );
  }
}

class _Mode {
  const _Mode({
    required this.icon,
    required this.color,
    required this.title,
    required this.desc,
    required this.count,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String desc;
  final String count;
  final VoidCallback onTap;
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.mode});
  final _Mode mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(CockpitRadii.lg),
      child: InkWell(
        onTap: mode.onTap,
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        child: Ink(
          padding: const EdgeInsets.all(CockpitSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CockpitRadii.lg),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: mode.color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(mode.icon, color: mode.color, size: 24),
              ),
              const SizedBox(height: CockpitSpacing.md),
              Text(
                mode.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: CockpitSpacing.xs),
              Expanded(
                child: Text(
                  mode.desc,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(height: CockpitSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      mode.count,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: mode.color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      size: 18, color: theme.colorScheme.onSurfaceVariant),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Continue where you left off
// ---------------------------------------------------------------------------

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.topic,
    required this.lastStudied,
    required this.onTap,
  });
  final Topic topic;
  final DateTime? lastStudied;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pct = (topic.mastery * 100).round();
    return _OutlinedCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(CockpitRadii.sm),
            ),
            child: Icon(Icons.menu_book_rounded, color: scheme.primary, size: 20),
          ),
          const SizedBox(width: CockpitSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Continue Where You Left Off',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(
                  topic.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: CockpitSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(CockpitRadii.pill),
                        child: LinearProgressIndicator(
                          value: topic.mastery.clamp(0, 1).toDouble(),
                          minHeight: 6,
                          backgroundColor: scheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    const SizedBox(width: CockpitSpacing.sm),
                    Text('$pct%',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: CockpitSpacing.xs),
                Row(
                  children: [
                    Icon(Icons.schedule, size: 12, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 3),
                    Text(
                      'Last studied ${relativeDay(lastStudied).toLowerCase()}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.chevron_right, color: scheme.primary, size: 20),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Knowledge snapshot
// ---------------------------------------------------------------------------

class _KnowledgeSnapshot extends StatelessWidget {
  const _KnowledgeSnapshot({
    required this.connected,
    required this.weakest,
    required this.strongest,
  });
  final Topic connected;
  final Topic weakest;
  final Topic strongest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _OutlinedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: CockpitSpacing.sm),
              Expanded(
                child: Text(
                  'Knowledge Snapshot',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              InkWell(
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Knowledge Graph — Phase 2')),
                ),
                child: Row(
                  children: [
                    Text(
                      'View Knowledge Graph',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 16, color: scheme.primary),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _SnapshotMetric(
                  icon: Icons.hub_rounded,
                  iconColor: scheme.primary,
                  label: 'Most Connected Topic',
                  value: connected.title,
                  sub: '${connected.relatedTopicIds.length} connections',
                ),
              ),
              Expanded(
                child: _SnapshotMetric(
                  icon: Icons.trending_down_rounded,
                  iconColor: scheme.error,
                  label: 'Weakest Topic',
                  value: weakest.title,
                  sub: '${(weakest.mastery * 100).round()}% mastery',
                  subColor: scheme.error,
                ),
              ),
              Expanded(
                child: _SnapshotMetric(
                  icon: Icons.trending_up_rounded,
                  iconColor: scheme.tertiary,
                  label: 'Strongest Topic',
                  value: strongest.title,
                  sub: '${(strongest.mastery * 100).round()}% mastery',
                  subColor: scheme.tertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SnapshotMetric extends StatelessWidget {
  const _SnapshotMetric({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.sub,
    this.subColor,
  });
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String sub;
  final Color? subColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: CockpitSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(height: CockpitSpacing.xs),
          Text(
            label,
            maxLines: 2,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 11,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: subColor ?? scheme.onSurfaceVariant,
              fontWeight: subColor != null ? FontWeight.w600 : FontWeight.w400,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: CockpitSpacing.lg, right: CockpitSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _OutlinedCard extends StatelessWidget {
  const _OutlinedCard({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(CockpitRadii.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        child: Ink(
          padding: const EdgeInsets.all(CockpitSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CockpitRadii.lg),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
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
    final violet = _shiftHue(scheme.primary, -28);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CockpitRadii.pill),
            gradient: LinearGradient(colors: [scheme.secondary, violet]),
          ),
          child: SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: CockpitSpacing.sm),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CockpitRadii.pill),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
            child: SizedBox(
              height: 48,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: scheme.onSurface),
                  const SizedBox(width: CockpitSpacing.sm),
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
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
        child: Icon(icon, size: 18, color: theme.colorScheme.onSurface),
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
