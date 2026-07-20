import 'dart:math' as math;

import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/mock/mock_data.dart';

/// Screen 16 — Study Analytics.
///
/// All values come from [studyAnalyticsMockData]. The charts are intentionally
/// drawn in-package so this mock-only screen does not add a chart dependency.
class StudyAnalyticsPage extends StatefulWidget {
  const StudyAnalyticsPage({super.key, required this.studioId});

  final String studioId;

  @override
  State<StudyAnalyticsPage> createState() => _StudyAnalyticsPageState();
}

enum _AnalyticsPeriod { week, month, allTime }

class _StudyAnalyticsPageState extends State<StudyAnalyticsPage> {
  _AnalyticsPeriod _period = _AnalyticsPeriod.month;

  void _soon(String label) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label — coming soon')));
  }

  @override
  Widget build(BuildContext context) {
    final data = studyAnalyticsMockData;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                CockpitSpacing.md,
                CockpitSpacing.sm,
                CockpitSpacing.md,
                CockpitSpacing.sm,
              ),
              child: Column(
                children: [
                  _AnalyticsHeader(
                    title: data.studioTitle,
                    onBack: () => context.go('/study/${widget.studioId}'),
                    onCalendar: () => _soon('Calendar'),
                    onMore: () => _soon('More options'),
                  ),
                  const SizedBox(height: CockpitSpacing.sm),
                  _PeriodSelector(
                    value: _period,
                    onChanged: (value) => setState(() => _period = value),
                  ),
                  const SizedBox(height: CockpitSpacing.sm),
                  _OverallMasteryCard(data: data),
                  const SizedBox(height: CockpitSpacing.sm),
                  SizedBox(
                    height: 330,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _StudyActivityCard(data: data)),
                        const SizedBox(width: CockpitSpacing.sm),
                        Expanded(child: _PerformanceTrendsCard(data: data)),
                      ],
                    ),
                  ),
                  const SizedBox(height: CockpitSpacing.sm),
                  SizedBox(
                    height: 330,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _RetentionCard(data: data)),
                        const SizedBox(width: CockpitSpacing.sm),
                        Expanded(child: _TimeSpentCard(data: data)),
                      ],
                    ),
                  ),
                  const SizedBox(height: CockpitSpacing.sm),
                  _AchievementsCard(data: data),
                  const SizedBox(height: CockpitSpacing.sm),
                  SizedBox(
                    height: 190,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Expanded(child: _AiInsightsCard()),
                        const SizedBox(width: CockpitSpacing.sm),
                        Expanded(child: _ReadinessCard(mastery: data.mastery)),
                      ],
                    ),
                  ),
                  const SizedBox(height: CockpitSpacing.sm),
                  SizedBox(
                    height: 58,
                    child: Row(
                      children: [
                        Expanded(
                          flex: 10,
                          child: _FooterButton(
                            icon: Icons.menu_book_outlined,
                            label: 'Continue Learning',
                            onTap: () =>
                                context.go('/study/${widget.studioId}'),
                          ),
                        ),
                        const SizedBox(width: CockpitSpacing.sm),
                        Expanded(
                          flex: 13,
                          child: _FooterButton(
                            icon: Icons.auto_awesome,
                            label: 'View AI Study Plan',
                            filled: true,
                            onTap: () => _soon('AI Study Plan'),
                          ),
                        ),
                        const SizedBox(width: CockpitSpacing.sm),
                        Expanded(
                          flex: 10,
                          child: _FooterButton(
                            icon: Icons.share_outlined,
                            label: 'Share Progress',
                            onTap: () => _soon('Share Progress'),
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
    );
  }
}

class _AnalyticsHeader extends StatelessWidget {
  const _AnalyticsHeader({
    required this.title,
    required this.onBack,
    required this.onCalendar,
    required this.onMore,
  });

  final String title;
  final VoidCallback onBack;
  final VoidCallback onCalendar;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      height: 73,
      child: Row(
        children: [
          _RoundIconButton(icon: Icons.chevron_left, onTap: onBack),
          const SizedBox(width: CockpitSpacing.md),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: CockpitSpacing.xs),
                Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 13, color: scheme.primary),
                    const SizedBox(width: CockpitSpacing.xs),
                    Text(
                      'Study Analytics',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _RoundIconButton(
            icon: Icons.calendar_month_outlined,
            onTap: onCalendar,
          ),
          const SizedBox(width: CockpitSpacing.sm),
          _RoundIconButton(icon: Icons.more_horiz, onTap: onMore),
        ],
      ),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.value, required this.onChanged});

  final _AnalyticsPeriod value;
  final ValueChanged<_AnalyticsPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const labels = {
      _AnalyticsPeriod.week: 'Week',
      _AnalyticsPeriod.month: 'Month',
      _AnalyticsPeriod.allTime: 'All Time',
    };
    return Center(
      child: Container(
        width: 150,
        height: 43,
        padding: const EdgeInsets.all(CockpitSpacing.xxs),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(CockpitRadii.sm),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            for (final period in _AnalyticsPeriod.values)
              Expanded(
                child: InkWell(
                  onTap: () => onChanged(period),
                  borderRadius: BorderRadius.circular(CockpitRadii.sm),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: value == period
                          ? scheme.surface
                          : scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(CockpitRadii.sm),
                      boxShadow: value == period
                          ? [
                              BoxShadow(
                                color: scheme.shadow.withValues(alpha: 0.08),
                                blurRadius: 4,
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      labels[period]!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: value == period
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: value == period
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OverallMasteryCard extends StatelessWidget {
  const _OverallMasteryCard({required this.data});

  final StudyAnalyticsMockData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _AnalyticsSurface(
      height: 206,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 112,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CardTitle('Overall Mastery'),
                const SizedBox(height: CockpitSpacing.xs),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '${data.mastery}'),
                      const TextSpan(text: '%', style: TextStyle(fontSize: 17)),
                    ],
                  ),
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: scheme.primary,
                    fontSize: 31,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
                const SizedBox(height: CockpitSpacing.xs),
                Row(
                  children: [
                    Icon(
                      Icons.trending_up,
                      size: 13,
                      color: CockpitColors.brand.success,
                    ),
                    const SizedBox(width: CockpitSpacing.xs),
                    Expanded(
                      child: Text(
                        '+18% this month',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: CockpitColors.brand.success,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  'vs last month (${data.previousMastery}%)',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(
                    horizontal: CockpitSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(CockpitRadii.sm),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      Image.asset(
                        'assets/images/ai_study_companion.png',
                        package: 'study_studio',
                        width: 22,
                        height: 22,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: CockpitSpacing.xs),
                      Expanded(
                        child: Text(
                          "You're progressing faster\nthan your previous pace!",
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 11,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          Expanded(
            child: CustomPaint(
              painter: _LineChartPainter(
                values: data.masteryTrend,
                color: scheme.primary,
                gridColor: scheme.outlineVariant,
                labelColor: scheme.onSurfaceVariant,
                fill: true,
                endBadge: '${data.mastery}%',
                xLabels: const [
                  'Apr 18',
                  'Apr 25',
                  'May 2',
                  'May 9',
                  'May 16',
                  'May 18',
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StudyActivityCard extends StatelessWidget {
  const _StudyActivityCard({required this.data});

  final StudyAnalyticsMockData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final palette = [
      scheme.surfaceContainerHighest,
      scheme.primary.withValues(alpha: 0.22),
      scheme.primary.withValues(alpha: 0.48),
      scheme.primary,
      CockpitColors.brand.success,
    ];
    return _AnalyticsSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Study Activity', info: true),
          const SizedBox(height: CockpitSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(left: 17),
            child: Row(
              children: const [
                Expanded(child: _TinyText('Apr 21')),
                Expanded(child: _TinyText('Apr 28')),
                Expanded(child: _TinyText('May 5')),
                Expanded(child: _TinyText('May 12')),
                Expanded(child: _TinyText('May 18')),
              ],
            ),
          ),
          const SizedBox(height: CockpitSpacing.xs),
          for (var row = 0; row < data.studyActivity.length; row++)
            Expanded(
              child: Row(
                children: [
                  SizedBox(width: 13, child: _TinyText('MTWTFSS'[row])),
                  for (final level in data.studyActivity[row])
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.all(1.2),
                        decoration: BoxDecoration(
                          color: palette[level],
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: CockpitSpacing.xs),
          Wrap(
            spacing: CockpitSpacing.md,
            runSpacing: CockpitSpacing.xs,
            children: [
              _LegendDot(label: 'Long (60m+)', color: scheme.primary),
              _LegendDot(
                label: 'Medium (20–60m)',
                color: CockpitColors.brand.success,
              ),
              _LegendDot(
                label: 'Short (<20m)',
                color: CockpitColors.brand.warning,
              ),
              _LegendDot(
                label: 'No study',
                color: scheme.surfaceContainerHighest,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PerformanceTrendsCard extends StatelessWidget {
  const _PerformanceTrendsCard({required this.data});

  final StudyAnalyticsMockData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = [
      scheme.primary,
      scheme.secondary,
      CockpitColors.brand.success,
      CockpitColors.brand.warning,
      _shiftHue(scheme.error, -18),
    ];
    return _AnalyticsSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: _CardTitle('Performance Trends', info: true),
              ),
              Container(
                height: 20,
                padding: const EdgeInsets.symmetric(
                  horizontal: CockpitSpacing.sm,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(CockpitRadii.sm),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    const _TinyText('Mastery'),
                    const SizedBox(width: CockpitSpacing.sm),
                    Icon(Icons.expand_more, size: 13, color: scheme.primary),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.xs),
          Expanded(
            child: _FullSizeChart(
              key: const ValueKey('study-analytics-performance-chart'),
              painter: _MultiLineChartPainter(
                series: data.performanceSeries,
                colors: colors,
                gridColor: scheme.outlineVariant,
                labelColor: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: CockpitSpacing.xs),
          Wrap(
            spacing: CockpitSpacing.sm,
            runSpacing: CockpitSpacing.xs,
            children: [
              for (var i = 0; i < data.performanceSeries.length; i++)
                _LegendDot(
                  label: data.performanceSeries[i].label,
                  color: colors[i],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RetentionCard extends StatelessWidget {
  const _RetentionCard({required this.data});

  final StudyAnalyticsMockData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _AnalyticsSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardTitle('Retention Curve', info: true),
          const SizedBox(height: CockpitSpacing.xs),
          Expanded(
            child: _FullSizeChart(
              key: const ValueKey('study-analytics-retention-chart'),
              painter: _LineChartPainter(
                values: data.retention,
                color: scheme.primary,
                gridColor: scheme.outlineVariant,
                labelColor: scheme.onSurfaceVariant,
                fill: true,
                endBadge: '76%',
                highlightBadge: '91%',
                xLabels: const ['Today', 'Day 3', 'Day 7', 'Day 14', 'May 18'],
              ),
            ),
          ),
          Container(
            height: 53,
            padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.sm),
            color: scheme.surfaceContainerLowest,
            child: Row(
              children: [
                Expanded(
                  child: _RetentionStat(
                    label: 'Current Retention',
                    value: '91%',
                    color: scheme.primary,
                  ),
                ),
                VerticalDivider(width: 8, color: scheme.outlineVariant),
                Expanded(
                  child: _RetentionStat(
                    label: 'Without review, it drops to',
                    value: '76% in 6 days',
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: CockpitSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.event_note_outlined, size: 13, color: scheme.primary),
              const SizedBox(width: CockpitSpacing.xs),
              Expanded(
                child: Text(
                  'Recommended review:  Tomorrow',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    fontSize: 11,
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

class _TimeSpentCard extends StatelessWidget {
  const _TimeSpentCard({required this.data});

  final StudyAnalyticsMockData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = [
      scheme.primary,
      scheme.secondary,
      CockpitColors.brand.success,
      CockpitColors.brand.warning,
      _shiftHue(scheme.error, -18),
      scheme.outline,
    ];
    final icons = [
      Icons.school_outlined,
      Icons.quiz_outlined,
      Icons.style_outlined,
      Icons.bolt,
      Icons.track_changes,
      Icons.more_horiz,
    ];
    return _AnalyticsSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Time Spent by Activity', info: true),
          const SizedBox(height: CockpitSpacing.sm),
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: 67,
                  height: 114,
                  child: CustomPaint(
                    painter: _DonutPainter(colors: colors),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Text(
                            '28h 45m',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          _TinyText('Total'),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: CockpitSpacing.xs),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (var i = 0; i < data.activityBreakdown.length; i++)
                        Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: colors[i].withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(
                                  CockpitRadii.sm,
                                ),
                              ),
                              child: Icon(icons[i], size: 13, color: colors[i]),
                            ),
                            const SizedBox(width: CockpitSpacing.xxs),
                            Expanded(
                              child: Text(
                                data.activityBreakdown[i].label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                            SizedBox(
                              width: 25,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _TinyText(data.activityBreakdown[i].value),
                                  _TinyText(data.activityBreakdown[i].detail),
                                ],
                              ),
                            ),
                          ],
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

class _AchievementsCard extends StatelessWidget {
  const _AchievementsCard({required this.data});

  final StudyAnalyticsMockData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = [
      scheme.primary,
      CockpitColors.brand.success,
      scheme.secondary,
      CockpitColors.brand.warning,
      _shiftHue(scheme.error, -18),
    ];
    const icons = [
      Icons.local_fire_department,
      Icons.menu_book,
      Icons.psychology,
      Icons.track_changes,
      Icons.emoji_events,
    ];
    return _AnalyticsSurface(
      height: 145,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Achievements', info: true),
          const SizedBox(height: CockpitSpacing.xs),
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < data.achievements.length; i++) ...[
                  if (i > 0) const SizedBox(width: CockpitSpacing.xs),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(CockpitSpacing.xxs),
                      decoration: BoxDecoration(
                        color: colors[i].withValues(alpha: 0.035),
                        borderRadius: BorderRadius.circular(CockpitRadii.sm),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Column(
                        children: [
                          Icon(icons[i], size: 13, color: colors[i]),
                          Text(
                            data.achievements[i].value,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  height: 1.1,
                                ),
                          ),
                          Expanded(
                            child: Center(
                              child: Text(
                                data.achievements[i].label,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(fontSize: 11, height: 1),
                              ),
                            ),
                          ),
                          Text(
                            data.achievements[i].detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AiInsightsCard extends StatelessWidget {
  const _AiInsightsCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = [
      (
        Icons.schedule,
        scheme.primary,
        "You're most accurate when studying\nbetween 7–9 PM.",
      ),
      (
        Icons.trending_up,
        scheme.primary,
        'Lightning Recall improves your\nquiz scores by 14%.',
      ),
      (
        Icons.track_changes,
        CockpitColors.brand.warning,
        'Scenario Mode has become your\nstrongest learning method.',
      ),
    ];
    return _AnalyticsSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('AI Insights', info: true),
          const SizedBox(height: CockpitSpacing.xs),
          for (final item in items)
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(bottom: CockpitSpacing.xs),
                padding: const EdgeInsets.symmetric(
                  horizontal: CockpitSpacing.xs,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(CockpitRadii.sm),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(item.$1, size: 13, color: item.$2),
                    const SizedBox(width: CockpitSpacing.sm),
                    Expanded(
                      child: Text(
                        item.$3,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 11,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Text(
            'View All Insights     ›',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.primary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({required this.mastery});

  final int mastery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _AnalyticsSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Predictive Exam Readiness', info: true),
          const SizedBox(height: CockpitSpacing.sm),
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: 78,
                  height: 133,
                  child: CustomPaint(
                    painter: _RingPainter(
                      value: 0.96,
                      color: CockpitColors.brand.success,
                      background: scheme.surfaceContainerHighest,
                    ),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '96%',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
                          _TinyText('Ready'),
                        ],
                      ),
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
                          const Expanded(child: _TinyText('Confidence Level')),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: CockpitSpacing.sm,
                              vertical: CockpitSpacing.xxs,
                            ),
                            decoration: BoxDecoration(
                              color: CockpitColors.brand.success.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(
                                CockpitRadii.pill,
                              ),
                            ),
                            child: Text(
                              'High',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: CockpitColors.brand.success,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      const _TinyText('Suggested remaining\npreparation'),
                      Text(
                        '18 min',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: CockpitColors.brand.success,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.auto_awesome,
                size: 13,
                color: CockpitColors.brand.success,
              ),
              const SizedBox(width: CockpitSpacing.xs),
              Expanded(
                child: Text(
                  "You're right on track to ace your exam!",
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: CockpitColors.brand.success,
                    fontSize: 11,
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

class _AnalyticsSurface extends StatelessWidget {
  const _AnalyticsSurface({required this.child, this.height});

  final Widget child;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      padding: const EdgeInsets.all(CockpitSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.025),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _FullSizeChart extends StatelessWidget {
  const _FullSizeChart({super.key, required this.painter});

  final CustomPainter painter;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        assert(constraints.hasBoundedWidth && constraints.hasBoundedHeight);
        final chartSize = Size(constraints.maxWidth, constraints.maxHeight);
        return ClipRect(
          child: SizedBox.fromSize(
            size: chartSize,
            child: CustomPaint(size: chartSize, painter: painter),
          ),
        );
      },
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.text, {this.info = false});

  final String text;
  final bool info;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
        if (info) ...[
          const SizedBox(width: CockpitSpacing.xs),
          Icon(Icons.info_outline, size: 13, color: scheme.outline),
        ],
      ],
    );
  }
}

class _TinyText extends StatelessWidget {
  const _TinyText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 11,
        height: 1.1,
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: CockpitSpacing.xs),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontSize: 10),
          ),
        ),
      ],
    );
  }
}

class _RetentionStat extends StatelessWidget {
  const _RetentionStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TinyText(label),
        Text(
          value,
          maxLines: 1,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: CircleBorder(side: BorderSide(color: scheme.outlineVariant)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 35,
          height: 60,
          child: Icon(icon, size: 17, color: scheme.onSurface),
        ),
      ),
    );
  }
}

class _FooterButton extends StatelessWidget {
  const _FooterButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final violet = _shiftHue(scheme.primary, -22);
    return Material(
      color: filled ? scheme.primary : scheme.surface,
      borderRadius: BorderRadius.circular(CockpitRadii.sm),
      child: Ink(
        decoration: BoxDecoration(
          gradient: filled
              ? LinearGradient(colors: [scheme.primary, violet])
              : null,
          borderRadius: BorderRadius.circular(CockpitRadii.sm),
          border: Border.all(
            color: filled ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CockpitRadii.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 13,
                color: filled ? scheme.onPrimary : scheme.primary,
              ),
              const SizedBox(width: CockpitSpacing.xs),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: filled ? scheme.onPrimary : scheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.values,
    required this.color,
    required this.gridColor,
    required this.labelColor,
    required this.xLabels,
    this.fill = false,
    this.endBadge,
    this.highlightBadge,
  });

  final List<double> values;
  final Color color;
  final Color gridColor;
  final Color labelColor;
  final List<String> xLabels;
  final bool fill;
  final String? endBadge;
  final String? highlightBadge;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(24, 13, size.width - 10, size.height - 16);
    final grid = Paint()
      ..color = gridColor.withValues(alpha: 0.65)
      ..strokeWidth = 0.5;
    for (var i = 0; i <= 4; i++) {
      final y = plot.bottom - plot.height * i / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _paintText(canvas, '${i * 25}%', Offset(1, y - 3), labelColor, 5);
    }
    for (var i = 0; i < xLabels.length; i++) {
      final x = plot.left + plot.width * i / math.max(1, xLabels.length - 1);
      _paintCenteredText(
        canvas,
        xLabels[i],
        Offset(x, plot.bottom + 5),
        labelColor,
        4.8,
        size,
      );
    }

    final path = Path();
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final point = Offset(
        plot.left + plot.width * i / math.max(1, values.length - 1),
        plot.bottom - plot.height * values[i].clamp(0, 100) / 100,
      );
      points.add(point);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    if (fill && points.isNotEmpty) {
      final area = Path.from(path)
        ..lineTo(points.last.dx, plot.bottom)
        ..lineTo(points.first.dx, plot.bottom)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.18),
              color.withValues(alpha: 0.01),
            ],
          ).createShader(plot),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (final point in points) {
      canvas.drawCircle(point, 1.7, Paint()..color = color);
      canvas.drawCircle(
        point,
        0.8,
        Paint()..color = color.withValues(alpha: 0.2),
      );
    }
    if (endBadge != null && points.isNotEmpty) {
      _paintBadge(
        canvas,
        endBadge!,
        points.last - const Offset(0, 14),
        color,
        size,
      );
    }
    if (highlightBadge != null && points.length > 1) {
      _paintBadge(
        canvas,
        highlightBadge!,
        points[1] - const Offset(0, 13),
        color,
        size,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

class _MultiLineChartPainter extends CustomPainter {
  _MultiLineChartPainter({
    required this.series,
    required this.colors,
    required this.gridColor,
    required this.labelColor,
  });

  final List<AnalyticsSeriesMock> series;
  final List<Color> colors;
  final Color gridColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(21, 7, size.width - 4, size.height - 13);
    final grid = Paint()
      ..color = gridColor.withValues(alpha: 0.65)
      ..strokeWidth = 0.45;
    for (var i = 0; i <= 4; i++) {
      final y = plot.bottom - plot.height * i / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _paintText(canvas, '${i * 25}%', Offset(0, y - 3), labelColor, 4.5);
    }
    const labels = ['Apr 18', 'Apr 25', 'May 2', 'May 9', 'May 16', 'May 18'];
    for (var i = 0; i < labels.length; i++) {
      final x = plot.left + plot.width * i / (labels.length - 1);
      _paintCenteredText(
        canvas,
        labels[i],
        Offset(x, plot.bottom + 4),
        labelColor,
        4.2,
        size,
      );
    }
    for (var s = 0; s < series.length; s++) {
      final values = series[s].values;
      final path = Path();
      for (var i = 0; i < values.length; i++) {
        final p = Offset(
          plot.left + plot.width * i / math.max(1, values.length - 1),
          plot.bottom - plot.height * values[i].clamp(0, 100) / 100,
        );
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawCircle(p, 1.25, Paint()..color = colors[s]);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colors[s]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MultiLineChartPainter oldDelegate) =>
      oldDelegate.series != series || oldDelegate.colors != colors;
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.colors});

  final List<Color> colors;
  static const _fractions = [0.31, 0.21, 0.19, 0.15, 0.11, 0.03];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = math.min(size.width, size.height) / 2 - 4;
    final ring = Rect.fromCircle(center: center, radius: radius);
    var start = -math.pi / 2;
    for (var i = 0; i < _fractions.length; i++) {
      final sweep = math.pi * 2 * _fractions[i] - 0.035;
      canvas.drawArc(
        ring,
        start,
        sweep,
        false,
        Paint()
          ..color = colors[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 15
          ..strokeCap = StrokeCap.butt,
      );
      start += math.pi * 2 * _fractions[i];
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.colors != colors;
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.color,
    required this.background,
  });

  final double value;
  final Color color;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 5;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = background);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.color != color;
}

void _paintBadge(
  Canvas canvas,
  String text,
  Offset center,
  Color color,
  Size bounds,
) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color.computeLuminance() > 0.55
            ? color.withValues(alpha: 0.95)
            : ColorScheme.fromSeed(seedColor: color).onPrimary,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final badgeSize = Size(painter.width + 8, painter.height + 5);
  final boundedCenter = Offset(
    _clampCenter(center.dx, bounds.width, badgeSize.width),
    _clampCenter(center.dy, bounds.height, badgeSize.height),
  );
  final rect = Rect.fromCenter(
    center: boundedCenter,
    width: badgeSize.width,
    height: badgeSize.height,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, const Radius.circular(CockpitRadii.sm)),
    Paint()..color = color,
  );
  painter.paint(
    canvas,
    Offset(
      rect.center.dx - painter.width / 2,
      rect.center.dy - painter.height / 2,
    ),
  );
}

void _paintText(
  Canvas canvas,
  String text,
  Offset offset,
  Color color,
  double size,
) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: size),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, offset);
}

void _paintCenteredText(
  Canvas canvas,
  String text,
  Offset center,
  Color color,
  double size,
  Size bounds,
) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: size),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(
    canvas,
    Offset(
      _clampOrigin(center.dx - painter.width / 2, bounds.width, painter.width),
      _clampOrigin(center.dy, bounds.height, painter.height),
    ),
  );
}

double _clampCenter(double value, double extent, double itemExtent) {
  if (extent <= itemExtent) return extent / 2;
  return value.clamp(itemExtent / 2, extent - itemExtent / 2).toDouble();
}

double _clampOrigin(double value, double extent, double itemExtent) {
  if (extent <= itemExtent) return 0;
  return value.clamp(0, extent - itemExtent).toDouble();
}

Color _shiftHue(Color base, double degrees) {
  final hsl = HSLColor.fromColor(base);
  return hsl.withHue((hsl.hue + degrees) % 360).toColor();
}
