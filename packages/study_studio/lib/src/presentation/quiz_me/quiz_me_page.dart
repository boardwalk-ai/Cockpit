import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../domain/entities/quiz_question.dart';
import '../../domain/entities/studio.dart';

class QuizMePage extends ConsumerStatefulWidget {
  const QuizMePage({super.key, required this.studioId, this.topicId});
  final String studioId;
  final String? topicId;

  @override
  ConsumerState<QuizMePage> createState() => _QuizMePageState();
}

class _QuizMePageState extends ConsumerState<QuizMePage> {
  int _index = 0;
  int _score = 0;
  bool _submitted = false;
  String? _selected;
  final _text = TextEditingController();
  bool _done = false;

  List<QuizQuestion> _questions(Studio studio) {
    final topics = widget.topicId == null
        ? studio.topics
        : studio.topics.where((t) => t.id == widget.topicId);
    return [for (final t in topics) ...t.quizQuestions];
  }

  Future<void> _submit(QuizQuestion q) async {
    final response = _selected ?? _text.text;
    final correct = q.isCorrect(response);
    await ref.read(studioRepositoryProvider).recordQuizResult(
          studioId: widget.studioId,
          topicId: q.topicId,
          correct: correct,
        );
    setState(() {
      _submitted = true;
      if (correct) _score++;
    });
  }

  void _next(int total) {
    setState(() {
      if (_index + 1 >= total) {
        _done = true;
      } else {
        _index++;
        _submitted = false;
        _selected = null;
        _text.clear();
      }
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(studioProvider(widget.studioId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quiz Me'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            ref.invalidate(studioProvider(widget.studioId));
            context.go('/study/${widget.studioId}');
          },
        ),
      ),
      body: async.when(
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
          if (_done) {
            return _Summary(
              score: _score,
              total: questions.length,
              studioId: widget.studioId,
            );
          }
          final q = questions[_index];
          return _QuestionView(
            q: q,
            index: _index,
            total: questions.length,
            score: _score,
            submitted: _submitted,
            selected: _selected,
            textController: _text,
            onSelect: (v) => setState(() => _selected = v),
            onSubmit: () => _submit(q),
            onNext: () => _next(questions.length),
          );
        },
      ),
    );
  }
}

class _QuestionView extends StatelessWidget {
  const _QuestionView({
    required this.q,
    required this.index,
    required this.total,
    required this.score,
    required this.submitted,
    required this.selected,
    required this.textController,
    required this.onSelect,
    required this.onSubmit,
    required this.onNext,
  });

  final QuizQuestion q;
  final int index;
  final int total;
  final int score;
  final bool submitted;
  final String? selected;
  final TextEditingController textController;
  final ValueChanged<String> onSelect;
  final VoidCallback onSubmit;
  final VoidCallback onNext;

  bool get _isChoice =>
      q.type == QuizType.multipleChoice || q.type == QuizType.trueFalse;

  bool get _hasAnswer =>
      _isChoice ? selected != null : textController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final correct = submitted && q.isCorrect(selected ?? textController.text);

    return ListView(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Question ${index + 1} of $total', style: theme.textTheme.labelMedium),
            Text('Score: $score', style: theme.textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: CockpitSpacing.md),
        CockpitCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(q.question, style: theme.textTheme.titleMedium),
              const SizedBox(height: CockpitSpacing.lg),
              if (_isChoice)
                RadioGroup<String>(
                  groupValue: selected,
                  onChanged: (v) {
                    if (!submitted && v != null) onSelect(v);
                  },
                  child: Column(
                    children: [
                      for (final c in q.choices)
                        RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: Text(c),
                          value: c,
                        ),
                    ],
                  ),
                )
              else
                TextField(
                  controller: textController,
                  enabled: !submitted,
                  decoration: const InputDecoration(hintText: 'Type your answer'),
                ),
            ],
          ),
        ),
        const SizedBox(height: CockpitSpacing.lg),
        if (submitted) ...[
          CockpitCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      correct ? Icons.check_circle : Icons.cancel,
                      color: correct ? theme.colorScheme.tertiary : theme.colorScheme.error,
                    ),
                    const SizedBox(width: CockpitSpacing.sm),
                    Text(
                      correct ? 'Correct' : 'Not quite',
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ),
                const SizedBox(height: CockpitSpacing.sm),
                if (!correct) Text('Answer: ${q.answer}', style: theme.textTheme.bodyMedium),
                const SizedBox(height: CockpitSpacing.xs),
                Text(q.explanation, style: theme.textTheme.bodyMedium),
                if (q.relatedConcept != null) ...[
                  const SizedBox(height: CockpitSpacing.sm),
                  TagChip(label: 'Related: ${q.relatedConcept}'),
                ],
              ],
            ),
          ),
          const SizedBox(height: CockpitSpacing.lg),
          FilledButton(
            onPressed: onNext,
            child: Text(index + 1 >= total ? 'Finish' : 'Next question'),
          ),
        ] else
          FilledButton(
            onPressed: _hasAnswer ? onSubmit : null,
            child: const Text('Submit Answer'),
          ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.score, required this.total, required this.studioId});
  final int score;
  final int total;
  final String studioId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = total == 0 ? 0 : (score / total * 100).round();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(CockpitSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.emoji_events, size: 56, color: theme.colorScheme.tertiary),
              const SizedBox(height: CockpitSpacing.lg),
              Text('Quiz complete', style: theme.textTheme.headlineSmall),
              const SizedBox(height: CockpitSpacing.sm),
              Text('You scored $score / $total ($pct%)',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: CockpitSpacing.xl),
              FilledButton(
                onPressed: () => context.go('/study/$studioId'),
                child: const Text('Back to Studio'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
