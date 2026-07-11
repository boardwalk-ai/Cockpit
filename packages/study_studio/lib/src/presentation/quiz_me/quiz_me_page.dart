import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../domain/entities/quiz_question.dart';
import '../../domain/entities/studio.dart';

/// Screen 7 — Quiz Me.
///
/// Not a list of questions: an AI-guided assessment that changes pace after the
/// calm of Teach Me. Intro → one question at a time with a confidence meter →
/// in-place feedback that reinforces learning → a completion that hands off to
/// Lightning Recall. Same visual language + Outfit.
class QuizMePage extends ConsumerStatefulWidget {
  const QuizMePage({super.key, required this.studioId, this.topicId});
  final String studioId;
  final String? topicId;

  @override
  ConsumerState<QuizMePage> createState() => _QuizMePageState();
}

enum _Phase { intro, quiz, done }

enum _Confidence { guessing, somewhat, very }

class _QuizMePageState extends ConsumerState<QuizMePage> {
  _Phase _phase = _Phase.intro;
  int _index = 0;

  // Per-question state so navigating back restores prior answers.
  final _selected = <int, String>{};
  final _confidence = <int, _Confidence>{};
  final _submitted = <int>{};
  final _correct = <int, bool>{};
  final _text = TextEditingController();

  List<QuizQuestion> _questions(Studio studio) {
    final topics = widget.topicId == null
        ? studio.topics
        : studio.topics.where((t) => t.id == widget.topicId);
    return [for (final t in topics) ...t.quizQuestions];
  }

  Future<void> _submit(QuizQuestion q) async {
    if (_submitted.contains(_index)) return;
    final response = _selected[_index] ?? '';
    final correct = q.isCorrect(response);
    await ref.read(studioRepositoryProvider).recordQuizResult(
          studioId: widget.studioId,
          topicId: q.topicId,
          correct: correct,
        );
    if (!mounted) return;
    setState(() {
      _submitted.add(_index);
      _correct[_index] = correct;
    });
  }

  void _goto(int i, int total) {
    setState(() {
      _index = i.clamp(0, total - 1);
      _text.text = _selected[_index] ?? '';
    });
  }

  int get _score => _correct.values.where((c) => c).length;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(studioProvider(widget.studioId));
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (studio) {
                final questions = _questions(studio);
                if (questions.isEmpty) {
                  return const EmptyState(
                    icon: Icons.quiz_outlined,
                    title: 'No quiz questions',
                    message: 'This selection has no questions yet.',
                  );
                }
                return _build(context, studio, questions);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _build(BuildContext context, Studio studio, List<QuizQuestion> qs) {
    final total = qs.length;
    final topicTitle = widget.topicId == null
        ? 'All topics'
        : (studio.topics
                .where((t) => t.id == widget.topicId)
                .map((t) => t.title)
                .firstOrNull ??
            'Quiz');

    void close() {
      ref.invalidate(studioProvider(widget.studioId));
      context.go('/study/${widget.studioId}');
    }

    final progress = switch (_phase) {
      _Phase.intro => 0.0,
      _Phase.done => 1.0,
      _Phase.quiz => (_index + (_submitted.contains(_index) ? 1 : 0)) / total,
    };

    return Column(
      children: [
        _Header(
          studioTitle: studio.title,
          topicTitle: topicTitle,
          index: _index,
          total: total,
          showProgress: _phase == _Phase.quiz,
          progress: progress,
          onClose: close,
        ),
        Expanded(
          child: switch (_phase) {
            _Phase.intro => _Intro(
                total: total,
                onStart: () => setState(() => _phase = _Phase.quiz),
              ),
            _Phase.done => _Completion(
                score: _score,
                total: total,
                confusedTopics: _confusedTopics(studio, qs),
                onLightning: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Lightning Recall — Phase 2')),
                ),
                onBack: close,
              ),
            _Phase.quiz => _QuestionView(
                key: ValueKey(_index),
                q: qs[_index],
                index: _index,
                total: total,
                selected: _selected[_index],
                confidence: _confidence[_index],
                submitted: _submitted.contains(_index),
                correct: _correct[_index] ?? false,
                textController: _text,
                studioId: widget.studioId,
                topicTitle: _topicTitleFor(studio, qs[_index].topicId),
                onSelect: (v) => setState(() => _selected[_index] = v),
                onText: (v) => _selected[_index] = v,
                onConfidence: (c) => setState(() => _confidence[_index] = c),
                onSubmit: () => _submit(qs[_index]),
              ),
          },
        ),
        if (_phase == _Phase.quiz)
          _QuizNav(
            index: _index,
            total: total,
            canNext: _submitted.contains(_index),
            onPrev: _index > 0 ? () => _goto(_index - 1, total) : null,
            onNext: () {
              if (_index + 1 >= total) {
                setState(() => _phase = _Phase.done);
              } else {
                _goto(_index + 1, total);
              }
            },
          ),
      ],
    );
  }

  String _topicTitleFor(Studio studio, String topicId) =>
      studio.topics.where((t) => t.id == topicId).map((t) => t.title).firstOrNull ??
      'this topic';

  List<String> _confusedTopics(Studio studio, List<QuizQuestion> qs) {
    final titles = <String>{};
    for (final entry in _correct.entries) {
      if (entry.value == false) {
        titles.add(_topicTitleFor(studio, qs[entry.key].topicId));
      }
    }
    return titles.take(3).toList();
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.studioTitle,
    required this.topicTitle,
    required this.index,
    required this.total,
    required this.showProgress,
    required this.progress,
    required this.onClose,
  });
  final String studioTitle;
  final String topicTitle;
  final int index;
  final int total;
  final bool showProgress;
  final double progress;
  final VoidCallback onClose;

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
      child: Column(
        children: [
          Row(
            children: [
              _CircleButton(icon: Icons.close, onTap: onClose),
              const SizedBox(width: CockpitSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      studioTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Row(
                      children: [
                        Icon(Icons.help_rounded, size: 13, color: scheme.error),
                        const SizedBox(width: 4),
                        Text(
                          'Quiz Me',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '  ·  $topicTitle',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (showProgress)
                Text(
                  'Q ${index + 1}/$total',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
            ],
          ),
          if (showProgress) ...[
            const SizedBox(height: CockpitSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(CockpitRadii.pill),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Intro
// ---------------------------------------------------------------------------

class _Intro extends StatelessWidget {
  const _Intro({required this.total, required this.onStart});
  final int total;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final minutes = (total * 0.5).ceil().clamp(1, 999);
    return ListView(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      children: [
        const SizedBox(height: CockpitSpacing.xl),
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.quiz_rounded, size: 42, color: scheme.primary),
          ),
        ),
        const SizedBox(height: CockpitSpacing.lg),
        Text(
          'Quiz Ready',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: CockpitSpacing.sm),
        Text(
          "You're about to answer $total AI-generated questions based on your "
          'uploaded materials.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: CockpitSpacing.xl),
        Row(
          children: [
            Expanded(
              child: _InfoTile(
                icon: Icons.schedule,
                label: 'Estimated time',
                value: '$minutes minutes',
              ),
            ),
            const SizedBox(width: CockpitSpacing.md),
            Expanded(
              child: _InfoTile(
                icon: Icons.auto_graph,
                label: 'Difficulty',
                value: 'Adaptive',
                valueColor: scheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: CockpitSpacing.md),
        Container(
          padding: const EdgeInsets.all(CockpitSpacing.md),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(CockpitRadii.md),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: scheme.primary),
              const SizedBox(width: CockpitSpacing.sm),
              Expanded(
                child: Text(
                  'Questions become harder or easier depending on your '
                  'performance.',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: CockpitSpacing.xl),
        _GradientButton(
          icon: Icons.play_arrow_rounded,
          label: 'Start Quiz',
          onTap: onStart,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Question
// ---------------------------------------------------------------------------

class _QuestionView extends StatelessWidget {
  const _QuestionView({
    super.key,
    required this.q,
    required this.index,
    required this.total,
    required this.selected,
    required this.confidence,
    required this.submitted,
    required this.correct,
    required this.textController,
    required this.studioId,
    required this.topicTitle,
    required this.onSelect,
    required this.onText,
    required this.onConfidence,
    required this.onSubmit,
  });

  final QuizQuestion q;
  final int index;
  final int total;
  final String? selected;
  final _Confidence? confidence;
  final bool submitted;
  final bool correct;
  final TextEditingController textController;
  final String studioId;
  final String topicTitle;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onText;
  final ValueChanged<_Confidence> onConfidence;
  final VoidCallback onSubmit;

  bool get _isChoice =>
      q.type == QuizType.multipleChoice || q.type == QuizType.trueFalse;

  bool get _hasAnswer =>
      _isChoice ? selected != null : textController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      children: [
        Text(
          'Question ${index + 1}',
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: CockpitSpacing.sm),
        Text(
          q.question,
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700, height: 1.25),
        ),
        const SizedBox(height: CockpitSpacing.lg),
        if (_isChoice)
          for (final c in q.choices)
            _AnswerOption(
              label: c,
              selected: selected == c,
              submitted: submitted,
              isAnswer: c == q.answer,
              onTap: submitted ? null : () => onSelect(c),
            )
        else
          TextField(
            controller: textController,
            enabled: !submitted,
            onChanged: onText,
            decoration: const InputDecoration(hintText: 'Type your answer'),
          ),
        if (!submitted) ...[
          const SizedBox(height: CockpitSpacing.lg),
          Text(
            'How confident are you?',
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Row(
            children: [
              for (final c in _Confidence.values) ...[
                Expanded(
                  child: _ConfidenceChip(
                    level: c,
                    selected: confidence == c,
                    onTap: () => onConfidence(c),
                  ),
                ),
                if (c != _Confidence.values.last)
                  const SizedBox(width: CockpitSpacing.sm),
              ],
            ],
          ),
          const SizedBox(height: CockpitSpacing.xl),
          _GradientButton(
            icon: Icons.check_circle_outline,
            label: 'Check Answer',
            onTap: _hasAnswer ? onSubmit : null,
          ),
        ] else ...[
          const SizedBox(height: CockpitSpacing.lg),
          _Feedback(
            correct: correct,
            answer: q.answer,
            explanation: q.explanation,
            relatedConcept: q.relatedConcept,
            onReview: () =>
                context.go('/study/$studioId/teach/${q.topicId}'),
          ),
          const SizedBox(height: CockpitSpacing.md),
          _AiInsight(
            correct: correct,
            confidence: confidence,
            topicTitle: topicTitle,
          ),
        ],
      ],
    );
  }
}

class _AnswerOption extends StatelessWidget {
  const _AnswerOption({
    required this.label,
    required this.selected,
    required this.submitted,
    required this.isAnswer,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final bool submitted;
  final bool isAnswer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Colour logic: after submit, reveal correct (green) and the wrong pick (red).
    Color border = scheme.outlineVariant;
    Color bg = scheme.surface;
    Color fg = scheme.onSurface;
    IconData? trailing;
    Color? trailingColor;

    if (submitted) {
      if (isAnswer) {
        border = scheme.tertiary;
        bg = scheme.tertiary.withValues(alpha: 0.10);
        trailing = Icons.check_circle;
        trailingColor = scheme.tertiary;
      } else if (selected) {
        border = scheme.error;
        bg = scheme.error.withValues(alpha: 0.08);
        trailing = Icons.cancel;
        trailingColor = scheme.error;
      }
    } else if (selected) {
      border = scheme.primary;
      bg = scheme.primary.withValues(alpha: 0.08);
      fg = scheme.primary;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: CockpitSpacing.md),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CockpitRadii.md),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(CockpitRadii.md),
              border: Border.all(
                color: border,
                width: (selected || (submitted && isAnswer)) ? 1.8 : 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: CockpitSpacing.lg,
              vertical: CockpitSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: fg,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (trailing != null)
                  Icon(trailing, size: 20, color: trailingColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({
    required this.level,
    required this.selected,
    required this.onTap,
  });
  final _Confidence level;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (label, icon) = switch (level) {
      _Confidence.guessing => ('Guessing', Icons.help_outline),
      _Confidence.somewhat => ('Somewhat', Icons.thumbs_up_down_outlined),
      _Confidence.very => ('Very Sure', Icons.verified_outlined),
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CockpitRadii.md),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.sm),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.10)
              : scheme.surface,
          borderRadius: BorderRadius.circular(CockpitRadii.md),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                size: 18,
                color: selected ? scheme.primary : scheme.onSurfaceVariant),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Feedback extends StatelessWidget {
  const _Feedback({
    required this.correct,
    required this.answer,
    required this.explanation,
    required this.relatedConcept,
    required this.onReview,
  });
  final bool correct;
  final String answer;
  final String explanation;
  final String? relatedConcept;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = correct ? scheme.tertiary : scheme.error;
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(correct ? Icons.check_circle : Icons.cancel,
                  color: accent, size: 22),
              const SizedBox(width: CockpitSpacing.sm),
              Text(
                correct ? 'Correct!' : 'Not quite',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800, color: accent),
              ),
            ],
          ),
          if (!correct) ...[
            const SizedBox(height: CockpitSpacing.sm),
            Text.rich(
              TextSpan(
                style: theme.textTheme.bodyMedium,
                children: [
                  const TextSpan(text: 'Correct answer: '),
                  TextSpan(
                    text: answer,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: CockpitSpacing.sm),
          Text(explanation,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
          const SizedBox(height: CockpitSpacing.md),
          Row(
            children: [
              if (relatedConcept != null)
                Expanded(
                  child: Text(
                    'Related: $relatedConcept',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                )
              else
                const Spacer(),
              TextButton.icon(
                onPressed: onReview,
                icon: const Icon(Icons.menu_book_outlined, size: 16),
                label: const Text('Review this section'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AiInsight extends StatelessWidget {
  const _AiInsight({
    required this.correct,
    required this.confidence,
    required this.topicTitle,
  });
  final bool correct;
  final _Confidence? confidence;
  final String topicTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final String message;
    if (!correct) {
      message = "We'll add $topicTitle to your next review session.";
    } else if (confidence == _Confidence.guessing) {
      message =
          "Right — but you weren't sure. We'll reinforce $topicTitle to build "
          'confidence.';
    } else {
      message = 'Solid recall on $topicTitle. Keep it up!';
    }

    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.md),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome, size: 16, color: scheme.primary),
          const SizedBox(width: CockpitSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Insight',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(message,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Completion (Screen 8 handoff)
// ---------------------------------------------------------------------------

class _Completion extends StatelessWidget {
  const _Completion({
    required this.score,
    required this.total,
    required this.confusedTopics,
    required this.onLightning,
    required this.onBack,
  });
  final int score;
  final int total;
  final List<String> confusedTopics;
  final VoidCallback onLightning;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      children: [
        const SizedBox(height: CockpitSpacing.xl),
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: scheme.tertiary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.emoji_events_rounded,
                size: 42, color: scheme.tertiary),
          ),
        ),
        const SizedBox(height: CockpitSpacing.lg),
        Text(
          'Great work.',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: CockpitSpacing.xs),
        Text.rich(
          textAlign: TextAlign.center,
          TextSpan(
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: scheme.onSurfaceVariant),
            children: [
              const TextSpan(text: 'You answered '),
              TextSpan(
                text: '$score / $total',
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: CockpitSpacing.xl),
        Container(
          padding: const EdgeInsets.all(CockpitSpacing.lg),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(CockpitRadii.lg),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, size: 16, color: scheme.primary),
                  const SizedBox(width: CockpitSpacing.sm),
                  Text(
                    'AI Recommendation',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CockpitSpacing.sm),
              Text(
                confusedTopics.isEmpty
                    ? 'The concepts you recalled most slowly would benefit from '
                        'rapid-fire practice.'
                    : 'You were slower on ${confusedTopics.join(', ')}. '
                        'Rapid-fire practice will lock these in.',
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: CockpitSpacing.xl),
        _GradientButton(
          icon: Icons.bolt_rounded,
          label: 'Start Lightning Recall',
          onTap: onLightning,
        ),
        const SizedBox(height: CockpitSpacing.sm),
        Center(
          child: TextButton(
            onPressed: onBack,
            child: const Text('Back to Studio'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom nav
// ---------------------------------------------------------------------------

class _QuizNav extends StatelessWidget {
  const _QuizNav({
    required this.index,
    required this.total,
    required this.canNext,
    required this.onPrev,
    required this.onNext,
  });
  final int index;
  final int total;
  final bool canNext;
  final VoidCallback? onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLast = index + 1 >= total;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        CockpitSpacing.md,
        CockpitSpacing.sm,
        CockpitSpacing.md,
        CockpitSpacing.md,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          _NavButton(
            icon: Icons.arrow_back,
            label: 'Previous',
            onTap: onPrev,
            trailing: false,
          ),
          const Spacer(),
          _NavButton(
            icon: Icons.arrow_forward,
            label: isLast ? 'See Results' : 'Next Question',
            onTap: canNext ? onNext : null,
            trailing: true,
            filled: true,
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.trailing,
    this.filled = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool trailing;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onTap != null;

    if (filled) {
      return _GradientButton(
        icon: icon,
        label: label,
        onTap: onTap,
        expand: false,
        trailingIcon: true,
      );
    }

    final color = enabled
        ? scheme.onSurface
        : scheme.onSurfaceVariant.withValues(alpha: 0.4);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.md,
          vertical: CockpitSpacing.sm,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(CockpitRadii.pill),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: CockpitSpacing.xs),
            Text(label, style: theme.textTheme.labelMedium?.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

class _InfoTile extends StatelessWidget {
  const _InfoTile({
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
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(height: CockpitSpacing.sm),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
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
    this.expand = true,
    this.trailingIcon = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool expand;
  final bool trailingIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final violet = _shiftHue(scheme.primary, -28);
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CockpitRadii.pill),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(CockpitRadii.pill),
              gradient: LinearGradient(colors: [scheme.secondary, violet]),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: expand ? 0 : CockpitSpacing.lg,
              ),
              child: SizedBox(
                height: 50,
                child: Row(
                  mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!trailingIcon) Icon(icon, color: Colors.white, size: 20),
                    if (!trailingIcon) const SizedBox(width: CockpitSpacing.sm),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (trailingIcon) const SizedBox(width: CockpitSpacing.sm),
                    if (trailingIcon) Icon(icon, color: Colors.white, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
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
