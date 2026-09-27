import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../domain/entities/flashcard.dart';
import '../../domain/entities/studio.dart';
import '../../domain/entities/topic.dart';
import '../format.dart';
import '../widgets/mobile_layout.dart';
import '../widgets/studio_palette.dart';
import '../widgets/studio_scaffold.dart';

/// Screen 8 — AI Mastery Report.
///
/// Post-session analytics summarising mastery, learning activities, topic
/// breakdown, and a personalised study plan. Every value is derived from the
/// live [Studio] loaded through [studioProvider]; nothing here is hard-coded.
class MasteryReportPage extends ConsumerWidget {
  const MasteryReportPage({super.key, required this.studioId});

  final String studioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(studioProvider(studioId));

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            // Wider on desktop so cards use the space (the topic/skills section
            // already reflows to two columns past ~400px) instead of a narrow
            // sliver with empty side margins.
            constraints: BoxConstraints(
              maxWidth: isDesktop(context) ? 1040 : 480,
            ),
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (studio) => _MasteryReportBody(studio: studio),
            ),
          ),
        ),
      ),
    );
  }
}

class _MasteryReportBody extends StatelessWidget {
  const _MasteryReportBody({required this.studio});

  final Studio studio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = '/study/${studio.id}';

    final mastery = studio.overallMastery;
    final sessionDate = relativeDay(studio.lastStudied ?? studio.updatedAt);
    final topics = [...studio.topics]
      ..sort((a, b) => b.mastery.compareTo(a.mastery));
    final strong = topics.where((t) => t.mastery >= 0.8).toList();
    final weak = studio.weakTopics;
    final minutesToMastery = weak.fold<int>(
      0,
      (sum, t) => sum + t.estimatedStudyTimeMinutes,
    );

    return Column(
      children: [
        _Header(examTitle: studio.title, onBack: () => context.go(base)),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: CockpitSpacing.xl),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: CockpitSpacing.lg,
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'This Studio  •  $sessionDate',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: CockpitSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: CockpitSpacing.md),
                    _MasteryOverview(
                      mastery: mastery,
                      strongCount: strong.length,
                      totalCount: topics.length,
                    ),
                    const SizedBox(height: CockpitSpacing.lg),
                    _AiAssessmentCard(
                      focusTopics: weak,
                      minutesToMastery: minutesToMastery,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: CockpitSpacing.xl),
              Padding(
                padding: const EdgeInsets.only(left: CockpitSpacing.lg),
                child: Text(
                  'Learning Journey',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: CockpitSpacing.md),
              _LearningJourneyRow(studio: studio),
              const SizedBox(height: CockpitSpacing.xl),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: CockpitSpacing.lg,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final byTopic = _MasteryByTopicCard(topics: topics);
                    final confidence = _ConfidencePerformanceCard(
                      strong: strong,
                      weak: weak,
                    );
                    final skills = _SkillsRow(strong: strong, weak: weak);
                    final wide =
                        !isMobilePlatform(context) &&
                        constraints.maxWidth >= 400;
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: byTopic),
                          const SizedBox(width: CockpitSpacing.md),
                          Expanded(
                            flex: 2,
                            child: Column(
                              children: [
                                confidence,
                                const SizedBox(height: CockpitSpacing.md),
                                skills,
                              ],
                            ),
                          ),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        byTopic,
                        const SizedBox(height: CockpitSpacing.md),
                        confidence,
                        const SizedBox(height: CockpitSpacing.md),
                        skills,
                      ],
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: CockpitSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: CockpitSpacing.lg),
                    _StudyPlanCard(weak: weak, mastery: mastery),
                    const SizedBox(height: CockpitSpacing.xl),
                    _GradientButton(
                      icon: Icons.auto_awesome,
                      label: 'Explore Knowledge Graph',
                      trailing: true,
                      onTap: () => context.go('$base/knowledge-graph'),
                    ),
                    const SizedBox(height: CockpitSpacing.md),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => context.go(base),
                        icon: Icon(
                          Icons.menu_book_outlined,
                          color: scheme.primary,
                        ),
                        label: Text(
                          'Continue Studying',
                          style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
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

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.examTitle, required this.onBack});

  final String examTitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    void soon(String label) => ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label — coming soon')));

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
          _CircleButton(icon: Icons.arrow_back_ios_new, onTap: onBack),
          const SizedBox(width: CockpitSpacing.sm),
          Expanded(
            child: Column(
              children: [
                Text(
                  examTitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: CockpitSpacing.xs,
                  children: [
                    Icon(Icons.auto_awesome, size: 14, color: scheme.primary),
                    Text(
                      'AI Mastery Report',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          _CircleButton(icon: Icons.ios_share, onTap: () => soon('Share')),
          const SizedBox(width: CockpitSpacing.xs),
          _CircleButton(
            icon: Icons.more_horiz,
            onTap: () => soon('More options'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mastery overview
// ---------------------------------------------------------------------------

class _MasteryOverview extends StatelessWidget {
  const _MasteryOverview({
    required this.mastery,
    required this.strongCount,
    required this.totalCount,
  });

  final double mastery;
  final int strongCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pct = (mastery * 100).round();
    final (label, color) = _readiness(mastery);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          height: 120,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: CircularProgressIndicator(
                  value: 1,
                  strokeWidth: 10,
                  valueColor: AlwaysStoppedAnimation(
                    scheme.surfaceContainerHighest,
                  ),
                ),
              ),
              SizedBox(
                width: 120,
                height: 120,
                child: CircularProgressIndicator(
                  value: mastery.clamp(0, 1),
                  strokeWidth: 10,
                  strokeCap: StrokeCap.round,
                  valueColor: AlwaysStoppedAnimation(scheme.primary),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$pct%',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Mastery',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: CockpitSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Exam Readiness',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: CockpitSpacing.xs),
              MobileWrap(
                children: [
                  Text(
                    label,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: CockpitSpacing.xs),
                  Icon(Icons.trending_up_rounded, size: 20, color: color),
                ],
              ),
              const SizedBox(height: CockpitSpacing.sm),
              Text(
                'Based on the mastery of every Study Object in this studio.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: CockpitSpacing.md),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: CockpitSpacing.md,
                  vertical: CockpitSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(CockpitRadii.md),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: CockpitSpacing.sm),
                    Expanded(
                      child: Text(
                        '$strongCount of $totalCount topics above 80% mastery',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
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

(String, Color) _readiness(double mastery) {
  if (mastery >= 0.8) return ('High', CockpitColors.brand.success);
  if (mastery >= 0.6) return ('Moderate', CockpitColors.brand.warning);
  return ('Building', CockpitColors.brand.error);
}

// ---------------------------------------------------------------------------
// AI Assessment
// ---------------------------------------------------------------------------

class _AiAssessmentCard extends StatelessWidget {
  const _AiAssessmentCard({
    required this.focusTopics,
    required this.minutesToMastery,
  });

  final List<Topic> focusTopics;
  final int minutesToMastery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasFocus = focusTopics.isNotEmpty;
    final summary = hasFocus
        ? 'Solid progress. Your strongest topics are locked in — a little more '
              'work on the areas below takes you to full mastery.'
        : 'Outstanding — every topic in this studio is above the weak '
              'threshold. Keep reviewing to stay sharp.';

    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CockpitRadii.xl),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: 0.08),
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
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      scheme.primary,
                      scheme.primary.withValues(alpha: 0.75),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.smart_toy_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: CockpitSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Assessment',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: CockpitSpacing.xs),
                    Text(
                      summary,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: CockpitSpacing.sm),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: scheme.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(CockpitRadii.md),
                ),
                child: Icon(
                  Icons.emoji_events_rounded,
                  color: scheme.secondary,
                  size: 32,
                ),
              ),
            ],
          ),
          if (hasFocus) ...[
            const SizedBox(height: CockpitSpacing.lg),
            Text(
              'To reach full mastery, focus on:',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: CockpitSpacing.sm),
            Wrap(
              spacing: CockpitSpacing.sm,
              runSpacing: CockpitSpacing.sm,
              children: [for (final t in focusTopics) TagChip(label: t.title)],
            ),
            const SizedBox(height: CockpitSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: Container(height: 1, color: scheme.outlineVariant),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CockpitSpacing.lg,
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Est. study time',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: CockpitSpacing.xs),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$minutesToMastery min',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: CockpitSpacing.xs),
                          Icon(Icons.schedule, size: 18, color: scheme.primary),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(height: 1, color: scheme.outlineVariant),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Learning journey
// ---------------------------------------------------------------------------

class _LearningJourneyRow extends StatefulWidget {
  const _LearningJourneyRow({required this.studio});

  final Studio studio;

  @override
  State<_LearningJourneyRow> createState() => _LearningJourneyRowState();
}

class _LearningJourneyRowState extends State<_LearningJourneyRow> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final studio = widget.studio;
    final masteredCards = studio.topics
        .expand((t) => t.flashcards)
        .where((f) => f.status == FlashcardStatus.review)
        .length;

    final items = [
      _JourneyItem(
        icon: Icons.menu_book_rounded,
        iconColor: StudyPalette.violet,
        title: 'Study Objects',
        subtitle: '${studio.topicCount}',
        detail: 'Topics',
      ),
      _JourneyItem(
        icon: Icons.help_outline_rounded,
        iconColor: StudyPalette.violet,
        title: 'Quiz Me',
        subtitle: '${studio.quizCount}',
        detail: 'Questions',
      ),
      _JourneyItem(
        icon: Icons.style_rounded,
        iconColor: StudyPalette.violet,
        title: 'Flashcards',
        subtitle: '${studio.flashcardCount}',
        detail: 'Cards',
      ),
      _JourneyItem(
        icon: Icons.check_circle_outline_rounded,
        iconColor: CockpitColors.brand.success,
        title: 'Mastered Cards',
        subtitle: '$masteredCards',
        subtitleColor: CockpitColors.brand.success,
        detail: 'In review',
      ),
      _JourneyItem(
        icon: Icons.local_fire_department_rounded,
        iconColor: CockpitColors.brand.error,
        title: 'Weak Topics',
        subtitle: '${studio.weakTopics.length}',
        subtitleColor: CockpitColors.brand.error,
        detail: 'To review',
      ),
    ];

    if (isMobilePlatform(context)) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            for (final item in items)
              ListTile(
                leading: Icon(item.icon, color: item.iconColor),
                title: Text(item.title),
                subtitle: Text(item.detail ?? ''),
                trailing: Text(item.subtitle),
              ),
          ],
        ),
      );
    }
    return SizedBox(
      height: 108,
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: const EdgeInsets.only(
            left: CockpitSpacing.lg,
            right: CockpitSpacing.lg,
          ),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(width: CockpitSpacing.sm),
                items[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _JourneyItem extends StatelessWidget {
  const _JourneyItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.detail,
    this.subtitleColor,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String? detail;
  final Color? subtitleColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: 100,
      padding: const EdgeInsets.all(CockpitSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const Spacer(),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.labelSmall?.copyWith(
              color: subtitleColor ?? scheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (detail != null)
            Text(
              detail!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mastery by topic
// ---------------------------------------------------------------------------

class _MasteryByTopicCard extends StatelessWidget {
  const _MasteryByTopicCard({required this.topics});

  final List<Topic> topics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final warning = CockpitColors.brand.warning;
    // Show the first handful; the rest live behind "View All".
    final shown = topics.take(7).toList();

    return _OutlinedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mastery by Topic',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: CockpitSpacing.lg),
          if (shown.isEmpty)
            Text(
              'No topics yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          for (final t in shown) ...[
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(CockpitRadii.pill),
                    child: LinearProgressIndicator(
                      value: t.mastery.clamp(0, 1),
                      minHeight: 6,
                      backgroundColor: scheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(
                        t.mastery >= 0.8 ? scheme.primary : warning,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: CockpitSpacing.sm),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${(t.mastery * 100).round()}%',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: CockpitSpacing.sm),
          ],
          if (topics.length > shown.length)
            InkWell(
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Full topic list — coming soon')),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'View All Topics (${topics.length})',
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
    );
  }
}

// ---------------------------------------------------------------------------
// Focus insights (confidence vs performance)
// ---------------------------------------------------------------------------

class _ConfidencePerformanceCard extends StatelessWidget {
  const _ConfidencePerformanceCard({required this.strong, required this.weak});

  final List<Topic> strong;
  final List<Topic> weak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final success = CockpitColors.brand.success;
    final error = CockpitColors.brand.error;
    final topWeak = weak.isNotEmpty ? weak.first : null;
    final topStrong = strong.isNotEmpty ? strong.first : null;

    return _OutlinedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Focus Insights',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: CockpitSpacing.lg),
          if (topWeak != null)
            _InsightRow(
              icon: Icons.warning_amber_rounded,
              iconColor: error,
              title: 'Needs attention: ${topWeak.title}',
              body:
                  'Mastery is at ${(topWeak.mastery * 100).round()}%. '
                  'Prioritise this topic next.',
            ),
          if (topWeak != null && topStrong != null)
            const SizedBox(height: CockpitSpacing.md),
          if (topStrong != null)
            _InsightRow(
              icon: Icons.check_circle_outline_rounded,
              iconColor: success,
              title: 'Strongest: ${topStrong.title}',
              body:
                  'Mastery is at ${(topStrong.mastery * 100).round()}%. '
                  'Keep it fresh with quick reviews.',
            ),
          if (topWeak == null && topStrong == null)
            Text(
              'Complete a few quizzes to unlock personalised insights.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: CockpitSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Skills cards
// ---------------------------------------------------------------------------

class _SkillsRow extends StatelessWidget {
  const _SkillsRow({required this.strong, required this.weak});

  final List<Topic> strong;
  final List<Topic> weak;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _StrongestSkillsCard(topics: strong)),
          const SizedBox(width: CockpitSpacing.sm),
          Expanded(child: _NeedsPracticeCard(topics: weak)),
        ],
      ),
    );
  }
}

class _StrongestSkillsCard extends StatelessWidget {
  const _StrongestSkillsCard({required this.topics});

  final List<Topic> topics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final success = CockpitColors.brand.success;

    return _OutlinedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events_outlined, size: 16, color: success),
              const SizedBox(width: CockpitSpacing.xs),
              Expanded(
                child: Text(
                  'Strongest Skills',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.md),
          if (topics.isEmpty)
            Text(
              'No topics above 80% yet — keep going!',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          for (final t in topics.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: CockpitSpacing.xs),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded, size: 14, color: success),
                  const SizedBox(width: CockpitSpacing.xs),
                  Expanded(
                    child: Text(
                      t.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
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

class _NeedsPracticeCard extends StatelessWidget {
  const _NeedsPracticeCard({required this.topics});

  final List<Topic> topics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final warning = CockpitColors.brand.warning;

    return _OutlinedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.local_fire_department_rounded,
                size: 16,
                color: warning,
              ),
              const SizedBox(width: CockpitSpacing.xs),
              Expanded(
                child: Text(
                  'Needs More Practice',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.md),
          if (topics.isEmpty)
            Text(
              'Nothing weak right now. Great work!',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          for (final t in topics.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: CockpitSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  TextButton(
                    onPressed: () =>
                        context.go('/study/${t.studioId}/topics/${t.id}'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(
                      'Review Now',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
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

// ---------------------------------------------------------------------------
// Study plan
// ---------------------------------------------------------------------------

class _StudyPlanCard extends StatelessWidget {
  const _StudyPlanCard({required this.weak, required this.mastery});

  final List<Topic> weak;
  final double mastery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Build the plan from the weakest topics so the recommendation always
    // reflects real study time from the model.
    final planned = weak.take(3).toList();
    final totalMinutes = planned.fold<int>(
      0,
      (sum, t) => sum + t.estimatedStudyTimeMinutes,
    );
    final target = ((mastery * 100).round() + 4).clamp(0, 100);

    return _OutlinedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MobileWrap(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: CockpitSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Personalized Study Plan',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Recommended next session',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Icon(Icons.schedule_rounded, size: 28, color: scheme.primary),
                  Text(
                    '$totalMinutes min',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Estimated Session Time',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.lg),
          if (planned.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: CockpitSpacing.sm),
              child: Text(
                'All topics are in good shape — a light review keeps them sharp.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final t in planned)
            Padding(
              padding: const EdgeInsets.only(bottom: CockpitSpacing.sm),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: CockpitSpacing.md),
                  Expanded(
                    child: Text(
                      '${t.title} review',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    '${t.estimatedStudyTimeMinutes} min',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: CockpitSpacing.sm),
          Row(
            children: [
              Icon(Icons.trending_up_rounded, size: 16, color: scheme.primary),
              const SizedBox(width: CockpitSpacing.xs),
              Expanded(
                child: Text(
                  'Target: Raise mastery to $target%+',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _OutlinedCard extends StatelessWidget {
  const _OutlinedCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: child,
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

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CockpitRadii.pill),
            gradient: LinearGradient(
              colors: [scheme.secondary, StudyPalette.violet],
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!trailing) ...[
                  Icon(icon, color: Colors.white, size: 18),
                  const SizedBox(width: CockpitSpacing.sm),
                ],
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
                if (trailing) ...[
                  const SizedBox(width: CockpitSpacing.sm),
                  Icon(icon, color: Colors.white, size: 18),
                  const Text(' →', style: TextStyle(color: Colors.white)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
