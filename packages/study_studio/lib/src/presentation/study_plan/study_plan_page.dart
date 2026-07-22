import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../domain/entities/studio.dart';
import '../../domain/entities/topic.dart';
import '../widgets/studio_scaffold.dart';

class StudyPlanPage extends ConsumerWidget {
  const StudyPlanPage({super.key, required this.studioId});

  final String studioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(studioProvider(studioId));

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isDesktop(context) ? 860 : 480),
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (studio) => _StudyPlanBody(studio: studio),
            ),
          ),
        ),
      ),
      bottomNavigationBar: async.maybeWhen(
        data: (studio) => _BottomActionBar(studio: studio),
        orElse: () => null,
      ),
    );
  }
}

class _StudyPlanBody extends StatelessWidget {
  const _StudyPlanBody({required this.studio});
  final Studio studio;

  @override
  Widget build(BuildContext context) {
    // Weakest topics first = highest priority to study.
    final ranked = [...studio.topics]
      ..sort((a, b) => a.mastery.compareTo(b.mastery));
    final priority = ranked.take(3).toList();
    final top = priority.isNotEmpty ? priority.first : null;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _Header(studio: studio),
        const SizedBox(height: CockpitSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
          child: _NextSessionCard(studio: studio, top: top),
        ),
        const SizedBox(height: CockpitSpacing.xl),
        if (priority.isNotEmpty) ...[
          const _PrioritySectionHeader(),
          const SizedBox(height: CockpitSpacing.sm),
          for (var i = 0; i < priority.length; i++)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CockpitSpacing.lg,
                0,
                CockpitSpacing.lg,
                CockpitSpacing.md,
              ),
              child: _PriorityTopicCard(
                studio: studio,
                topic: priority[i],
                rank: i,
              ),
            ),
          const SizedBox(height: CockpitSpacing.sm),
        ],
        if (top != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
            child: _PlanReasoningRow(studio: studio, top: top),
          ),
        const SizedBox(height: CockpitSpacing.xl),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
          child: _AdaptiveSchedule(studio: studio, ranked: ranked),
        ),
        const SizedBox(height: CockpitSpacing.lg),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
          child: _SmartReminders(),
        ),
        const SizedBox(height: CockpitSpacing.xl),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.studio});
  final Studio studio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
            onTap: () => context.go('/study/${studio.id}'),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  studio.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 14, color: scheme.primary),
                    const SizedBox(width: CockpitSpacing.xs),
                    Text(
                      'AI Study Plan',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: CockpitSpacing.sm),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: CockpitColors.brand.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: CockpitSpacing.xs),
                    Text(
                      'Updated just now',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: CockpitSpacing.xs),
          _CircleButton(
            icon: Icons.calendar_today_outlined,
            onTap: () => _soon(context, 'Calendar'),
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

class _NextSessionCard extends StatelessWidget {
  const _NextSessionCard({required this.studio, required this.top});
  final Studio studio;
  final Topic? top;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final currentPct = (studio.overallMastery * 100).round();
    final goalPct = (currentPct + 11).clamp(0, 100);
    final gain = goalPct - currentPct;
    final sessionMin = _planSteps(
      top,
    ).fold<int>(0, (s, step) => s + step.minutes);

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
              const _RobotAvatar(),
              const SizedBox(width: CockpitSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TagChip(
                      label: 'AI RECOMMENDATION',
                      icon: Icons.auto_awesome,
                      color: scheme.primary,
                    ),
                    const SizedBox(height: CockpitSpacing.sm),
                    Text(
                      'Your Next Best Study Session',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: CockpitSpacing.xs),
                    Text(
                      "Based on your performance, I've created a personalized "
                      'plan to maximize your mastery.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: CockpitSpacing.sm),
              ProgressRing(
                value: studio.overallMastery,
                size: 74,
                stroke: 7,
                label: '$currentPct%',
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  icon: Icons.schedule,
                  label: 'Estimated Session',
                  value: '$sessionMin min',
                ),
              ),
              Expanded(
                child: _MiniStat(
                  icon: Icons.trending_up_rounded,
                  label: 'Potential Gain',
                  value: '+$gain%',
                  valueColor: CockpitColors.brand.success,
                ),
              ),
              Expanded(
                child: _MiniStat(
                  icon: Icons.flag_outlined,
                  label: 'Goal',
                  value: '$currentPct% → $goalPct%',
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.lg),
          _GradientButton(
            icon: Icons.play_arrow_rounded,
            label: "Start Today's Plan",
            trailingArrow: true,
            onTap: () => context.go(
              top != null
                  ? '/study/${studio.id}/teach/${top!.id}'
                  : '/study/${studio.id}/topics',
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
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
        Icon(icon, size: 15, color: scheme.onSurfaceVariant),
        const SizedBox(height: CockpitSpacing.xs),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _PrioritySectionHeader extends StatelessWidget {
  const _PrioritySectionHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Priority Topics',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: CockpitSpacing.xs),
                    Icon(
                      Icons.info_outline,
                      size: 15,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
                Text(
                  'Focus on these areas to improve fastest.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          _OutlinePill(
            icon: Icons.refresh_rounded,
            label: 'Recalculate Plan',
            onTap: () => _soon(context, 'Recalculate Plan'),
          ),
        ],
      ),
    );
  }
}

class _PriorityTopicCard extends StatelessWidget {
  const _PriorityTopicCard({
    required this.studio,
    required this.topic,
    required this.rank,
  });
  final Studio studio;
  final Topic topic;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = _rankColor(scheme, rank);
    final isHigh = rank < 2;
    final masteryPct = (topic.mastery * 100).round();
    final reason = topic.commonMistakes.isNotEmpty
        ? topic.commonMistakes.first
        : 'Connected to ${topic.relatedTopicIds.length} other concepts.';

    return Material(
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(CockpitRadii.lg),
      child: InkWell(
        onTap: () => context.go('/study/${studio.id}/teach/${topic.id}'),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CockpitRadii.lg),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: accent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(CockpitSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: accent,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${rank + 1}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.onPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
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
                                          topic.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: CockpitSpacing.sm),
                                      TagChip(
                                        label: isHigh
                                            ? 'High Priority'
                                            : 'Medium Priority',
                                        color: accent,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: CockpitSpacing.xs),
                                  Text(
                                    reason,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      height: 1.25,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: CockpitSpacing.md),
                        Row(
                          children: [
                            Expanded(
                              child: _InlineMetric(
                                icon: Icons.schedule,
                                value: '${topic.estimatedStudyTimeMinutes} min',
                                label: 'Estimated Time',
                              ),
                            ),
                            Expanded(
                              child: _InlineMetric(
                                icon: Icons.bar_chart_rounded,
                                value: '$masteryPct%',
                                label: 'Mastery',
                              ),
                            ),
                            Expanded(
                              child: _InlineMetric(
                                icon: Icons.hub_outlined,
                                value:
                                    'Impacts ${topic.relatedTopicIds.length}',
                                label: 'other concepts',
                              ),
                            ),
                            _OutlinePill(
                              label: 'Start',
                              trailingArrow: true,
                              onTap: () => context.go(
                                '/study/${studio.id}/teach/${topic.id}',
                              ),
                            ),
                          ],
                        ),
                      ],
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

class _InlineMetric extends StatelessWidget {
  const _InlineMetric({
    required this.icon,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: CockpitSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: CockpitSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 10,
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

class _PlanReasoningRow extends StatelessWidget {
  const _PlanReasoningRow({required this.studio, required this.top});
  final Studio studio;
  final Topic top;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _LearningPathCard(top: top)),
        const SizedBox(width: CockpitSpacing.md),
        Expanded(
          child: Column(
            children: [
              _AiReasoningCard(studio: studio, top: top),
              const SizedBox(height: CockpitSpacing.md),
              _WeeklyGoalCard(studio: studio),
            ],
          ),
        ),
      ],
    );
  }
}

class _LearningPathCard extends StatelessWidget {
  const _LearningPathCard({required this.top});
  final Topic top;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final steps = _planSteps(top);
    return _OutlinedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recommended Learning Path',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            "Here's how I recommend you study ${top.title}.",
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: CockpitSpacing.md),
          for (var i = 0; i < steps.length; i++) ...[
            _PathStepRow(step: steps[i], index: i),
            if (i != steps.length - 1)
              const SizedBox(height: CockpitSpacing.md),
          ],
          const SizedBox(height: CockpitSpacing.md),
          _OutlinePill(
            label: 'Preview All Steps',
            trailingArrow: true,
            fullWidth: true,
            onTap: () => _soon(context, 'Preview All Steps'),
          ),
        ],
      ),
    );
  }
}

class _PathStepRow extends StatelessWidget {
  const _PathStepRow({required this.step, required this.index});
  final _PlanStep step;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Text(
            '${index + 1}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: CockpitSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.title,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                step.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: CockpitSpacing.xs),
        Text(
          '${step.minutes} min',
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _AiReasoningCard extends StatelessWidget {
  const _AiReasoningCard({required this.studio, required this.top});
  final Studio studio;
  final Topic top;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final byId = {for (final t in studio.topics) t.id: t};
    final related = top.relatedTopicIds
        .map((id) => byId[id]?.title)
        .whereType<String>()
        .take(3)
        .toList();

    return _OutlinedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 15, color: scheme.primary),
              const SizedBox(width: CockpitSpacing.xs),
              Text(
                'AI Reasoning',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Text(
            'Why this order?',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Improving ${top.title} first builds a strong foundation and '
            'strengthens these connected concepts.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.3,
            ),
          ),
          if (related.isNotEmpty) ...[
            const SizedBox(height: CockpitSpacing.sm),
            Wrap(
              spacing: CockpitSpacing.xs,
              runSpacing: CockpitSpacing.xs,
              children: [for (final r in related) TagChip(label: r)],
            ),
          ],
          const SizedBox(height: CockpitSpacing.md),
          Container(
            padding: const EdgeInsets.all(CockpitSpacing.md),
            decoration: BoxDecoration(
              color: CockpitColors.brand.success.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(CockpitRadii.md),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.trending_up_rounded,
                  size: 16,
                  color: CockpitColors.brand.success,
                ),
                const SizedBox(width: CockpitSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.2,
                          ),
                          children: [
                            TextSpan(
                              text: '+8% ',
                              style: TextStyle(
                                color: CockpitColors.brand.success,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const TextSpan(text: 'overall mastery'),
                          ],
                        ),
                      ),
                      Text(
                        '+${related.length} stronger concept connections',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
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

class _WeeklyGoalCard extends StatelessWidget {
  const _WeeklyGoalCard({required this.studio});
  final Studio studio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const done = 3;
    const target = 5;
    final readiness = (studio.overallMastery * 100).round().clamp(0, 100);
    return _OutlinedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Weekly Goal',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: CockpitSpacing.xs),
              Expanded(
                child: Text(
                  '$target sessions/week',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.md),
          Row(
            children: [
              ProgressRing(
                value: done / target,
                size: 56,
                stroke: 6,
                label: '$done/$target',
              ),
              const SizedBox(width: CockpitSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estimated Exam Readiness',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '$readiness%',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: CockpitColors.brand.success,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdaptiveSchedule extends StatelessWidget {
  const _AdaptiveSchedule({required this.studio, required this.ranked});
  final Studio studio;
  final List<Topic> ranked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final days = _buildDays(ranked);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Adaptive Schedule',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          'Your personalized roadmap',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: CockpitSpacing.md),
        SizedBox(
          height: 118,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: days.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: CockpitSpacing.md),
            itemBuilder: (context, i) =>
                _DayCard(day: days[i], isToday: i == 0),
          ),
        ),
      ],
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.day, required this.isToday});
  final _ScheduleDay day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: 132,
      padding: const EdgeInsets.all(CockpitSpacing.md),
      decoration: BoxDecoration(
        color: isToday
            ? scheme.primary.withValues(alpha: 0.08)
            : scheme.surface,
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        border: Border.all(
          color: isToday
              ? scheme.primary.withValues(alpha: 0.40)
              : scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            day.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: isToday ? scheme.primary : scheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Text(
            day.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${day.minutes} min',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Align(
            alignment: Alignment.centerRight,
            child: Icon(
              isToday ? Icons.play_circle_fill_rounded : Icons.event_outlined,
              size: 22,
              color: isToday ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmartReminders extends StatelessWidget {
  const _SmartReminders();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const reminders = <(IconData, String, String)>[
      (Icons.timer_outlined, 'Review in 2 hours', 'Best time for retention'),
      (
        Icons.notifications_active_outlined,
        'Daily at 7:00 PM',
        'Your study time',
      ),
      (Icons.school_outlined, 'Before your exam', 'Maximize readiness'),
    ];
    return _OutlinedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.notifications_none_rounded,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: CockpitSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Smart Reminders',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      "We'll help you stay consistent.",
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.md),
          Wrap(
            spacing: CockpitSpacing.sm,
            runSpacing: CockpitSpacing.sm,
            children: [
              for (final r in reminders)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CockpitSpacing.md,
                    vertical: CockpitSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(CockpitRadii.md),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(r.$1, size: 15, color: scheme.primary),
                      const SizedBox(width: CockpitSpacing.sm),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.$2,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            r.$3,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({required this.studio});
  final Studio studio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final top = ([
      ...studio.topics,
    ]..sort((a, b) => a.mastery.compareTo(b.mastery))).firstOrNull;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(CockpitSpacing.md),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: [
              _OutlinePill(
                icon: Icons.tune_rounded,
                label: 'Customize',
                onTap: () => _soon(context, 'Customize Plan'),
              ),
              const SizedBox(width: CockpitSpacing.sm),
              Expanded(
                child: _GradientButton(
                  icon: Icons.play_arrow_rounded,
                  label: "Start Today's Plan",
                  onTap: () => context.go(
                    top != null
                        ? '/study/${studio.id}/teach/${top.id}'
                        : '/study/${studio.id}/topics',
                  ),
                ),
              ),
              const SizedBox(width: CockpitSpacing.sm),
              _OutlinePill(
                icon: Icons.skip_next_rounded,
                label: 'Skip',
                onTap: () => _soon(context, 'Skip Today'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanStep {
  const _PlanStep(this.title, this.subtitle, this.minutes);
  final String title;
  final String subtitle;
  final int minutes;
}

// Mock steps for the recommended learning path.
List<_PlanStep> _planSteps(Topic? top) {
  final cards = top?.flashcards.length ?? 8;
  return [
    const _PlanStep('Teach Me', 'Understand the concept deeply', 5),
    _PlanStep('Flashcards', 'Review key points ($cards cards)', 8),
    const _PlanStep('Scenario Mode', 'Apply in a real-world scenario', 7),
    const _PlanStep('Lightning Recall', '10 rapid recall questions', 5),
  ];
}

class _ScheduleDay {
  const _ScheduleDay(this.label, this.title, this.minutes);
  final String label;
  final String title;
  final int minutes;
}

List<_ScheduleDay> _buildDays(List<Topic> ranked) {
  const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  const months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];
  final now = DateTime.now();
  String labelFor(int i) {
    if (i == 0) return 'TODAY';
    if (i == 1) return 'TOMORROW';
    final d = now.add(Duration(days: i));
    return '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
  }

  final days = <_ScheduleDay>[];
  for (var i = 0; i < 3 && i < ranked.length; i++) {
    days.add(
      _ScheduleDay(
        labelFor(days.length),
        ranked[i].title,
        ranked[i].estimatedStudyTimeMinutes,
      ),
    );
  }
  days.add(_ScheduleDay(labelFor(days.length), 'Mixed Review', 25));
  days.add(_ScheduleDay(labelFor(days.length), 'Mock Exam', 30));
  return days;
}

Color _rankColor(ColorScheme scheme, int rank) {
  switch (rank) {
    case 0:
      return scheme.error;
    case 1:
      return Color.lerp(scheme.error, scheme.tertiary, 0.5)!;
    default:
      return scheme.tertiary;
  }
}

void _soon(BuildContext context, String label) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('$label — coming soon')));
}

class _RobotAvatar extends StatelessWidget {
  const _RobotAvatar();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final violet = _shiftHue(scheme.primary, -28);
    return Container(
      width: 64,
      height: 64,
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
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 32),
    );
  }
}

class _OutlinedCard extends StatelessWidget {
  const _OutlinedCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: child,
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailingArrow = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool trailingArrow;

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
                if (trailingArrow) ...[
                  const SizedBox(width: CockpitSpacing.sm),
                  const Icon(
                    Icons.arrow_forward,
                    color: Colors.white,
                    size: 18,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlinePill extends StatelessWidget {
  const _OutlinePill({
    required this.label,
    required this.onTap,
    this.icon,
    this.trailingArrow = false,
    this.fullWidth = false,
  });
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool trailingArrow;
  final bool fullWidth;

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
            padding: const EdgeInsets.symmetric(
              horizontal: CockpitSpacing.md,
              vertical: CockpitSpacing.sm,
            ),
            child: Row(
              mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: scheme.primary),
                  const SizedBox(width: CockpitSpacing.xs),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (trailingArrow) ...[
                  const SizedBox(width: CockpitSpacing.xs),
                  Icon(Icons.chevron_right, size: 16, color: scheme.primary),
                ],
              ],
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
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: scheme.onSurface),
      ),
    );
  }
}

Color _shiftHue(Color base, double degrees) {
  final hsl = HSLColor.fromColor(base);
  final h = (hsl.hue + degrees) % 360;
  return hsl.withHue(h < 0 ? h + 360 : h).toColor();
}
