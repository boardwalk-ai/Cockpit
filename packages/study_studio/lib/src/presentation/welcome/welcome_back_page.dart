import 'dart:math' as math;

import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/mock/mock_data.dart';
import '../widgets/studio_scaffold.dart';

/// Screen 17 — Welcome Back.
///
/// This is a mock-only Study Studio overview. Existing tools navigate to their
/// current routes; unfinished internship screens use the app's snackbar
/// placeholder convention.
class WelcomeBackPage extends StatelessWidget {
  const WelcomeBackPage({super.key});

  @override
  Widget build(BuildContext context) {
    final data = welcomeMockData;
    return StudioShell(
      selectedIndex: 1,
      child: SafeArea(
        bottom: false,
        child: isDesktop(context)
            ? _WelcomeDesktop(data: data)
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: _WelcomeBody(data: data),
                ),
              ),
      ),
    );
  }
}

void _soon(BuildContext context, String label) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('$label — coming soon')));
}

class _WelcomeBody extends StatelessWidget {
  const _WelcomeBody({required this.data});
  final WelcomeMockData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = '/study/${data.studioId}';
    final teach = '$base/teach/${data.topicId}';
    final tools = <(IconData, String, VoidCallback)>[
      (Icons.school, 'Teach Me', () => context.go(teach)),
      (
        Icons.quiz,
        'Quiz Me',
        () => context.go('$base/quiz?topicId=${data.topicId}'),
      ),
      (
        Icons.bolt,
        'Lightning Recall',
        () => _soon(context, 'Lightning Recall'),
      ),
      (
        Icons.style,
        'Flashcards',
        () => context.go('$base/flashcards?topicId=${data.topicId}'),
      ),
      (
        Icons.track_changes,
        'Scenario Mode',
        () => _soon(context, 'Scenario Mode'),
      ),
      (Icons.hub, 'Knowledge Graph', () => _soon(context, 'Knowledge Graph')),
      (Icons.chat_bubble_outline, 'Ask AI', () => _soon(context, 'Ask AI')),
      (
        Icons.event_note,
        'AI Study Plan',
        () => _soon(context, 'AI Study Plan'),
      ),
      (Icons.insights, 'Study Analytics', () => context.go('$base/analytics')),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Welcome Back', style: theme.textTheme.headlineSmall),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: () => _soon(context, 'Notifications'),
              icon: const Icon(Icons.notifications_outlined),
              label: const Text('Notifications'),
            ),
            TextButton.icon(
              onPressed: () => _soon(context, 'AI Companion'),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('AI Companion'),
            ),
          ],
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text("Today's Briefing", style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                Text(
                  'Your next session is ${data.sessionMinutes} minutes. Keep your ${data.streak}-day streak going.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 20,
                  runSpacing: 12,
                  children: [
                    StatTile(value: '${data.mastery}%', label: 'Mastery'),
                    StatTile(value: '${data.retention}%', label: 'Retention'),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => context.go(teach),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Continue Learning'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text("Here's today's plan", style: theme.textTheme.titleLarge),
        const ListTile(
          leading: Icon(Icons.looks_one_outlined),
          title: Text('Begin with Routing'),
        ),
        const ListTile(
          leading: Icon(Icons.looks_two_outlined),
          title: Text('Review WAN Design'),
        ),
        const ListTile(
          leading: Icon(Icons.looks_3_outlined),
          title: Text('Finish with Scenario Mode'),
        ),
        Text('Estimated mastery after session: ${data.estimatedMastery}%'),
        const SizedBox(height: 24),
        Text(
          'Your Study Studio at a Glance',
          style: theme.textTheme.titleLarge,
        ),
        for (final tool in tools)
          Card(
            child: ListTile(
              minTileHeight: 56,
              leading: Icon(tool.$1),
              title: Text(tool.$2),
              trailing: const Icon(Icons.chevron_right),
              onTap: tool.$3,
            ),
          ),
        const SizedBox(height: 16),
        const _LearningMilestonesCard(desktop: true),
        const SizedBox(height: 16),
        const _AiNoticedCard(desktop: true),
        const SizedBox(height: 16),
        const _KnowledgeEvolutionCard(desktop: true),
        const SizedBox(height: 16),
        const _WhatsNewCard(desktop: true),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => context.go(base),
          icon: const Icon(Icons.grid_view),
          label: const Text('Explore Study Studio'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Desktop / web layout — header + briefing full-width, then a two-column
// region: left (wider) has Today's Plan, Studio at a Glance and the action
// buttons; right stacks the four smaller insight cards.
// ---------------------------------------------------------------------------

class _WelcomeDesktop extends StatelessWidget {
  const _WelcomeDesktop({required this.data});

  final WelcomeMockData data;

  @override
  Widget build(BuildContext context) {
    final base = '/study/${data.studioId}';
    final teach = '$base/teach/${data.topicId}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 28, 40, 28),
      child: ContentColumn(
        maxWidth: 1160,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _WelcomeHeader(
                data: data,
                desktop: true,
                onNotifications: () => _soon(context, 'Notifications'),
                onCompanion: () => _soon(context, 'AI Companion'),
              ),
              const SizedBox(height: CockpitSpacing.lg),
              _BriefingCard(
                data: data,
                desktop: true,
                onContinue: () => context.go(teach),
              ),
              const SizedBox(height: CockpitSpacing.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _TodaysPlanCard(data: data, desktop: true),
                        const SizedBox(height: CockpitSpacing.lg),
                        _StudioGlanceCard(
                          desktop: true,
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
                        const SizedBox(height: CockpitSpacing.lg),
                        Row(
                          children: [
                            Expanded(
                              child: _WelcomeActionButton(
                                title: 'Continue Learning',
                                subtitle: "Resume today's AI-planned session",
                                icon: Icons.play_arrow_rounded,
                                filled: true,
                                desktop: true,
                                onTap: () => context.go(teach),
                              ),
                            ),
                            const SizedBox(width: CockpitSpacing.md),
                            Expanded(
                              child: _WelcomeActionButton(
                                title: 'Explore Study Studio',
                                subtitle: 'Browse tools and topics freely',
                                icon: Icons.grid_view_rounded,
                                desktop: true,
                                onTap: () => context.go(base),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: CockpitSpacing.xl),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _LearningMilestonesCard(desktop: true),
                        const SizedBox(height: CockpitSpacing.lg),
                        const _AiNoticedCard(desktop: true),
                        const SizedBox(height: CockpitSpacing.lg),
                        const _KnowledgeEvolutionCard(desktop: true),
                        const SizedBox(height: CockpitSpacing.lg),
                        const _WhatsNewCard(desktop: true),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader({
    required this.data,
    required this.onNotifications,
    required this.onCompanion,
    this.desktop = false,
  });

  final WelcomeMockData data;
  final VoidCallback onNotifications;
  final VoidCallback onCompanion;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final avatarSize = desktop ? 56.0 : 43.0;
    return SizedBox(
      height: desktop ? null : 66,
      child: Row(
        children: [
          Container(
            width: avatarSize,
            height: avatarSize,
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
              size: desktop ? 30 : 26,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(width: CockpitSpacing.md),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Good Morning, ${data.userName} 👋',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontSize: desktop ? null : 8,
                    fontWeight: FontWeight.w700,
                    height: desktop ? null : 1,
                  ),
                ),
                const SizedBox(height: CockpitSpacing.xxs),
                Text(
                  'Welcome Back',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontSize: desktop ? null : 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    height: desktop ? null : 1,
                  ),
                ),
                const SizedBox(height: CockpitSpacing.xxs),
                Text(
                  'Your AI Study Companion is ready.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: desktop ? null : 7,
                    height: desktop ? null : 1,
                  ),
                ),
              ],
            ),
          ),
          _HeaderAction(
            icon: Icons.notifications_none_rounded,
            showDot: true,
            onTap: onNotifications,
            desktop: desktop,
          ),
          const SizedBox(width: CockpitSpacing.sm),
          _HeaderAction(
            icon: Icons.auto_awesome,
            onTap: onCompanion,
            desktop: desktop,
          ),
        ],
      ),
    );
  }
}

class _BriefingCard extends StatelessWidget {
  const _BriefingCard({
    required this.data,
    required this.onContinue,
    this.desktop = false,
  });

  final WelcomeMockData data;
  final VoidCallback onContinue;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final imageBoxWidth = desktop ? 170.0 : 127.0;
    final imageSize = desktop ? 150.0 : 116.0;
    // `stretch` needs a bounded height: the phone card has a fixed one, the
    // desktop card grows with its content, so measure it first.
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: imageBoxWidth,
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
                width: imageSize,
                height: imageSize,
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
            padding: desktop
                ? const EdgeInsets.symmetric(
                    horizontal: CockpitSpacing.lg,
                    vertical: CockpitSpacing.md,
                  )
                : const EdgeInsets.fromLTRB(
                    CockpitSpacing.md,
                    CockpitSpacing.sm,
                    CockpitSpacing.sm,
                    CockpitSpacing.sm,
                  ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: desktop
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: desktop ? 16 : 9,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: CockpitSpacing.xs),
                    Text(
                      "Today's Briefing",
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        fontSize: desktop ? null : 6.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: CockpitSpacing.sm),
                Text(
                  "Today's session",
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontSize: desktop ? null : 8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '${data.sessionMinutes}'),
                      TextSpan(
                        text: ' min',
                        style: TextStyle(fontSize: desktop ? 14 : 8),
                      ),
                    ],
                  ),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: scheme.primary,
                    fontSize: desktop ? 32 : 24,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
                Divider(
                  height: desktop ? CockpitSpacing.lg : CockpitSpacing.md,
                ),
                Row(
                  children: [
                    Expanded(
                      child: _BriefMetric(
                        icon: Icons.donut_large,
                        color: scheme.primary,
                        label: 'Mastery',
                        value: '${data.mastery}%',
                        desktop: desktop,
                      ),
                    ),
                    Expanded(
                      child: _BriefMetric(
                        icon: Icons.shield_outlined,
                        color: CockpitColors.brand.success,
                        label: 'Exam Readiness',
                        value: 'Ready',
                        desktop: desktop,
                      ),
                    ),
                    Expanded(
                      child: _BriefMetric(
                        icon: Icons.psychology,
                        color: scheme.secondary,
                        label: 'Retention',
                        value: '${data.retention}%',
                        desktop: desktop,
                      ),
                    ),
                    Expanded(
                      child: _BriefMetric(
                        icon: Icons.local_fire_department,
                        color: CockpitColors.brand.warning,
                        label: 'Streak',
                        value: '${data.streak} days',
                        desktop: desktop,
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  height: desktop ? CockpitSpacing.lg : CockpitSpacing.sm,
                ),
                SizedBox(
                  width: double.infinity,
                  height: desktop ? 44 : 26,
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
                              size: desktop ? 18 : 13,
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
                                  fontSize: desktop ? null : 8,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward,
                              size: desktop ? 15 : 11,
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
    );
    return _WelcomeSurface(
      height: desktop ? null : 130,
      padding: EdgeInsets.zero,
      child: desktop ? IntrinsicHeight(child: row) : row,
    );
  }
}

class _TodaysPlanCard extends StatelessWidget {
  const _TodaysPlanCard({required this.data, this.desktop = false});

  final WelcomeMockData data;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (desktop) {
      return _WelcomeSurface(
        padding: const EdgeInsets.all(CockpitSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(CockpitRadii.sm),
                  ),
                  child: Icon(
                    Icons.calendar_month_rounded,
                    size: 24,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: CockpitSpacing.md),
                Text(
                  "Here's today's plan",
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: CockpitSpacing.lg),
            _PlanStep(
              color: scheme.primary,
              action: 'Begin with',
              topic: 'Routing',
              showLine: true,
              desktop: true,
            ),
            _PlanStep(
              color: scheme.secondary,
              action: 'Review',
              topic: 'WAN Design',
              showLine: true,
              desktop: true,
            ),
            _PlanStep(
              color: CockpitColors.brand.success,
              action: 'Finish with',
              topic: 'Scenario Mode',
              desktop: true,
            ),
            const SizedBox(height: CockpitSpacing.md),
            Container(
              padding: const EdgeInsets.all(CockpitSpacing.md),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.025),
                borderRadius: BorderRadius.circular(CockpitRadii.sm),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          'Estimated mastery after today',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Text(
                        '${data.estimatedMastery}%',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: CockpitSpacing.sm),
                  SizedBox(
                    height: 70,
                    child: CustomPaint(
                      painter: _WelcomeSparklinePainter(
                        values: const [55, 57, 60, 71, 68, 79, 85, 91, 100],
                        color: scheme.primary,
                        gridColor: scheme.outlineVariant,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  const SizedBox(height: CockpitSpacing.xs),
                  Text(
                    'Based on your learning habits and upcoming review '
                    'schedule.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

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
    this.desktop = false,
  });

  final bool desktop;
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

    if (desktop) {
      return _WelcomeSurface(
        padding: const EdgeInsets.all(CockpitSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Your Study Studio at a Glance',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onSeeAll,
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.chevron_right, size: 18),
                  label: const Text('See all tools'),
                ),
              ],
            ),
            const SizedBox(height: CockpitSpacing.sm),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: CockpitSpacing.sm,
                crossAxisSpacing: CockpitSpacing.sm,
                mainAxisExtent: 72,
              ),
              itemCount: tools.length,
              itemBuilder: (_, i) => _ToolTile(data: tools[i], desktop: true),
            ),
          ],
        ),
      );
    }

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
  const _LearningMilestonesCard({this.desktop = false});

  final bool desktop;

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

    if (desktop) {
      return _WelcomeSurface(
        padding: const EdgeInsets.all(CockpitSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _WelcomeSectionTitle(
              icon: Icons.emoji_events_outlined,
              title: 'Learning Milestones',
              subtitle: 'Your progress so far',
              color: scheme.primary,
              desktop: true,
            ),
            const SizedBox(height: CockpitSpacing.md),
            Wrap(
              spacing: CockpitSpacing.sm,
              runSpacing: CockpitSpacing.sm,
              children: [
                for (final m in metrics)
                  Container(
                    width: 100,
                    padding: const EdgeInsets.all(CockpitSpacing.sm),
                    decoration: BoxDecoration(
                      color: m.$2.withValues(alpha: 0.035),
                      borderRadius: BorderRadius.circular(CockpitRadii.sm),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(m.$1, size: 20, color: m.$2),
                        const SizedBox(height: CockpitSpacing.xs),
                        Text(
                          m.$3,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: CockpitSpacing.xxs),
                        Text(
                          m.$4,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
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
  const _AiNoticedCard({this.desktop = false});

  final bool desktop;

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

    if (desktop) {
      return _WelcomeSurface(
        padding: const EdgeInsets.all(CockpitSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _WelcomeSectionTitle(
              icon: Icons.auto_awesome,
              title: 'AI has noticed...',
              color: scheme.primary,
              desktop: true,
            ),
            const SizedBox(height: CockpitSpacing.md),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: CockpitSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(item.$1, size: 16, color: item.$2),
                    const SizedBox(width: CockpitSpacing.sm),
                    Expanded(
                      child: Text(
                        item.$3.replaceAll('\n', ' '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

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
  const _KnowledgeEvolutionCard({this.desktop = false});

  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (desktop) {
      return _WelcomeSurface(
        padding: const EdgeInsets.all(CockpitSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Knowledge Evolution',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              'Your knowledge graph is growing.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: CockpitSpacing.md),
            SizedBox(
              height: 90,
              child: Row(
                children: [
                  const Flexible(
                    child: _GraphCount(
                      label: 'Before',
                      value: '126',
                      desktop: true,
                    ),
                  ),
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
                  Icon(Icons.arrow_forward, size: 18, color: scheme.primary),
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
                  const Flexible(
                    child: _GraphCount(
                      label: 'Now',
                      value: '148',
                      desktop: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: CockpitSpacing.xs),
            Text(
              'Your understanding continues to grow as you study.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

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
  const _WhatsNewCard({this.desktop = false});

  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (desktop) {
      return _WelcomeSurface(
        padding: const EdgeInsets.all(CockpitSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "What's New",
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CockpitSpacing.sm,
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
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: CockpitSpacing.sm),
            Container(
              padding: const EdgeInsets.all(CockpitSpacing.md),
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
                        _WelcomeTinyText(
                          'Lecture 6 introduced:',
                          desktop: true,
                        ),
                        Text(
                          'Wireless Networking',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.wifi, size: 18, color: scheme.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: CockpitSpacing.md),
            _WelcomeTinyText('The AI has already prepared:', desktop: true),
            const SizedBox(height: CockpitSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: _PreparedMetric(
                    icon: Icons.menu_book,
                    value: '+5',
                    label: 'Topics',
                    color: scheme.primary,
                    desktop: true,
                  ),
                ),
                Expanded(
                  child: _PreparedMetric(
                    icon: Icons.style,
                    value: '+14',
                    label: 'Flashcards',
                    color: CockpitColors.brand.success,
                    desktop: true,
                  ),
                ),
                Expanded(
                  child: _PreparedMetric(
                    icon: Icons.quiz,
                    value: '+8',
                    label: 'Quiz Questions',
                    color: CockpitColors.brand.warning,
                    desktop: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: CockpitSpacing.xs),
            Text(
              'Ready whenever you are.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: CockpitColors.brand.success,
              ),
            ),
          ],
        ),
      );
    }

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
    this.desktop = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool showDot;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = desktop ? 44.0 : 35.0;
    return Material(
      color: scheme.surface,
      shape: const CircleBorder(),
      elevation: 1,
      shadowColor: scheme.shadow.withValues(alpha: 0.12),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: desktop ? 20 : 17, color: scheme.onSurface),
              if (showDot)
                Positioned(
                  top: desktop ? 9 : 7,
                  right: desktop ? 10 : 8,
                  child: Container(
                    width: desktop ? 7 : 5,
                    height: desktop ? 7 : 5,
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
    this.desktop = false,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      alignment: Alignment.centerLeft,
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: desktop ? 20 : 12, color: color),
          const SizedBox(width: CockpitSpacing.xs),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: desktop ? null : 4.7,
                  height: desktop ? null : 1,
                ),
              ),
              Text(
                value,
                style:
                    (desktop
                            ? Theme.of(context).textTheme.titleSmall
                            : Theme.of(context).textTheme.labelSmall)
                        ?.copyWith(
                          fontSize: desktop ? null : 6.5,
                          fontWeight: FontWeight.w700,
                          height: desktop ? null : 1.1,
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
    this.desktop = false,
  });

  final Color color;
  final String action;
  final String topic;
  final bool showLine;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final dotSize = desktop ? 7.0 : 5.0;
    // The connector line is an Expanded, so the row needs a bounded height.
    // Desktop text is theme-sized, so measure it instead of hard-coding.
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: desktop ? 10 : 8,
          child: Column(
            children: [
              Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _WelcomeTinyText(action, desktop: desktop),
              Text(
                topic,
                style:
                    (desktop
                            ? Theme.of(context).textTheme.bodyMedium
                            : Theme.of(context).textTheme.labelMedium)
                        ?.copyWith(
                          fontSize: desktop ? null : 7,
                          fontWeight: FontWeight.w700,
                          height: desktop ? null : 1,
                        ),
              ),
            ],
          ),
        ),
      ],
    );
    return desktop
        ? IntrinsicHeight(child: row)
        : SizedBox(height: 19, child: row);
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
  const _ToolTile({
    required this.data,
    this.compact = false,
    this.desktop = false,
  });

  final _ToolData data;
  final bool compact;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconBoxSize = desktop ? 40.0 : (compact ? 20.0 : 23.0);
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
          padding: EdgeInsets.all(
            desktop ? CockpitSpacing.sm : CockpitSpacing.xs,
          ),
          child: Row(
            children: [
              Container(
                width: iconBoxSize,
                height: iconBoxSize,
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(CockpitRadii.sm),
                ),
                child: Icon(
                  data.icon,
                  size: desktop ? 22 : (compact ? 12 : 14),
                  color: data.color,
                ),
              ),
              SizedBox(width: desktop ? CockpitSpacing.sm : CockpitSpacing.xs),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          (desktop
                                  ? Theme.of(context).textTheme.labelLarge
                                  : Theme.of(context).textTheme.labelSmall)
                              ?.copyWith(
                                fontSize: desktop ? null : (compact ? 5 : 5.8),
                                fontWeight: FontWeight.w700,
                                height: desktop ? null : 1,
                              ),
                    ),
                    const SizedBox(height: CockpitSpacing.xxs),
                    Text(
                      data.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: data.color,
                        fontSize: desktop ? null : (compact ? 4.3 : 5),
                        height: desktop ? null : 1,
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
    this.desktop = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: desktop ? 18 : 10, color: color),
        const SizedBox(width: CockpitSpacing.sm),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style:
                    (desktop
                            ? Theme.of(context).textTheme.titleMedium
                            : Theme.of(context).textTheme.labelMedium)
                        ?.copyWith(
                          fontSize: desktop ? null : 7,
                          fontWeight: FontWeight.w700,
                          height: desktop ? null : 1,
                        ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style:
                      (desktop
                              ? Theme.of(context).textTheme.bodySmall
                              : Theme.of(context).textTheme.labelSmall)
                          ?.copyWith(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: desktop ? null : 5.2,
                            height: desktop ? null : 1,
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
  const _GraphCount({
    required this.label,
    required this.value,
    this.desktop = false,
  });

  final String label;
  final String value;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _WelcomeTinyText(label, desktop: desktop),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontSize: desktop ? null : 11,
            fontWeight: FontWeight.w700,
            height: desktop ? null : 1,
          ),
        ),
        _WelcomeTinyText('Connections', desktop: desktop),
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
    this.desktop = false,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      alignment: Alignment.centerLeft,
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: desktop ? 18 : 10, color: color),
          SizedBox(width: desktop ? CockpitSpacing.sm : CockpitSpacing.xxs),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: desktop ? null : 5.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: desktop ? null : 3.8,
                ),
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
    this.desktop = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  final bool desktop;

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
          child: Padding(
            padding: desktop
                ? const EdgeInsets.symmetric(vertical: CockpitSpacing.md)
                : EdgeInsets.zero,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: desktop ? 20 : 12,
                  color: filled ? scheme.onPrimary : scheme.primary,
                ),
                const SizedBox(width: CockpitSpacing.sm),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: filled ? scheme.onPrimary : scheme.primary,
                          fontSize: desktop ? null : 8,
                          fontWeight: FontWeight.w700,
                          height: desktop ? null : 1,
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
                          fontSize: desktop ? null : 5,
                          height: desktop ? null : 1,
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
    );
  }
}

class _WelcomeTinyText extends StatelessWidget {
  const _WelcomeTinyText(this.text, {this.desktop = false});

  final String text;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: desktop ? null : 5,
        height: desktop ? null : 1.05,
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
