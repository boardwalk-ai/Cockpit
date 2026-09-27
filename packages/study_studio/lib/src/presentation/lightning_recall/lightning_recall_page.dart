import 'dart:async';

import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../domain/entities/studio.dart';
import '../widgets/mobile_layout.dart';
import '../widgets/studio_palette.dart';
import '../widgets/studio_scaffold.dart';

/// Seconds allowed per question before the countdown ring empties.
const _perQuestionSeconds = 7;

/// Weak-topic chips shown in the session summary before collapsing to "+N more".
const _maxWeakChips = 8;

/// Screen 9 — Lightning Recall.
///
/// Rapid-fire recall session with countdown timer, streak tracking, and
/// instant feedback. Questions and stats are pulled from the live [Studio]'s
/// quiz bank via [studioProvider]; grading uses the studio's own answers.
class LightningRecallPage extends ConsumerWidget {
  const LightningRecallPage({super.key, required this.studioId});

  final String studioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(studioProvider(studioId));

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (studio) => _RecallSession(studio: studio),
        ),
      ),
    );
  }
}

/// Holds the live session state once the studio has loaded.
class _RecallSession extends StatefulWidget {
  const _RecallSession({required this.studio});

  final Studio studio;

  @override
  State<_RecallSession> createState() => _RecallSessionState();
}

class _RecallSessionState extends State<_RecallSession> {
  final _answerController = TextEditingController();
  Timer? _countdownTimer;

  late final List<_RecallQuestion> _questions;
  late final List<String> _weakTopics;

  int _questionIndex = 0;
  int _streak = 0;
  int _bestStreak = 0;
  int _answeredCount = 0;
  int _correctCount = 0;
  int _countdown = _perQuestionSeconds;
  bool _paused = false;
  bool _showHint = false;
  bool _showFeedback = false;
  bool _answered = false;
  bool _answeredCorrectly = false;

  @override
  void initState() {
    super.initState();
    // Flatten every Study Object's quiz bank into a single recall queue.
    _questions = [
      for (final topic in widget.studio.topics)
        for (final q in topic.quizQuestions)
          _RecallQuestion(
            text: q.question,
            answer: q.answer,
            hint: q.relatedConcept ?? 'Topic: ${topic.title}',
            explanation: q.explanation,
          ),
    ];
    _weakTopics = [for (final t in widget.studio.weakTopics) t.title];
    if (_questions.isNotEmpty) _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _answerController.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    if (_paused) return;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _paused) return;
      setState(() {
        if (_countdown > 0) {
          _countdown--;
        } else {
          _countdownTimer?.cancel();
        }
      });
    });
  }

  _RecallQuestion get _current =>
      _questions[_questionIndex % _questions.length];

  double get _progress =>
      _questions.isEmpty ? 0 : (_questionIndex + 1) / _questions.length;

  void _submitAnswer() {
    if (_answered) return; // Already graded — don't double-count the streak.
    final input = _answerController.text.trim();
    if (input.isEmpty) return;
    final correct = _current.matches(input);
    setState(() {
      _answered = true;
      _showFeedback = true;
      _answeredCorrectly = correct;
      _answeredCount++;
      if (correct) {
        _correctCount++;
        _streak++;
        if (_streak > _bestStreak) _bestStreak = _streak;
      } else {
        _streak = 0;
      }
    });
    _countdownTimer?.cancel();
  }

  void _nextQuestion() {
    if (_questionIndex + 1 >= _questions.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session complete — great work!')),
      );
      return;
    }
    setState(() {
      _questionIndex++;
      _answerController.clear();
      _showHint = false;
      _showFeedback = false;
      _answered = false;
      _answeredCorrectly = false;
      _countdown = _perQuestionSeconds;
    });
    _startCountdown();
  }

  void _skip() => _nextQuestion();

  void _togglePause() {
    setState(() => _paused = !_paused);
    if (_paused) {
      _countdownTimer?.cancel();
    } else {
      _startCountdown();
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = '/study/${widget.studio.id}';

    if (_questions.isEmpty) {
      return _EmptyRecall(examTitle: widget.studio.title, base: base);
    }

    final accuracy = _answeredCount == 0
        ? 0
        : (_correctCount / _answeredCount * 100).round();

    return _LightningRecallBody(
      examTitle: widget.studio.title,
      questionIndex: _questionIndex,
      totalQuestions: _questions.length,
      topicCount: widget.studio.topicCount,
      weakCount: widget.studio.weakTopics.length,
      flashcardCount: widget.studio.flashcardCount,
      weakTopics: _weakTopics,
      progress: _progress,
      streak: _streak,
      bestStreak: _bestStreak,
      answeredCount: _answeredCount,
      accuracy: accuracy,
      countdown: _countdown,
      paused: _paused,
      showHint: _showHint,
      showFeedback: _showFeedback,
      answered: _answered,
      answeredCorrectly: _answeredCorrectly,
      question: _current,
      answerController: _answerController,
      onSubmit: _submitAnswer,
      onHint: () => setState(() => _showHint = true),
      onSkip: _skip,
      onTogglePause: _togglePause,
      onNext: _nextQuestion,
      onEnd: () => context.go(base),
      onBack: () => context.go(base),
    );
  }
}

class _RecallQuestion {
  const _RecallQuestion({
    required this.text,
    required this.answer,
    required this.hint,
    required this.explanation,
  });

  final String text;
  final String answer;
  final String hint;
  final String explanation;

  /// Lenient match against the studio's canonical answer: exact, or either
  /// string containing the other (guarded by length to avoid trivial hits).
  bool matches(String input) {
    final a = answer.trim().toLowerCase();
    final n = input.trim().toLowerCase();
    if (n.isEmpty) return false;
    return n == a ||
        (a.length > 3 && n.contains(a)) ||
        (n.length > 3 && a.contains(n));
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyRecall extends StatelessWidget {
  const _EmptyRecall({required this.examTitle, required this.base});

  final String examTitle;
  final String base;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      children: [
        _Header(examTitle: examTitle, onBack: () => context.go(base)),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(CockpitSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bolt_rounded,
                    size: 48,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: CockpitSpacing.md),
                  Text(
                    'No recall questions yet',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: CockpitSpacing.xs),
                  Text(
                    'This studio has no quiz questions to recall from. Generate '
                    'a quiz first, then come back.',
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
// Body
// ---------------------------------------------------------------------------

class _LightningRecallBody extends StatelessWidget {
  const _LightningRecallBody({
    required this.examTitle,
    required this.questionIndex,
    required this.totalQuestions,
    required this.topicCount,
    required this.weakCount,
    required this.flashcardCount,
    required this.weakTopics,
    required this.progress,
    required this.streak,
    required this.bestStreak,
    required this.answeredCount,
    required this.accuracy,
    required this.countdown,
    required this.paused,
    required this.showHint,
    required this.showFeedback,
    required this.answered,
    required this.answeredCorrectly,
    required this.question,
    required this.answerController,
    required this.onSubmit,
    required this.onHint,
    required this.onSkip,
    required this.onTogglePause,
    required this.onNext,
    required this.onEnd,
    required this.onBack,
  });

  final String examTitle;
  final int questionIndex;
  final int totalQuestions;
  final int topicCount;
  final int weakCount;
  final int flashcardCount;
  final List<String> weakTopics;
  final double progress;
  final int streak;
  final int bestStreak;
  final int answeredCount;
  final int accuracy;
  final int countdown;
  final bool paused;
  final bool showHint;
  final bool showFeedback;
  final bool answered;
  final bool answeredCorrectly;
  final _RecallQuestion question;
  final TextEditingController answerController;
  final VoidCallback onSubmit;
  final VoidCallback onHint;
  final VoidCallback onSkip;
  final VoidCallback onTogglePause;
  final VoidCallback onNext;
  final VoidCallback onEnd;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final summary = _SessionSummaryCard(
      total: totalQuestions,
      topics: topicCount,
      weak: weakCount,
      flashcards: flashcardCount,
      weakTopics: weakTopics,
    );
    final progressBar = _QuestionProgress(
      index: questionIndex,
      total: totalQuestions,
      progress: progress,
    );
    final flow = _FlowStateCard(streak: streak);
    final questionCard = _QuestionCard(
      streak: streak,
      countdown: countdown,
      paused: paused,
      answered: answered,
      showHint: showHint,
      question: question,
      answerController: answerController,
      onSubmit: onSubmit,
      onHint: onHint,
    );
    final feedback = showFeedback
        ? _FeedbackCard(
            correct: answeredCorrectly,
            answer: question.answer,
            explanation: question.explanation,
          )
        : null;
    final metrics = showFeedback
        ? _MetricsRow(
            answered: answeredCount,
            total: totalQuestions,
            accuracy: accuracy,
            bestStreak: bestStreak,
          )
        : null;
    final controls = _ControlRow(
      paused: paused,
      onSkip: onSkip,
      onTogglePause: onTogglePause,
      onEnd: onEnd,
    );
    final nextButton = _GradientButton(
      icon: Icons.bolt_rounded,
      label: 'Next Question',
      onTap: onNext,
    );

    return Column(
      children: [
        _Header(examTitle: examTitle, onBack: onBack),
        Expanded(
          child: isDesktop(context)
              ? _desktop(
                  summary: summary,
                  progressBar: progressBar,
                  flow: flow,
                  questionCard: questionCard,
                  feedback: feedback,
                  metrics: metrics,
                  controls: controls,
                  nextButton: nextButton,
                )
              : _mobile(
                  summary: summary,
                  progressBar: progressBar,
                  flow: flow,
                  questionCard: questionCard,
                  feedback: feedback,
                  metrics: metrics,
                  controls: controls,
                  nextButton: nextButton,
                ),
        ),
      ],
    );
  }

  /// Mobile / narrow: single stacked column, centred at a comfortable width.
  Widget _mobile({
    required Widget summary,
    required Widget progressBar,
    required Widget flow,
    required Widget questionCard,
    required Widget? feedback,
    required Widget? metrics,
    required Widget controls,
    required Widget nextButton,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(
          padding: const EdgeInsets.only(bottom: CockpitSpacing.xl),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CockpitSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  summary,
                  const SizedBox(height: CockpitSpacing.lg),
                  progressBar,
                  const SizedBox(height: CockpitSpacing.md),
                  flow,
                  const SizedBox(height: CockpitSpacing.lg),
                  questionCard,
                  if (feedback != null) ...[
                    const SizedBox(height: CockpitSpacing.md),
                    feedback,
                    const SizedBox(height: CockpitSpacing.md),
                    metrics!,
                  ],
                  const SizedBox(height: CockpitSpacing.lg),
                  controls,
                  const SizedBox(height: CockpitSpacing.md),
                  nextButton,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Desktop / wide: THREE columns with the question centred as the focus —
  /// left = live session feedback, centre = the question (widest), right =
  /// session summary + weak topics.
  Widget _desktop({
    required Widget summary,
    required Widget progressBar,
    required Widget flow,
    required Widget questionCard,
    required Widget? feedback,
    required Widget? metrics,
    required Widget controls,
    required Widget nextButton,
  }) {
    return Padding(
      // Full viewport width (minus a small gutter) — no centred max-width cap,
      // so the three columns fill the screen instead of leaving big side
      // margins. Right column is wider (flex 4) for the dense session summary.
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left — live session feedback (flow state, metrics).
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  flow,
                  if (metrics != null) ...[
                    const SizedBox(height: CockpitSpacing.lg),
                    metrics,
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 24),
          // Centre — the question you're answering (the main focus).
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  progressBar,
                  const SizedBox(height: CockpitSpacing.lg),
                  questionCard,
                  if (feedback != null) ...[
                    const SizedBox(height: CockpitSpacing.md),
                    feedback,
                  ],
                  const SizedBox(height: CockpitSpacing.lg),
                  controls,
                  const SizedBox(height: CockpitSpacing.md),
                  nextButton,
                ],
              ),
            ),
          ),
          const SizedBox(width: 24),
          // Right — session summary + weak topics.
          Expanded(flex: 4, child: SingleChildScrollView(child: summary)),
        ],
      ),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  examTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: CockpitSpacing.xs,
                  runSpacing: CockpitSpacing.xxs,
                  children: [
                    Icon(Icons.bolt_rounded, size: 14, color: scheme.primary),
                    Text(
                      'Lightning Recall',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '•',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      'Rapid Recall',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          _CircleButton(
            icon: Icons.bar_chart_rounded,
            onTap: () => soon('Analytics'),
          ),
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
// Session summary
// ---------------------------------------------------------------------------

class _SessionSummaryCard extends StatelessWidget {
  const _SessionSummaryCard({
    required this.total,
    required this.topics,
    required this.weak,
    required this.flashcards,
    required this.weakTopics,
  });

  final int total;
  final int topics;
  final int weak;
  final int flashcards;
  final List<String> weakTopics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final stats = [
      _SessionStat(
        icon: Icons.layers_outlined,
        value: '$total',
        label: 'Total',
      ),
      _SessionStat(
        icon: Icons.menu_book_outlined,
        value: '$topics',
        label: 'Topics',
      ),
      _SessionStat(
        icon: Icons.local_fire_department_rounded,
        value: '$weak',
        label: 'Weak',
        valueColor: true,
      ),
      _SessionStat(
        icon: Icons.style_outlined,
        value: '$flashcards',
        label: 'Flashcards',
      ),
    ];

    return _OutlinedCard(
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
                  color: scheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.bolt_rounded,
                  size: 20,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: CockpitSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lightning Recall',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Rapid-fire questions to build instant recall.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              if (isMobilePlatform(context)) {
                return Wrap(spacing: 24, runSpacing: 16, children: stats);
              }
              if (constraints.maxWidth < 360) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < stats.length; i++) ...[
                        if (i > 0)
                          Container(
                            width: 1,
                            height: 44,
                            margin: const EdgeInsets.symmetric(
                              horizontal: CockpitSpacing.md,
                            ),
                            color: scheme.outlineVariant,
                          ),
                        stats[i],
                      ],
                    ],
                  ),
                );
              }

              return Row(
                children: [
                  for (var i = 0; i < stats.length; i++) ...[
                    if (i > 0)
                      Container(
                        width: 1,
                        height: 44,
                        margin: const EdgeInsets.symmetric(
                          horizontal: CockpitSpacing.sm,
                        ),
                        color: scheme.outlineVariant,
                      ),
                    Expanded(child: stats[i]),
                  ],
                ],
              );
            },
          ),
          if (weakTopics.isNotEmpty) ...[
            const SizedBox(height: CockpitSpacing.lg),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: CockpitSpacing.md,
                vertical: CockpitSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(CockpitRadii.md),
              ),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: CockpitSpacing.sm,
                runSpacing: CockpitSpacing.xs,
                children: [
                  MobileWrap(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.track_changes_rounded,
                        size: 14,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: CockpitSpacing.xs),
                      Text(
                        'Weak topics included:',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  for (final topic in weakTopics.take(_maxWeakChips))
                    _TopicChip(label: topic),
                  if (weakTopics.length > _maxWeakChips)
                    _TopicChip(
                      label: '+${weakTopics.length - _maxWeakChips} more',
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

/// A weak-topic pill. Unlike the shared [TagChip], it caps its width and
/// ellipsizes the label so long topic names (e.g. "Instruction Set Architecture
/// and Execution Cycle") never overflow the dense session-summary panel.
class _TopicChip extends StatelessWidget {
  const _TopicChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme.secondary;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 200),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.md,
          vertical: CockpitSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(CockpitRadii.pill),
          border: Border.all(color: c.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(color: c),
        ),
      ),
    );
  }
}

class _SessionStat extends StatelessWidget {
  const _SessionStat({
    required this.icon,
    required this.value,
    required this.label,
    this.valueColor = false,
  });

  final IconData icon;
  final String value;
  final String label;
  final bool valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(height: CockpitSpacing.xs),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: valueColor ? scheme.primary : null,
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: valueColor ? scheme.primary : scheme.onSurfaceVariant,
            fontSize: 10,
            fontWeight: valueColor ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Progress
// ---------------------------------------------------------------------------

class _QuestionProgress extends StatelessWidget {
  const _QuestionProgress({
    required this.index,
    required this.total,
    required this.progress,
  });

  final int index;
  final int total;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pct = (progress * 100).round();

    return Column(
      children: [
        MobileWrap(
          children: [
            Text.rich(
              TextSpan(
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                children: [
                  const TextSpan(text: 'Question '),
                  TextSpan(
                    text: '${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(text: ' / $total'),
                ],
              ),
            ),
            const Spacer(),
            Text(
              '$pct% Complete',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: CockpitSpacing.sm),
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
// Flow state
// ---------------------------------------------------------------------------

class _FlowStateCard extends StatelessWidget {
  const _FlowStateCard({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Flow segments light up with the current streak (capped at 7).
    final lit = streak.clamp(0, 7);
    final (label, message) = switch (lit) {
      >= 5 => ('Excellent', "You're in the zone! Keep the streak going."),
      >= 2 => ('Warming up', 'Nice — string a few more together.'),
      _ => ('Getting started', 'Answer correctly to build your flow.'),
    };

    return _OutlinedCard(
      padding: const EdgeInsets.symmetric(
        horizontal: CockpitSpacing.lg,
        vertical: CockpitSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: scheme.primary),
              const SizedBox(width: CockpitSpacing.xs),
              Text(
                'Flow State',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.md),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Container(
                          height: 8,
                          margin: EdgeInsets.only(
                            right: i < 6 ? CockpitSpacing.xs : 0,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              CockpitRadii.pill,
                            ),
                            gradient: i < lit
                                ? LinearGradient(
                                    colors: [
                                      scheme.primary,
                                      Color.lerp(
                                        scheme.primary,
                                        StudyPalette.pink,
                                        lit <= 1 ? 0 : i / (lit - 1),
                                      )!,
                                    ],
                                  )
                                : null,
                            color: i >= lit
                                ? scheme.surfaceContainerHighest
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: CockpitSpacing.sm),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary.withValues(alpha: 0.15),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.35),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.diamond_rounded,
                  size: 14,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Question card
// ---------------------------------------------------------------------------

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.streak,
    required this.countdown,
    required this.paused,
    required this.answered,
    required this.showHint,
    required this.question,
    required this.answerController,
    required this.onSubmit,
    required this.onHint,
  });

  final int streak;
  final int countdown;
  final bool paused;
  final bool answered;
  final bool showHint;
  final _RecallQuestion question;
  final TextEditingController answerController;
  final VoidCallback onSubmit;
  final VoidCallback onHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final countdownProgress = countdown / _perQuestionSeconds;

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
        children: [
          Row(
            children: [
              const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bolt_rounded, size: 16, color: scheme.primary),
                  const SizedBox(width: CockpitSpacing.xs),
                  Text(
                    'Streak $streak',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.sm),
          SizedBox(
            width: 88,
            height: 88,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 88,
                  height: 88,
                  child: CircularProgressIndicator(
                    value: 1,
                    strokeWidth: 6,
                    valueColor: AlwaysStoppedAnimation(
                      scheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                SizedBox(
                  width: 88,
                  height: 88,
                  child: CircularProgressIndicator(
                    value: countdownProgress.clamp(0, 1),
                    strokeWidth: 6,
                    strokeCap: StrokeCap.round,
                    valueColor: AlwaysStoppedAnimation(
                      countdown == 0 ? scheme.error : scheme.primary,
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$countdown',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'SECONDS',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: 9,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: CockpitSpacing.lg),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: CockpitSpacing.md,
              vertical: CockpitSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(CockpitRadii.pill),
            ),
            child: Text(
              'QUESTION',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: CockpitSpacing.md),
          Text(
            question.text,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: CockpitSpacing.lg),
          TextField(
            controller: answerController,
            enabled: !paused && !answered,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit(),
            decoration: InputDecoration(
              hintText: 'Type your answer...',
              filled: true,
              fillColor: scheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CockpitRadii.lg),
                borderSide: BorderSide(color: scheme.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CockpitRadii.lg),
                borderSide: BorderSide(color: scheme.outlineVariant),
              ),
            ),
          ),
          const SizedBox(height: CockpitSpacing.xs),
          Text(
            answered
                ? 'Tap Next Question to continue'
                : 'Press Enter to submit',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (showHint) ...[
            const SizedBox(height: CockpitSpacing.sm),
            Text(
              question.hint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: CockpitSpacing.md),
          TextButton.icon(
            onPressed: (paused || answered) ? null : onHint,
            icon: Icon(Icons.lightbulb_outline_rounded, color: scheme.primary),
            label: Text(
              "Can't recall? Show hint",
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Feedback + metrics
// ---------------------------------------------------------------------------

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({
    required this.correct,
    required this.answer,
    required this.explanation,
  });

  final bool correct;
  final String answer;
  final String explanation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Colour and icon follow correctness — a wrong answer must never read green.
    final accent = correct
        ? CockpitColors.brand.success
        : CockpitColors.brand.error;

    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.md),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: accent,
                size: 22,
              ),
              const SizedBox(width: CockpitSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      correct ? 'Correct! 🎉' : 'Not quite',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (!correct) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Answer: $answer',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      explanation,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
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

class _MetricsRow extends StatelessWidget {
  const _MetricsRow({
    required this.answered,
    required this.total,
    required this.accuracy,
    required this.bestStreak,
  });

  final int answered;
  final int total;
  final int accuracy;
  final int bestStreak;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      _MetricTile(
        icon: Icons.checklist_rounded,
        label: 'Answered',
        value: '$answered/$total',
        detail: 'This session',
      ),
      _MetricTile(
        icon: Icons.track_changes_rounded,
        label: 'Accuracy',
        value: '$accuracy%',
        detail: accuracy >= 80 ? 'Excellent' : 'Keep going',
      ),
      _MetricTile(
        icon: Icons.local_fire_department_rounded,
        label: 'Best Streak',
        value: '$bestStreak',
        detail: 'In a row',
      ),
    ];

    return Row(
      children: [
        for (var i = 0; i < metrics.length; i++) ...[
          if (i > 0) const SizedBox(width: CockpitSpacing.sm),
          Expanded(child: metrics[i]),
        ],
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return _OutlinedCard(
      padding: const EdgeInsets.all(CockpitSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(height: CockpitSpacing.xs),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 10,
              height: 1.2,
            ),
          ),
          const SizedBox(height: CockpitSpacing.xs),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Controls
// ---------------------------------------------------------------------------

class _ControlRow extends StatelessWidget {
  const _ControlRow({
    required this.paused,
    required this.onSkip,
    required this.onTogglePause,
    required this.onEnd,
  });

  final bool paused;
  final VoidCallback onSkip;
  final VoidCallback onTogglePause;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final error = CockpitColors.brand.error;

    return Row(
      children: [
        Expanded(
          child: _OutlineActionButton(
            icon: Icons.skip_next_rounded,
            label: 'Skip',
            onTap: onSkip,
          ),
        ),
        const SizedBox(width: CockpitSpacing.sm),
        Expanded(
          child: _OutlineActionButton(
            icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            label: paused ? 'Resume' : 'Pause',
            onTap: onTogglePause,
            filled: true,
          ),
        ),
        const SizedBox(width: CockpitSpacing.sm),
        Expanded(
          child: _OutlineActionButton(
            icon: Icons.stop_circle_outlined,
            label: 'End Session',
            onTap: onEnd,
            borderColor: error,
            foregroundColor: error,
          ),
        ),
      ],
    );
  }
}

class _OutlineActionButton extends StatelessWidget {
  const _OutlineActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
    this.borderColor,
    this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;
  final Color? borderColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = foregroundColor ?? scheme.onSurface;
    final border = borderColor ?? scheme.outlineVariant;
    final bg = filled ? scheme.primary.withValues(alpha: 0.08) : scheme.surface;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(CockpitRadii.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CockpitRadii.lg),
            border: Border.all(color: border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: CockpitSpacing.md,
              horizontal: CockpitSpacing.xs,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(height: CockpitSpacing.xs),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
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

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _OutlinedCard extends StatelessWidget {
  const _OutlinedCard({
    required this.child,
    this.padding = const EdgeInsets.all(CockpitSpacing.lg),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: padding,
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
            width: double.infinity,
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: CockpitSpacing.sm),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
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
