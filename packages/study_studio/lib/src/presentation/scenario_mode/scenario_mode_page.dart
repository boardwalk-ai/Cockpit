import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../domain/entities/scenario.dart';
import '../../domain/entities/studio.dart';
import '../widgets/mobile_layout.dart';
import '../widgets/studio_palette.dart';
import '../widgets/studio_scaffold.dart';

/// Screen 10 — Scenario Mode.
///
/// The learner applies concepts to a realistic situation: read the brief,
/// investigate clues, choose the best first action, then get the AI's reasoning.
/// Scenarios come from the live [Studio] (generated from the uploaded material).
class ScenarioModePage extends ConsumerStatefulWidget {
  const ScenarioModePage({super.key, required this.studioId});

  final String studioId;

  @override
  ConsumerState<ScenarioModePage> createState() => _ScenarioModePageState();
}

class _ScenarioModePageState extends ConsumerState<ScenarioModePage> {
  int _index = 0;
  final _revealed = <String>{};
  String? _selectedOptionId;

  void _reset() {
    _revealed.clear();
    _selectedOptionId = null;
  }

  void _goTo(int i, int total) {
    if (total == 0) return;
    setState(() {
      _index = i % total;
      _reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(studioProvider(widget.studioId));
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (studio) {
            final scenarios = studio.scenarios;
            final base = '/study/${studio.id}';
            if (scenarios.isEmpty) {
              return _Empty(
                title: studio.title,
                onBack: () => context.go(base),
              );
            }
            final i = _index.clamp(0, scenarios.length - 1);
            final scenario = scenarios[i];
            return Column(
              children: [
                _Header(
                  title: studio.title,
                  index: i,
                  total: scenarios.length,
                  onBack: () => context.go(base),
                ),
                Expanded(
                  child: _Body(
                    studio: studio,
                    scenario: scenario,
                    index: i,
                    total: scenarios.length,
                    revealed: _revealed,
                    selectedOptionId: _selectedOptionId,
                    onReveal: (id) => setState(() => _revealed.add(id)),
                    onSelect: (id) => setState(() => _selectedOptionId = id),
                    onAnother: () => _goTo(i + 1, scenarios.length),
                    onReviewLesson: () {
                      final t = _relatedTopicId(studio, scenario);
                      context.go(t != null ? '$base/teach/$t' : '$base/topics');
                    },
                    onContinue: () => context.go('$base/mastery-report'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Find a studio topic whose title matches one of the scenario's related
  /// topics (for "Review Lesson").
  String? _relatedTopicId(Studio studio, Scenario s) {
    for (final name in s.relatedTopics) {
      for (final t in studio.topics) {
        if (t.title.toLowerCase() == name.toLowerCase()) return t.id;
      }
    }
    return studio.topics.isNotEmpty ? studio.topics.first.id : null;
  }
}

// ---------------------------------------------------------------------------
// Body — responsive
// ---------------------------------------------------------------------------

class _Body extends StatelessWidget {
  const _Body({
    required this.studio,
    required this.scenario,
    required this.index,
    required this.total,
    required this.revealed,
    required this.selectedOptionId,
    required this.onReveal,
    required this.onSelect,
    required this.onAnother,
    required this.onReviewLesson,
    required this.onContinue,
  });

  final Studio studio;
  final Scenario scenario;
  final int index;
  final int total;
  final Set<String> revealed;
  final String? selectedOptionId;
  final ValueChanged<String> onReveal;
  final ValueChanged<String> onSelect;
  final VoidCallback onAnother;
  final VoidCallback onReviewLesson;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final answered = selectedOptionId != null;
    final progress = total == 0 ? 0.0 : (index + 1) / total;

    final brief = _BriefCard(scenario: scenario);
    final problem = _ProblemCard(scenario: scenario);
    final investigation = _InvestigationPanel(
      scenario: scenario,
      revealed: revealed,
      onReveal: onReveal,
    );
    final decision = _DecisionPanel(
      scenario: scenario,
      selectedOptionId: selectedOptionId,
      onSelect: onSelect,
    );
    final feedback = answered
        ? _FeedbackCard(
            scenario: scenario,
            correct: scenario.isCorrect(selectedOptionId!),
          )
        : null;
    final reflection = answered ? _ReflectionCard(scenario: scenario) : null;
    final actions = _ActionsBar(
      onAnother: onAnother,
      onReviewLesson: onReviewLesson,
      onContinue: onContinue,
    );

    if (isDesktop(context)) {
      // Two columns: the scenario narrative + decision on the left (main),
      // investigation tools + reflection on the right.
      return Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ProgressBar(progress: progress),
                          const SizedBox(height: CockpitSpacing.lg),
                          brief,
                          const SizedBox(height: CockpitSpacing.lg),
                          problem,
                          const SizedBox(height: CockpitSpacing.lg),
                          decision,
                          if (feedback != null) ...[
                            const SizedBox(height: CockpitSpacing.lg),
                            feedback,
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 2,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          investigation,
                          if (reflection != null) ...[
                            const SizedBox(height: CockpitSpacing.lg),
                            reflection,
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _bottom(context, actions, wide: true),
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              CockpitSpacing.lg,
              CockpitSpacing.xs,
              CockpitSpacing.lg,
              CockpitSpacing.lg,
            ),
            children: [
              _ProgressBar(progress: progress),
              const SizedBox(height: CockpitSpacing.lg),
              brief,
              const SizedBox(height: CockpitSpacing.lg),
              problem,
              const SizedBox(height: CockpitSpacing.lg),
              investigation,
              const SizedBox(height: CockpitSpacing.lg),
              decision,
              if (feedback != null) ...[
                const SizedBox(height: CockpitSpacing.lg),
                feedback,
              ],
              if (reflection != null) ...[
                const SizedBox(height: CockpitSpacing.lg),
                reflection,
              ],
            ],
          ),
        ),
        _bottom(context, actions, wide: false),
      ],
    );
  }

  Widget _bottom(BuildContext context, Widget actions, {required bool wide}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        CockpitSpacing.lg,
        CockpitSpacing.md,
        CockpitSpacing.lg,
        CockpitSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: wide ? ContentColumn(maxWidth: 1100, child: actions) : actions,
    );
  }
}

// ---------------------------------------------------------------------------
// Header + progress
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.index,
    required this.total,
    required this.onBack,
  });

  final String title;
  final int index;
  final int total;
  final VoidCallback onBack;

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
          _CircleButton(icon: Icons.arrow_back_ios_new, onTap: onBack),
          const SizedBox(width: CockpitSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                MobileWrap(
                  children: [
                    Icon(
                      Icons.track_changes_rounded,
                      size: 14,
                      color: StudyPalette.success,
                    ),
                    const SizedBox(width: CockpitSpacing.xs),
                    Text(
                      'Scenario Mode',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: StudyPalette.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          Text(
            'Scenario ${index + 1} of $total',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      children: [
        Row(
          children: [
            Text(
              'Progress',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Text(
              '${(progress * 100).round()}% Complete',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: CockpitSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(CockpitRadii.pill),
          child: LinearProgressIndicator(
            value: progress.clamp(0, 1),
            minHeight: 6,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Scenario brief
// ---------------------------------------------------------------------------

class _BriefCard extends StatelessWidget {
  const _BriefCard({required this.scenario});
  final Scenario scenario;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.assignment_outlined,
                size: 18,
                color: StudyPalette.success,
              ),
              const SizedBox(width: CockpitSpacing.xs),
              Text(
                'Scenario Brief',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: StudyPalette.success,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.md),
          Wrap(
            spacing: CockpitSpacing.xl,
            runSpacing: CockpitSpacing.md,
            children: [
              _Brief(
                icon: Icons.bar_chart_rounded,
                label: 'Difficulty',
                value: scenario.difficultyLabel,
              ),
              _Brief(
                icon: Icons.schedule_rounded,
                label: 'Est. time',
                value: '${scenario.estimatedMinutes} min',
              ),
              if (scenario.skills.isNotEmpty)
                _Brief(
                  icon: Icons.track_changes_rounded,
                  label: 'Skills tested',
                  value: scenario.skills.join(', '),
                ),
            ],
          ),
          if (scenario.aiNote.isNotEmpty) ...[
            const SizedBox(height: CockpitSpacing.md),
            Container(
              padding: const EdgeInsets.all(CockpitSpacing.md),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(CockpitRadii.md),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.smart_toy_rounded,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: CockpitSpacing.sm),
                  Expanded(
                    child: Text(
                      scenario.aiNote,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Brief extends StatelessWidget {
  const _Brief({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: CockpitSpacing.xs),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Problem hero
// ---------------------------------------------------------------------------

class _ProblemCard extends StatelessWidget {
  const _ProblemCard({required this.scenario});
  final Scenario scenario;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CockpitRadii.xl),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary.withValues(alpha: 0.06), scheme.surface],
        ),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Scenario',
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: CockpitSpacing.sm),
          if (scenario.title.isNotEmpty) ...[
            Text(
              scenario.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: CockpitSpacing.sm),
          ],
          Text(
            scenario.problem,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: CockpitSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(CockpitSpacing.md),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(CockpitRadii.md),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.help_outline_rounded,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: CockpitSpacing.sm),
                Expanded(
                  child: Text(
                    scenario.question,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.35,
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
// Investigation panel
// ---------------------------------------------------------------------------

class _InvestigationPanel extends StatelessWidget {
  const _InvestigationPanel({
    required this.scenario,
    required this.revealed,
    required this.onReveal,
  });

  final Scenario scenario;
  final Set<String> revealed;
  final ValueChanged<String> onReveal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (scenario.clues.isEmpty) return const SizedBox.shrink();
    final found = scenario.clues.where((c) => revealed.contains(c.id)).length;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.search_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: CockpitSpacing.xs),
              Expanded(
                child: Text(
                  'Investigation Tools',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                'Clues found: $found / ${scenario.clues.length}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Gather clues to help you solve the problem.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: CockpitSpacing.md),
          for (final clue in scenario.clues) ...[
            _ClueTile(
              clue: clue,
              revealed: revealed.contains(clue.id),
              onTap: () => onReveal(clue.id),
            ),
            const SizedBox(height: CockpitSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _ClueTile extends StatelessWidget {
  const _ClueTile({
    required this.clue,
    required this.revealed,
    required this.onTap,
  });

  final ScenarioClue clue;
  final bool revealed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: revealed
          ? scheme.primary.withValues(alpha: 0.05)
          : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(CockpitRadii.md),
      child: InkWell(
        onTap: revealed ? null : onTap,
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        child: Container(
          padding: const EdgeInsets.all(CockpitSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CockpitRadii.md),
            border: Border.all(
              color: revealed
                  ? scheme.primary.withValues(alpha: 0.3)
                  : scheme.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    revealed
                        ? Icons.check_circle_rounded
                        : Icons.lock_outline_rounded,
                    size: 16,
                    color: revealed
                        ? StudyPalette.success
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: CockpitSpacing.sm),
                  Expanded(
                    child: Text(
                      clue.label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (!revealed)
                    Text(
                      'Inspect',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              if (revealed) ...[
                const SizedBox(height: CockpitSpacing.xs),
                Text(
                  clue.detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Decision panel
// ---------------------------------------------------------------------------

class _DecisionPanel extends StatelessWidget {
  const _DecisionPanel({
    required this.scenario,
    required this.selectedOptionId,
    required this.onSelect,
  });

  final Scenario scenario;
  final String? selectedOptionId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final answered = selectedOptionId != null;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline_rounded,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: CockpitSpacing.xs),
              Text(
                'What would you do first?',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Choose the best initial action.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: CockpitSpacing.md),
          for (final option in scenario.options) ...[
            _OptionTile(
              option: option,
              selected: option.id == selectedOptionId,
              answered: answered,
              isCorrect: scenario.isCorrect(option.id),
              onTap: answered ? null : () => onSelect(option.id),
            ),
            const SizedBox(height: CockpitSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.selected,
    required this.answered,
    required this.isCorrect,
    required this.onTap,
  });

  final ScenarioOption option;
  final bool selected;
  final bool answered;
  final bool isCorrect;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // After answering, highlight the correct one (green) and a wrong pick (red).
    Color border = scheme.outlineVariant;
    Color? bg;
    if (answered) {
      if (isCorrect) {
        border = StudyPalette.success;
        bg = StudyPalette.success.withValues(alpha: 0.08);
      } else if (selected) {
        border = StudyPalette.danger;
        bg = StudyPalette.danger.withValues(alpha: 0.08);
      }
    } else if (selected) {
      border = scheme.primary;
      bg = scheme.primary.withValues(alpha: 0.06);
    }

    final IconData marker;
    Color markerColor = scheme.onSurfaceVariant;
    if (answered && isCorrect) {
      marker = Icons.check_circle_rounded;
      markerColor = StudyPalette.success;
    } else if (answered && selected) {
      marker = Icons.cancel_rounded;
      markerColor = StudyPalette.danger;
    } else if (selected) {
      marker = Icons.radio_button_checked_rounded;
      markerColor = scheme.primary;
    } else {
      marker = Icons.radio_button_unchecked_rounded;
    }

    return Material(
      color: bg ?? scheme.surface,
      borderRadius: BorderRadius.circular(CockpitRadii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        child: Container(
          padding: const EdgeInsets.all(CockpitSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CockpitRadii.md),
            border: Border.all(
              color: border,
              width: selected || (answered && isCorrect) ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(marker, size: 20, color: markerColor),
              const SizedBox(width: CockpitSpacing.md),
              Expanded(
                child: Text(
                  option.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
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

// ---------------------------------------------------------------------------
// AI reasoning feedback
// ---------------------------------------------------------------------------

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.scenario, required this.correct});
  final Scenario scenario;
  final bool correct;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = correct ? StudyPalette.success : StudyPalette.warning;

    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(CockpitRadii.xl),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                correct ? Icons.emoji_events_rounded : Icons.school_rounded,
                color: accent,
                size: 22,
              ),
              const SizedBox(width: CockpitSpacing.sm),
              Text(
                correct ? 'Excellent! 🎉' : "Good thinking — here's why",
                style: theme.textTheme.titleSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Text(
            scenario.reasoning,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
          if (scenario.outcomeLabel.isNotEmpty) ...[
            const SizedBox(height: CockpitSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: CockpitSpacing.md,
                vertical: CockpitSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(CockpitRadii.pill),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.flag_rounded, size: 15, color: accent),
                  const SizedBox(width: CockpitSpacing.xs),
                  Flexible(
                    child: Text(
                      scenario.outcomeLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Learning reflection
// ---------------------------------------------------------------------------

class _ReflectionCard extends StatelessWidget {
  const _ReflectionCard({required this.scenario});
  final Scenario scenario;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (scenario.skills.isNotEmpty) ...[
            Row(
              children: [
                Icon(
                  Icons.track_changes_rounded,
                  size: 16,
                  color: scheme.primary,
                ),
                const SizedBox(width: CockpitSpacing.xs),
                Text(
                  'What you practiced',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: CockpitSpacing.sm),
            for (final s in scenario.skills)
              Padding(
                padding: const EdgeInsets.only(bottom: CockpitSpacing.xs),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 15,
                      color: StudyPalette.success,
                    ),
                    const SizedBox(width: CockpitSpacing.xs),
                    Expanded(child: Text(s, style: theme.textTheme.bodySmall)),
                  ],
                ),
              ),
          ],
          if (scenario.relatedTopics.isNotEmpty) ...[
            const SizedBox(height: CockpitSpacing.md),
            Row(
              children: [
                Icon(Icons.menu_book_rounded, size: 16, color: scheme.primary),
                const SizedBox(width: CockpitSpacing.xs),
                Text(
                  'Related lessons',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: CockpitSpacing.sm),
            Wrap(
              spacing: CockpitSpacing.sm,
              runSpacing: CockpitSpacing.xs,
              children: [
                for (final t in scenario.relatedTopics)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: CockpitSpacing.md,
                        vertical: CockpitSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.secondary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(CockpitRadii.pill),
                        border: Border.all(
                          color: scheme.secondary.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        t,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.secondary,
                        ),
                      ),
                    ),
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
// Bottom actions
// ---------------------------------------------------------------------------

class _ActionsBar extends StatelessWidget {
  const _ActionsBar({
    required this.onAnother,
    required this.onReviewLesson,
    required this.onContinue,
  });

  final VoidCallback onAnother;
  final VoidCallback onReviewLesson;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _OutlineButton(
            icon: Icons.refresh_rounded,
            label: 'Try Another',
            onTap: onAnother,
          ),
        ),
        const SizedBox(width: CockpitSpacing.sm),
        Expanded(
          child: _OutlineButton(
            icon: Icons.menu_book_outlined,
            label: 'Review Lesson',
            onTap: onReviewLesson,
          ),
        ),
        const SizedBox(width: CockpitSpacing.sm),
        Expanded(
          child: _GradientButton(
            icon: Icons.arrow_forward_rounded,
            label: 'Continue',
            onTap: onContinue,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.onBack});
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      children: [
        _Header(title: title, index: 0, total: 0, onBack: onBack),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(CockpitSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.track_changes_rounded,
                    size: 48,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: CockpitSpacing.md),
                  Text(
                    'No scenarios yet',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: CockpitSpacing.xs),
                  Text(
                    'This studio has no application scenarios yet. Upload '
                    'material and rebuild to generate them.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

class _Card extends StatelessWidget {
  const _Card({required this.child});
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
          child: SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: scheme.onSurface),
                const SizedBox(width: CockpitSpacing.xs),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
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
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
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
                const SizedBox(width: CockpitSpacing.xs),
                Icon(icon, size: 18, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
