import 'dart:math' as math;

import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/mock/mock_data.dart';
import '../widgets/studio_bottom_nav.dart';

/// Screen 17 — Welcome Back.
///
/// This is a mock-only Study Studio overview. Existing tools navigate to their
/// current routes; unfinished internship screens use the app's snackbar
/// placeholder convention.
class WelcomeBackPage extends StatelessWidget {
  const WelcomeBackPage({super.key});

  void _soon(BuildContext context, String label) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label — coming soon')));
  }

  @override
  Widget build(BuildContext context) {
    final data = welcomeMockData;
    final base = '/study/${data.studioId}';
    final teach = '$base/teach/${data.topicId}';
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: const Alignment(0, -0.35),
                  colors: [
                    Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.055),
                    Theme.of(context).colorScheme.surface,
                  ],
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  CockpitSpacing.md,
                  CockpitSpacing.sm,
                  CockpitSpacing.md,
                  CockpitSpacing.sm,
                ),
                child: Column(
                  children: [
                    _WelcomeHeader(
                      data: data,
                      onNotifications: () => _soon(context, 'Notifications'),
                      onCompanion: () => _soon(context, 'AI Companion'),
                    ),
                    const SizedBox(height: CockpitSpacing.sm),
                    _BriefingCard(
                      data: data,
                      onContinue: () => context.go(teach),
                    ),
                    const SizedBox(height: CockpitSpacing.sm),
                    _TodaysPlanCard(data: data),
                    const SizedBox(height: CockpitSpacing.sm),
                    _StudioGlanceCard(
                      onSeeAll: () => context.go(base),
                      onTeach: () => context.go(teach),
                      onQuiz: () =>
                          context.go('$base/quiz?topicId=${data.topicId}'),
                      onLightning: () => _soon(context, 'Lightning Recall'),
                      onFlashcards: () => context.go(
                        '$base/flashcards?topicId=${data.topicId}',
                      ),
                      onScenario: () => _soon(context, 'Scenario Mode'),
                      onKnowledge: () => _soon(context, 'Knowledge Graph'),
                      onAskAi: () => _soon(context, 'Ask AI'),
                      onStudyPlan: () => _soon(context, 'AI Study Plan'),
                      onAnalytics: () => context.go('$base/analytics'),
                    ),
                    const SizedBox(height: CockpitSpacing.sm),
                    const SizedBox(
                      height: 105,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 11, child: _LearningMilestonesCard()),
                          SizedBox(width: CockpitSpacing.sm),
                          Expanded(flex: 9, child: _AiNoticedCard()),
                        ],
                      ),
                    ),
                    const SizedBox(height: CockpitSpacing.sm),
                    const SizedBox(
                      height: 110,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 11, child: _KnowledgeEvolutionCard()),
                          SizedBox(width: CockpitSpacing.sm),
                          Expanded(flex: 9, child: _WhatsNewCard()),
                        ],
                      ),
                    ),
                    const SizedBox(height: CockpitSpacing.sm),
                    SizedBox(
                      height: 37,
                      child: Row(
                        children: [
                          Expanded(
                            child: _WelcomeActionButton(
                              title: 'Continue Learning',
                              subtitle: "Resume today's AI-planned session",
                              icon: Icons.play_arrow_rounded,
                              filled: true,
                              onTap: () => context.go(teach),
                            ),
                          ),
                          const SizedBox(width: CockpitSpacing.sm),
                          Expanded(
                            child: _WelcomeActionButton(
                              title: 'Explore Study Studio',
                              subtitle: 'Browse tools and topics freely',
                              icon: Icons.grid_view_rounded,
                              onTap: () => context.go(base),
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
      ),
      bottomNavigationBar: const StudioBottomNav(selectedIndex: 1),
    );
  }
}

class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader({
    required this.data,
    required this.onNotifications,
    required this.onCompanion,
  });

  final WelcomeMockData data;
  final VoidCallback onNotifications;
  final VoidCallback onCompanion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      height: 66,
      child: Row(
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.secondary.withValues(alpha: 0.45),
                  scheme.primary.withValues(alpha: 0.2),
                ],
              ),
              border: Border.all(color: scheme.surface, width: 2),
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              Icons.person_rounded,
              size: 26,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(width: CockpitSpacing.md),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Good Morning, ${data.userName} 👋',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
                const SizedBox(height: CockpitSpacing.xxs),
                Text(
                  'Welcome Back',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    height: 1,
                  ),
                ),
                const SizedBox(height: CockpitSpacing.xxs),
                Text(
                  'Your AI Study Companion is ready.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 7,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          _HeaderAction(
            icon: Icons.notifications_none_rounded,
            showDot: true,
            onTap: onNotifications,
          ),
          const SizedBox(width: CockpitSpacing.sm),
          _HeaderAction(icon: Icons.auto_awesome, onTap: onCompanion),
        ],
      ),
    );
  }
}

class _BriefingCard extends StatelessWidget {
  const _BriefingCard({required this.data, required this.onContinue});

  final WelcomeMockData data;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _WelcomeSurface(
      height: 130,
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          SizedBox(
            width: 127,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(CockpitRadii.lg),
                      ),
                      gradient: RadialGradient(
                        colors: [
                          scheme.primary.withValues(alpha: 0.25),
                          scheme.primary.withValues(alpha: 0.035),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  width: 116,
                  height: 116,
                  child: Image.asset(
                    'assets/images/ai_study_companion.png',
                    package: 'study_studio',
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                CockpitSpacing.md,
                CockpitSpacing.sm,
                CockpitSpacing.sm,
                CockpitSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 9, color: scheme.primary),
                      const SizedBox(width: CockpitSpacing.xs),
                      Text(
                        "Today's Briefing",
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontSize: 6.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: CockpitSpacing.sm),
                  Text(
                    "Today's session",
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '${data.sessionMinutes}'),
                        const TextSpan(
                          text: ' min',
                          style: TextStyle(fontSize: 8),
                        ),
                      ],
                    ),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: scheme.primary,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                  const Divider(height: CockpitSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: _BriefMetric(
                          icon: Icons.donut_large,
                          color: scheme.primary,
                          label: 'Mastery',
                          value: '${data.mastery}%',
                        ),
                      ),
                      Expanded(
                        child: _BriefMetric(
                          icon: Icons.shield_outlined,
                          color: CockpitColors.brand.success,
                          label: 'Exam Readiness',
                          value: 'Ready',
                        ),
                      ),
                      Expanded(
                        child: _BriefMetric(
                          icon: Icons.psychology,
                          color: scheme.secondary,
                          label: 'Retention',
                          value: '${data.retention}%',
                        ),
                      ),
                      Expanded(
                        child: _BriefMetric(
                          icon: Icons.local_fire_department,
                          color: CockpitColors.brand.warning,
                          label: 'Streak',
                          value: '${data.streak} days',
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 26,
                    child: Material(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(CockpitRadii.sm),
                      child: InkWell(
                        onTap: onContinue,
                        borderRadius: BorderRadius.circular(CockpitRadii.sm),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: CockpitSpacing.sm,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.play_arrow_rounded,
                                size: 13,
                                color: scheme.onPrimary,
                              ),
                              Expanded(
                                child: Text(
                                  'Continue Learning',
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onPrimary,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward,
                                size: 11,
                                color: scheme.onPrimary,
                              ),
                            ],
                          ),
                        ),
                      ),
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

class _TodaysPlanCard extends StatelessWidget {
  const _TodaysPlanCard({required this.data});

  final WelcomeMockData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _WelcomeSurface(
      height: 98,
      child: Row(
        children: [
          Expanded(
            flex: 11,
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(CockpitRadii.sm),
                  ),
                  child: Icon(
                    Icons.calendar_month_rounded,
                    size: 22,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: CockpitSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Here's today's plan",
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      _PlanStep(
                        color: scheme.primary,
                        action: 'Begin with',
                        topic: 'Routing',
                        showLine: true,
                      ),
                      _PlanStep(
                        color: scheme.secondary,
                        action: 'Review',
                        topic: 'WAN Design',
                        showLine: true,
                      ),
                      _PlanStep(
                        color: CockpitColors.brand.success,
                        action: 'Finish with',
                        topic: 'Scenario Mode',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: CockpitSpacing.lg),
          Expanded(
            flex: 9,
            child: Container(
              padding: const EdgeInsets.all(CockpitSpacing.sm),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.025),
                borderRadius: BorderRadius.circular(CockpitRadii.sm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Estimated mastery\nafter today',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontSize: 6.5,
                      height: 1.15,
                    ),
                  ),
                  Text(
                    '${data.estimatedMastery}%',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: scheme.primary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                  Expanded(
                    child: CustomPaint(
                      painter: _WelcomeSparklinePainter(
                        values: const [55, 57, 60, 71, 68, 79, 85, 91, 100],
                        color: scheme.primary,
                        gridColor: scheme.outlineVariant,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  Text(
                    'Based on your learning habits and\nupcoming review schedule.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontSize: 5,
                      height: 1.1,
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

class _StudioGlanceCard extends StatelessWidget {
  const _StudioGlanceCard({
    required this.onSeeAll,
    required this.onTeach,
    required this.onQuiz,
    required this.onLightning,
    required this.onFlashcards,
    required this.onScenario,
    required this.onKnowledge,
    required this.onAskAi,
    required this.onStudyPlan,
    required this.onAnalytics,
  });

  final VoidCallback onSeeAll;
  final VoidCallback onTeach;
  final VoidCallback onQuiz;
  final VoidCallback onLightning;
  final VoidCallback onFlashcards;
  final VoidCallback onScenario;
  final VoidCallback onKnowledge;
  final VoidCallback onAskAi;
  final VoidCallback onStudyPlan;
  final VoidCallback onAnalytics;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tools = [
      _ToolData(
        Icons.smart_toy_outlined,
        'Teach Me',
        'Completed ✓',
        scheme.primary,
        onTeach,
      ),
      _ToolData(
        Icons.quiz,
        'Quiz Me',
        'Last Score\n91%',
        CockpitColors.brand.success,
        onQuiz,
      ),
      _ToolData(
        Icons.bolt,
        'Lightning Recall',
        'Current Streak\n32',
        CockpitColors.brand.warning,
        onLightning,
      ),
      _ToolData(
        Icons.style,
        'Flashcards',
        '12 cards due',
        scheme.secondary,
        onFlashcards,
      ),
      _ToolData(
        Icons.track_changes,
        'Scenario Mode',
        '2 available',
        _shiftHue(scheme.error, -18),
        onScenario,
      ),
      _ToolData(
        Icons.hub_outlined,
        'Knowledge Graph',
        '3 new connections\ndiscovered',
        scheme.primary,
        onKnowledge,
      ),
      _ToolData(
        Icons.chat_bubble_outline,
        'Ask AI',
        'Recent question\nRouting vs Switching',
        scheme.secondary,
        onAskAi,
      ),
      _ToolData(
        Icons.event_note,
        'AI Study Plan',
        'Ready',
        scheme.primary,
        onStudyPlan,
      ),
      _ToolData(
        Icons.pie_chart_outline,
        'Analytics',
        'Updated\ntoday',
        _shiftHue(scheme.primary, -28),
        onAnalytics,
      ),
    ];
    return _WelcomeSurface(
      height: 111,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Your Study Studio at a Glance',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              InkWell(
                onTap: onSeeAll,
                borderRadius: BorderRadius.circular(CockpitRadii.sm),
                child: Padding(
                  padding: const EdgeInsets.all(CockpitSpacing.xs),
                  child: Row(
                    children: [
                      Text(
                        'See all tools',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontSize: 6.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 10,
                        color: scheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.xs),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      for (var i = 0; i < 4; i++) ...[
                        if (i > 0) const SizedBox(width: CockpitSpacing.xs),
                        Expanded(child: _ToolTile(data: tools[i])),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: CockpitSpacing.xs),
                Expanded(
                  child: Row(
                    children: [
                      for (var i = 4; i < tools.length; i++) ...[
                        if (i > 4) const SizedBox(width: CockpitSpacing.xs),
                        Expanded(
                          child: _ToolTile(data: tools[i], compact: true),
                        ),
                      ],
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

class _LearningMilestonesCard extends StatelessWidget {
  const _LearningMilestonesCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final metrics = [
      (Icons.menu_book, scheme.primary, '212', 'Concepts\nMastered'),
      (Icons.bar_chart, CockpitColors.brand.success, '74', 'Study\nSessions'),
      (Icons.schedule, CockpitColors.brand.warning, '58', 'Hours\nLearned'),
      (Icons.psychology, scheme.secondary, '93%', 'Retention'),
      (
        Icons.local_fire_department,
        _shiftHue(scheme.error, -18),
        '21',
        'Day\nConsistency',
      ),
    ];
    return _WelcomeSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WelcomeSectionTitle(
            icon: Icons.emoji_events_outlined,
            title: 'Learning Milestones',
            subtitle: 'Your progress so far',
            color: scheme.primary,
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < metrics.length; i++) ...[
                  if (i > 0) const SizedBox(width: CockpitSpacing.xs),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(CockpitSpacing.xxs),
                      decoration: BoxDecoration(
                        color: metrics[i].$2.withValues(alpha: 0.035),
                        borderRadius: BorderRadius.circular(CockpitRadii.sm),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Column(
                        children: [
                          Icon(metrics[i].$1, size: 11, color: metrics[i].$2),
                          const SizedBox(height: CockpitSpacing.xxs),
                          Text(
                            metrics[i].$3,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  height: 1,
                                ),
                          ),
                          const Spacer(),
                          Text(
                            metrics[i].$4,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(fontSize: 4.2, height: 1),
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

class _AiNoticedCard extends StatelessWidget {
  const _AiNoticedCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = [
      (
        Icons.bolt,
        CockpitColors.brand.warning,
        'You learn 26% faster after\ncompleting Lightning Recall.',
      ),
      (
        Icons.dark_mode_outlined,
        scheme.primary,
        'You retain more information during\nevening study sessions.',
      ),
      (
        Icons.track_changes,
        _shiftHue(scheme.error, -18),
        'Scenario Mode has become your\nstrongest learning activity.',
      ),
      (
        Icons.check_circle,
        CockpitColors.brand.success,
        'Routing is no longer one of your\nweak areas.',
      ),
    ];
    return _WelcomeSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WelcomeSectionTitle(
            icon: Icons.auto_awesome,
            title: 'AI has noticed...',
            color: scheme.primary,
          ),
          const SizedBox(height: CockpitSpacing.xxs),
          for (final item in items)
            Expanded(
              child: Row(
                children: [
                  Icon(item.$1, size: 8, color: item.$2),
                  const SizedBox(width: CockpitSpacing.xs),
                  Expanded(
                    child: Text(
                      item.$3,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 4.5,
                        height: 1,
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

class _KnowledgeEvolutionCard extends StatelessWidget {
  const _KnowledgeEvolutionCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _WelcomeSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Knowledge Evolution',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontSize: 7,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            'Your knowledge graph is growing.',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 5.2,
            ),
          ),
          const SizedBox(height: CockpitSpacing.xs),
          Expanded(
            child: Row(
              children: [
                const _GraphCount(label: 'Before', value: '126'),
                Expanded(
                  child: CustomPaint(
                    painter: _KnowledgeGraphPainter(
                      primary: scheme.primary,
                      secondary: scheme.secondary,
                      success: CockpitColors.brand.success,
                      line: scheme.outlineVariant,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
                Icon(Icons.arrow_forward, size: 11, color: scheme.primary),
                Expanded(
                  child: CustomPaint(
                    painter: _KnowledgeGraphPainter(
                      primary: scheme.primary,
                      secondary: scheme.secondary,
                      success: CockpitColors.brand.success,
                      line: scheme.outlineVariant,
                      expanded: true,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
                const _GraphCount(label: 'Now', value: '148'),
              ],
            ),
          ),
          Align(
            child: Text(
              'Your understanding continues to grow as you study.',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontSize: 5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WhatsNewCard extends StatelessWidget {
  const _WhatsNewCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _WelcomeSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "What's New",
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontSize: 7,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: CockpitSpacing.xs,
                  vertical: CockpitSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(CockpitRadii.pill),
                ),
                child: Text(
                  'New',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onPrimary,
                    fontSize: 5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.xs),
          Container(
            padding: const EdgeInsets.all(CockpitSpacing.xs),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(CockpitRadii.sm),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _WelcomeTinyText('Lecture 6 introduced:'),
                      Text(
                        'Wireless Networking',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.wifi, size: 11, color: scheme.primary),
                ),
              ],
            ),
          ),
          const Spacer(),
          const _WelcomeTinyText('The AI has already prepared:'),
          Row(
            children: [
              Expanded(
                child: _PreparedMetric(
                  icon: Icons.menu_book,
                  value: '+5',
                  label: 'Topics',
                  color: scheme.primary,
                ),
              ),
              Expanded(
                child: _PreparedMetric(
                  icon: Icons.style,
                  value: '+14',
                  label: 'Flashcards',
                  color: CockpitColors.brand.success,
                ),
              ),
              Expanded(
                child: _PreparedMetric(
                  icon: Icons.quiz,
                  value: '+8',
                  label: 'Quiz Questions',
                  color: CockpitColors.brand.warning,
                ),
              ),
            ],
          ),
          Text(
            'Ready whenever you are.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: CockpitColors.brand.success,
              fontSize: 5.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeSurface extends StatelessWidget {
  const _WelcomeSurface({
    required this.child,
    this.height,
    this.padding = const EdgeInsets.all(CockpitSpacing.sm),
  });

  final Widget child;
  final double? height;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.035),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.onTap,
    this.showDot = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: const CircleBorder(),
      elevation: 1,
      shadowColor: scheme.shadow.withValues(alpha: 0.12),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 35,
          height: 35,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 17, color: scheme.onSurface),
              if (showDot)
                Positioned(
                  top: 7,
                  right: 8,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.surface),
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

class _BriefMetric extends StatelessWidget {
  const _BriefMetric({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      alignment: Alignment.centerLeft,
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: CockpitSpacing.xs),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(fontSize: 4.7, height: 1),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 6.5,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanStep extends StatelessWidget {
  const _PlanStep({
    required this.color,
    required this.action,
    required this.topic,
    this.showLine = false,
  });

  final Color color;
  final String action;
  final String topic;
  final bool showLine;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 19,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 8,
            child: Column(
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                if (showLine)
                  Expanded(
                    child: Container(
                      width: 1,
                      color: color.withValues(alpha: 0.28),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _WelcomeTinyText(action),
              Text(
                topic,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontSize: 7,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToolData {
  const _ToolData(this.icon, this.title, this.subtitle, this.color, this.onTap);

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({required this.data, this.compact = false});

  final _ToolData data;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CockpitRadii.sm),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: data.onTap,
        child: Padding(
          padding: const EdgeInsets.all(CockpitSpacing.xs),
          child: Row(
            children: [
              Container(
                width: compact ? 20 : 23,
                height: compact ? 20 : 23,
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(CockpitRadii.sm),
                ),
                child: Icon(
                  data.icon,
                  size: compact ? 12 : 14,
                  color: data.color,
                ),
              ),
              const SizedBox(width: CockpitSpacing.xs),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: compact ? 5 : 5.8,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: CockpitSpacing.xxs),
                    Text(
                      data.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: data.color,
                        fontSize: compact ? 4.3 : 5,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeSectionTitle extends StatelessWidget {
  const _WelcomeSectionTitle({
    required this.icon,
    required this.title,
    required this.color,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: CockpitSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontSize: 7,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 5.2,
                    height: 1,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GraphCount extends StatelessWidget {
  const _GraphCount({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _WelcomeTinyText(label),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
        const _WelcomeTinyText('Connections'),
      ],
    );
  }
}

class _PreparedMetric extends StatelessWidget {
  const _PreparedMetric({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      alignment: Alignment.centerLeft,
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: CockpitSpacing.xxs),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 5.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(fontSize: 3.8),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WelcomeActionButton extends StatelessWidget {
  const _WelcomeActionButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final violet = _shiftHue(scheme.primary, -24);
    return Material(
      color: filled ? scheme.primary : scheme.surface,
      borderRadius: BorderRadius.circular(CockpitRadii.md),
      child: Ink(
        decoration: BoxDecoration(
          gradient: filled
              ? LinearGradient(colors: [scheme.primary, violet])
              : null,
          borderRadius: BorderRadius.circular(CockpitRadii.md),
          border: Border.all(
            color: filled ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CockpitRadii.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 12,
                color: filled ? scheme.onPrimary : scheme.primary,
              ),
              const SizedBox(width: CockpitSpacing.sm),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: filled ? scheme.onPrimary : scheme.primary,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: CockpitSpacing.xxs),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: filled
                            ? scheme.onPrimary.withValues(alpha: 0.8)
                            : scheme.onSurfaceVariant,
                        fontSize: 5,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeTinyText extends StatelessWidget {
  const _WelcomeTinyText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 5,
        height: 1.05,
      ),
    );
  }
}

class _WelcomeSparklinePainter extends CustomPainter {
  _WelcomeSparklinePainter({
    required this.values,
    required this.color,
    required this.gridColor,
  });

  final List<double> values;
  final Color color;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final plot = Rect.fromLTRB(1, 3, size.width - 2, size.height - 2);
    final path = Path();
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final p = Offset(
        plot.left + plot.width * i / math.max(1, values.length - 1),
        plot.bottom - plot.height * values[i].clamp(0, 100) / 100,
      );
      points.add(p);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
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
    canvas.drawLine(
      Offset(plot.left, plot.bottom),
      Offset(plot.right, plot.bottom),
      Paint()..color = gridColor,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round,
    );
    for (final p in points) {
      canvas.drawCircle(p, 1.2, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _WelcomeSparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

class _KnowledgeGraphPainter extends CustomPainter {
  _KnowledgeGraphPainter({
    required this.primary,
    required this.secondary,
    required this.success,
    required this.line,
    this.expanded = false,
  });

  final Color primary;
  final Color secondary;
  final Color success;
  final Color line;
  final bool expanded;

  static const _small = [
    Offset(0.50, 0.48),
    Offset(0.24, 0.24),
    Offset(0.77, 0.18),
    Offset(0.16, 0.66),
    Offset(0.78, 0.73),
    Offset(0.46, 0.08),
    Offset(0.48, 0.86),
    Offset(0.93, 0.48),
  ];
  static const _large = [
    ..._small,
    Offset(0.05, 0.40),
    Offset(0.34, 0.62),
    Offset(0.65, 0.38),
    Offset(0.91, 0.08),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final nodes = expanded ? _large : _small;
    final points = [
      for (final node in nodes)
        Offset(node.dx * size.width, node.dy * size.height),
    ];
    final linePaint = Paint()
      ..color = line
      ..strokeWidth = 0.6;
    for (var i = 1; i < points.length; i++) {
      canvas.drawLine(points[0], points[i], linePaint);
      if (i > 2) canvas.drawLine(points[i - 1], points[i], linePaint);
    }
    final colors = [primary, secondary, success];
    for (var i = 0; i < points.length; i++) {
      final color = colors[i % colors.length];
      canvas.drawCircle(points[i], i == 0 ? 2.2 : 1.5, Paint()..color = color);
      canvas.drawCircle(
        points[i],
        i == 0 ? 4.5 : 3,
        Paint()..color = color.withValues(alpha: 0.09),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _KnowledgeGraphPainter oldDelegate) =>
      oldDelegate.expanded != expanded || oldDelegate.primary != primary;
}

Color _shiftHue(Color base, double degrees) {
  final hsl = HSLColor.fromColor(base);
  return hsl.withHue((hsl.hue + degrees) % 360).toColor();
}
