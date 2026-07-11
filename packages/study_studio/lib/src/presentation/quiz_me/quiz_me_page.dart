import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../domain/entities/quiz_question.dart';
import '../../domain/entities/studio.dart';

/// Screen 7 — Quiz Me.
///
/// An AI-guided assessment, not a list of questions. A persistent "Quiz Ready"
/// banner frames the session; each question is answered with a confidence
/// rating; feedback transforms in place to reinforce learning; and completion
/// hands off to Lightning Recall. Same visual language + Outfit.
class QuizMePage extends ConsumerStatefulWidget {
  const QuizMePage({super.key, required this.studioId, this.topicId});
  final String studioId;
  final String? topicId;

  @override
  ConsumerState<QuizMePage> createState() => _QuizMePageState();
}

enum _Confidence { guessing, somewhat, very }

class _QuizMePageState extends ConsumerState<QuizMePage> {
  bool _done = false;
  int _index = 0;

  // Per-question state so navigating back restores prior answers.
  final _selected = <int, String>{};
  final _confidence = <int, _Confidence>{};
  final _submitted = <int>{};
  final _correct = <int, bool>{};
  final _assistantOpen = <int>{};
  final _text = TextEditingController();

  List<QuizQuestion> _questions(Studio studio) {
    final topics = widget.topicId == null
        ? studio.topics
        : studio.topics.where((t) => t.id == widget.topicId);
    return [for (final t in topics) ...t.quizQuestions];
  }

  Future<void> _submit(QuizQuestion q) async {
    if (_submitted.contains(_index)) return;
    final correct = q.isCorrect(_selected[_index] ?? '');
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
        : _topicTitleFor(studio, widget.topicId!);

    void close() {
      ref.invalidate(studioProvider(widget.studioId));
      context.go('/study/${widget.studioId}');
    }

    if (_done) {
      return Column(
        children: [
          _Header(
            studioTitle: studio.title,
            topicTitle: topicTitle,
            onBack: close,
          ),
          Expanded(
            child: _Completion(
              score: _score,
              total: total,
              confusedTopics: _confusedTopics(studio, qs),
              onLightning: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Lightning Recall — Phase 2')),
              ),
              onWeakAreas: () => context.go('/study/${widget.studioId}/progress'),
              onBack: close,
            ),
          ),
        ],
      );
    }

    final submitted = _submitted.contains(_index);
    final q = qs[_index];
    final progress = (_index + 1) / total;

    return Column(
      children: [
        _Header(
          studioTitle: studio.title,
          topicTitle: topicTitle,
          onBack: close,
        ),
        _ProgressRow(index: _index, total: total, progress: progress),
        Expanded(
          child: ListView(
            key: ValueKey(_index),
            padding: const EdgeInsets.fromLTRB(
              CockpitSpacing.lg,
              CockpitSpacing.md,
              CockpitSpacing.lg,
              CockpitSpacing.xl,
            ),
            children: [
              if (_index == 0) ...[
                const _QuizReadyBanner(),
                const SizedBox(height: CockpitSpacing.lg),
              ],
              _QuestionCard(
                q: q,
                index: _index,
                selected: _selected[_index],
                submitted: submitted,
                onSelect: (v) => setState(() => _selected[_index] = v),
                onText: (v) => _selected[_index] = v,
                textController: _text,
              ),
              if (!submitted) ...[
                const SizedBox(height: CockpitSpacing.lg),
                _ConfidenceRow(
                  value: _confidence[_index],
                  onSelect: (c) => setState(() => _confidence[_index] = c),
                ),
                const SizedBox(height: CockpitSpacing.lg),
                _GradientButton(
                  icon: Icons.arrow_forward,
                  label: 'Check Answer',
                  trailingIcon: true,
                  onTap: _hasAnswer(q) ? () => _submit(q) : null,
                ),
              ],
              const SizedBox(height: CockpitSpacing.md),
              _AiStudyAssistant(
                open: _assistantOpen.contains(_index),
                onToggle: () => setState(() {
                  if (!_assistantOpen.remove(_index)) _assistantOpen.add(_index);
                }),
                onOpenTeach: () =>
                    context.go('/study/${widget.studioId}/teach/${q.topicId}'),
              ),
              if (submitted) ...[
                const SizedBox(height: CockpitSpacing.md),
                _Feedback(
                  q: q,
                  correct: _correct[_index] ?? false,
                  topicTitle: _topicTitleFor(studio, q.topicId),
                  onReview: () =>
                      context.go('/study/${widget.studioId}/teach/${q.topicId}'),
                ),
                const SizedBox(height: CockpitSpacing.md),
                _AiInsight(
                  correct: _correct[_index] ?? false,
                  selected: _selected[_index],
                  answer: q.answer,
                  topicTitle: _topicTitleFor(studio, q.topicId),
                  onWeakAreas: () =>
                      context.go('/study/${widget.studioId}/progress'),
                ),
              ],
            ],
          ),
        ),
        _QuizNav(
          index: _index,
          total: total,
          canNext: submitted,
          onPrev: _index > 0 ? () => _goto(_index - 1, total) : null,
          onNext: () {
            if (_index + 1 >= total) {
              setState(() => _done = true);
            } else {
              _goto(_index + 1, total);
            }
          },
        ),
      ],
    );
  }

  bool _hasAnswer(QuizQuestion q) {
    final isChoice =
        q.type == QuizType.multipleChoice || q.type == QuizType.trueFalse;
    return isChoice
        ? _selected[_index] != null
        : (_selected[_index] ?? '').trim().isNotEmpty;
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
// Header + progress
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.studioTitle,
    required this.topicTitle,
    required this.onBack,
  });
  final String studioTitle;
  final String topicTitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    void soon(String l) => ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$l — coming soon')));

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CockpitSpacing.md,
        CockpitSpacing.sm,
        CockpitSpacing.md,
        CockpitSpacing.sm,
      ),
      child: Row(
        children: [
          _CircleButton(icon: Icons.arrow_back_ios_new, onTap: onBack),
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
                    Flexible(
                      child: Text(
                        '  •  $topicTitle',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _CircleButton(icon: Icons.bookmark_border, onTap: () => soon('Bookmark')),
          const SizedBox(width: CockpitSpacing.xs),
          _CircleButton(icon: Icons.more_horiz, onTap: () => soon('More')),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CockpitSpacing.lg,
        0,
        CockpitSpacing.lg,
        CockpitSpacing.sm,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Question ${index + 1} of $total',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              Text(
                '${(progress * 100).round()}% Complete',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(CockpitRadii.pill),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quiz Ready banner
// ---------------------------------------------------------------------------

class _QuizReadyBanner extends StatelessWidget {
  const _QuizReadyBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.error.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.track_changes, color: scheme.error, size: 26),
              ),
              const SizedBox(width: CockpitSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quiz Ready',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "You're about to answer questions based on your "
                      'uploaded materials.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: CockpitSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MiniMeta(
                    icon: Icons.schedule,
                    label: 'Difficulty',
                    value: 'Adaptive',
                    valueColor: scheme.primary,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.md),
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 14, color: scheme.primary),
              const SizedBox(width: CockpitSpacing.xs),
              Expanded(
                child: Text(
                  'Questions become harder or easier depending on your '
                  'performance.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniMeta extends StatelessWidget {
  const _MiniMeta({
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
    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: CockpitSpacing.xs),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant, fontSize: 10),
            ),
            Text(
              value,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: valueColor,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Question card
// ---------------------------------------------------------------------------

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.q,
    required this.index,
    required this.selected,
    required this.submitted,
    required this.onSelect,
    required this.onText,
    required this.textController,
  });
  final QuizQuestion q;
  final int index;
  final String? selected;
  final bool submitted;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onText;
  final TextEditingController textController;

  bool get _isChoice =>
      q.type == QuizType.multipleChoice || q.type == QuizType.trueFalse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (typeLabel, typeIcon) = switch (q.type) {
      QuizType.multipleChoice => ('Multiple Choice', Icons.list_alt),
      QuizType.trueFalse => ('True / False', Icons.rule),
      QuizType.shortAnswer => ('Short Answer', Icons.short_text),
      QuizType.fillBlank => ('Fill in the Blank', Icons.edit_note),
    };

    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: CockpitSpacing.sm,
              vertical: CockpitSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(CockpitRadii.sm),
            ),
            child: Text(
              'Question ${index + 1}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: CockpitSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  q.question,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700, height: 1.25),
                ),
              ),
              const SizedBox(width: CockpitSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(typeIcon, size: 14, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 3),
                    Text(
                      typeLabel,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.lg),
          if (_isChoice)
            for (var i = 0; i < q.choices.length; i++)
              _AnswerOption(
                letter: String.fromCharCode(65 + i),
                label: q.choices[i],
                selected: selected == q.choices[i],
                submitted: submitted,
                isAnswer: q.choices[i] == q.answer,
                onTap: submitted ? null : () => onSelect(q.choices[i]),
              )
          else
            TextField(
              controller: textController,
              enabled: !submitted,
              onChanged: onText,
              decoration: const InputDecoration(hintText: 'Type your answer'),
            ),
        ],
      ),
    );
  }
}

class _AnswerOption extends StatelessWidget {
  const _AnswerOption({
    required this.letter,
    required this.label,
    required this.selected,
    required this.submitted,
    required this.isAnswer,
    required this.onTap,
  });
  final String letter;
  final String label;
  final bool selected;
  final bool submitted;
  final bool isAnswer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Color border = scheme.outlineVariant;
    Color bg = scheme.surface;
    Color accent = scheme.onSurfaceVariant;
    var emphasize = false;

    if (submitted) {
      if (isAnswer) {
        border = scheme.tertiary;
        bg = scheme.tertiary.withValues(alpha: 0.10);
        accent = scheme.tertiary;
        emphasize = true;
      } else if (selected) {
        border = scheme.error;
        bg = scheme.error.withValues(alpha: 0.08);
        accent = scheme.error;
        emphasize = true;
      }
    } else if (selected) {
      border = scheme.primary;
      bg = scheme.primary.withValues(alpha: 0.08);
      accent = scheme.primary;
      emphasize = true;
    }

    // Leading indicator: radio normally, status icon after submit.
    Widget leading;
    if (submitted && isAnswer) {
      leading = Icon(Icons.check_circle, size: 22, color: scheme.tertiary);
    } else if (submitted && selected) {
      leading = Icon(Icons.cancel, size: 22, color: scheme.error);
    } else {
      leading = Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: 2,
          ),
        ),
        child: selected
            ? Center(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              )
            : null,
      );
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
              border: Border.all(color: border, width: emphasize ? 1.8 : 1),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: CockpitSpacing.md,
              vertical: CockpitSpacing.md,
            ),
            child: Row(
              children: [
                leading,
                const SizedBox(width: CockpitSpacing.md),
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    letter,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: CockpitSpacing.md),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
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

// ---------------------------------------------------------------------------
// Confidence
// ---------------------------------------------------------------------------

class _ConfidenceRow extends StatelessWidget {
  const _ConfidenceRow({required this.value, required this.onSelect});
  final _Confidence? value;
  final ValueChanged<_Confidence> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(CockpitRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.public, size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: CockpitSpacing.xs),
              Text(
                'How confident are you?',
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Row(
            children: [
              for (final c in _Confidence.values) ...[
                Expanded(
                  child: _ConfidenceChip(
                    level: c,
                    selected: value == c,
                    onTap: () => onSelect(c),
                  ),
                ),
                if (c != _Confidence.values.last)
                  const SizedBox(width: CockpitSpacing.sm),
              ],
            ],
          ),
        ],
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
    final (label, emoji) = switch (level) {
      _Confidence.guessing => ('Guessing', '🙂'),
      _Confidence.somewhat => ('Somewhat Sure', '😐'),
      _Confidence.very => ('Very Confident', '😎'),
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CockpitRadii.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: CockpitSpacing.sm,
          horizontal: CockpitSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withValues(alpha: 0.10) : scheme.surface,
          borderRadius: BorderRadius.circular(CockpitRadii.md),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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

// ---------------------------------------------------------------------------
// AI Study Assistant (collapsible)
// ---------------------------------------------------------------------------

class _AiStudyAssistant extends StatelessWidget {
  const _AiStudyAssistant({
    required this.open,
    required this.onToggle,
    required this.onOpenTeach,
  });
  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onOpenTeach;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(CockpitRadii.md),
            child: Padding(
              padding: const EdgeInsets.all(CockpitSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.smart_toy_rounded,
                        size: 20, color: scheme.primary),
                  ),
                  const SizedBox(width: CockpitSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI Study Assistant',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          "I'll explain the answer and help you understand why.",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Icon(open ? Icons.expand_less : Icons.expand_more,
                      color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CockpitSpacing.md,
                0,
                CockpitSpacing.md,
                CockpitSpacing.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Want a deeper walkthrough of this concept?',
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                    ),
                  ),
                  const SizedBox(width: CockpitSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: onOpenTeach,
                    icon: const Icon(Icons.school_outlined, size: 16),
                    label: const Text('Teach Me'),
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
// Feedback
// ---------------------------------------------------------------------------

class _Feedback extends StatelessWidget {
  const _Feedback({
    required this.q,
    required this.correct,
    required this.topicTitle,
    required this.onReview,
  });
  final QuizQuestion q;
  final bool correct;
  final String topicTitle;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = correct ? scheme.tertiary : scheme.error;
    final others = q.choices.where((c) => c != q.answer).toList();

    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
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
                correct ? 'Correct! 🎉' : 'Not quite',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800, color: accent),
              ),
              const Spacer(),
              Row(
                children: [
                  Icon(Icons.public, size: 14, color: scheme.tertiary),
                  const SizedBox(width: 3),
                  Text(
                    correct ? 'Why this is correct' : 'Correct answer',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.tertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.sm),
          if (!correct) ...[
            Text.rich(
              TextSpan(
                style: theme.textTheme.bodyMedium,
                children: [
                  const TextSpan(text: 'The answer is '),
                  TextSpan(
                    text: q.answer,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
            const SizedBox(height: CockpitSpacing.xs),
          ],
          Text(q.explanation,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
          if (others.isNotEmpty) ...[
            const SizedBox(height: CockpitSpacing.md),
            Text(
              'Other options',
              style: theme.textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: CockpitSpacing.xs),
            Wrap(
              spacing: CockpitSpacing.sm,
              runSpacing: CockpitSpacing.xs,
              children: [
                for (final o in others)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CockpitSpacing.sm,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(CockpitRadii.sm),
                    ),
                    child: Text(
                      o,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: CockpitSpacing.md),
          // Review-in-lesson breadcrumb.
          InkWell(
            onTap: onReview,
            borderRadius: BorderRadius.circular(CockpitRadii.md),
            child: Container(
              padding: const EdgeInsets.all(CockpitSpacing.md),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(CockpitRadii.md),
                border: Border.all(color: scheme.primary.withValues(alpha: 0.14)),
              ),
              child: Row(
                children: [
                  Icon(Icons.menu_book_outlined, size: 18, color: scheme.primary),
                  const SizedBox(width: CockpitSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Review in lesson',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          q.relatedConcept == null
                              ? topicTitle
                              : '$topicTitle  ›  ${q.relatedConcept}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiInsight extends StatelessWidget {
  const _AiInsight({
    required this.correct,
    required this.selected,
    required this.answer,
    required this.topicTitle,
    required this.onWeakAreas,
  });
  final bool correct;
  final String? selected;
  final String answer;
  final String topicTitle;
  final VoidCallback onWeakAreas;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final String message;
    if (!correct && selected != null && selected!.isNotEmpty) {
      message = "You picked $selected — the answer is $answer. We'll add extra "
          'practice on $topicTitle to your next review session.';
    } else if (!correct) {
      message = "We'll add extra practice on $topicTitle to your next review "
          'session.';
    } else {
      message = 'Strong recall on $topicTitle. Keep the streak going!';
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
          const SizedBox(width: CockpitSpacing.sm),
          OutlinedButton.icon(
            onPressed: onWeakAreas,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: CockpitSpacing.sm,
                vertical: CockpitSpacing.xs,
              ),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.insights, size: 15),
            label: const Text('Weak Areas'),
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
    required this.onWeakAreas,
    required this.onBack,
  });
  final int score;
  final int total;
  final List<String> confusedTopics;
  final VoidCallback onLightning;
  final VoidCallback onWeakAreas;
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
                  const Spacer(),
                  TextButton.icon(
                    onPressed: onWeakAreas,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: CockpitSpacing.sm),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.insights, size: 15),
                    label: const Text('Weak Areas'),
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
    final scheme = Theme.of(context).colorScheme;
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
          _OutlineNavButton(
            icon: Icons.arrow_back,
            label: 'Previous Question',
            onTap: onPrev,
          ),
          const Spacer(),
          _GradientButton(
            icon: Icons.arrow_forward,
            label: isLast ? 'See Results' : 'Next Question',
            onTap: canNext ? onNext : null,
            expand: false,
            trailingIcon: true,
          ),
        ],
      ),
    );
  }
}

class _OutlineNavButton extends StatelessWidget {
  const _OutlineNavButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onTap != null;
    final color = enabled
        ? scheme.onSurface
        : scheme.onSurfaceVariant.withValues(alpha: 0.4);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.md,
          vertical: CockpitSpacing.md,
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
