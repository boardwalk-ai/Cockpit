import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../domain/entities/flashcard.dart';
import '../../domain/entities/studio.dart';

class FlashcardsPage extends ConsumerStatefulWidget {
  const FlashcardsPage({super.key, required this.studioId, this.topicId});
  final String studioId;
  final String? topicId;

  @override
  ConsumerState<FlashcardsPage> createState() => _FlashcardsPageState();
}

class _FlashcardsPageState extends ConsumerState<FlashcardsPage> {
  int _index = 0;
  bool _flipped = false;
  bool _done = false;

  List<Flashcard> _cards(Studio studio) {
    final topics = widget.topicId == null
        ? studio.topics
        : studio.topics.where((t) => t.id == widget.topicId);
    return [for (final t in topics) ...t.flashcards];
  }

  // Again/Hard/Good/Easy → quality 0..1 and an interval label.
  Future<void> _grade(Flashcard card, double quality, int total) async {
    await ref.read(studioRepositoryProvider).recordFlashcardReview(
          studioId: widget.studioId,
          topicId: card.topicId,
          quality: quality,
        );
    setState(() {
      _flipped = false;
      if (_index + 1 >= total) {
        _done = true;
      } else {
        _index++;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(studioProvider(widget.studioId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flashcards'),
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
          final cards = _cards(studio);
          if (cards.isEmpty) {
            return const EmptyState(
              icon: Icons.style_outlined,
              title: 'No flashcards',
              message: 'This selection has no cards yet.',
            );
          }
          if (_done) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.task_alt, size: 56, color: Theme.of(context).colorScheme.tertiary),
                  const SizedBox(height: CockpitSpacing.lg),
                  Text('Deck complete', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: CockpitSpacing.lg),
                  FilledButton(
                    onPressed: () => context.go('/study/${widget.studioId}'),
                    child: const Text('Back to Studio'),
                  ),
                ],
              ),
            );
          }
          final card = cards[_index];
          return _CardView(
            card: card,
            index: _index,
            total: cards.length,
            flipped: _flipped,
            onFlip: () => setState(() => _flipped = true),
            onGrade: (q) => _grade(card, q, cards.length),
          );
        },
      ),
    );
  }
}

class _CardView extends StatelessWidget {
  const _CardView({
    required this.card,
    required this.index,
    required this.total,
    required this.flipped,
    required this.onFlip,
    required this.onGrade,
  });

  final Flashcard card;
  final int index;
  final int total;
  final bool flipped;
  final VoidCallback onFlip;
  final ValueChanged<double> onGrade;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      child: Column(
        children: [
          Text('Card ${index + 1} of $total', style: theme.textTheme.labelMedium),
          const SizedBox(height: CockpitSpacing.lg),
          Expanded(
            child: GestureDetector(
              onTap: flipped ? null : onFlip,
              child: SizedBox(
                width: double.infinity,
                child: CockpitCard(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            flipped ? 'ANSWER' : 'QUESTION',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: CockpitSpacing.lg),
                          Text(
                            flipped ? card.back : card.front,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge,
                          ),
                          if (!flipped) ...[
                            const SizedBox(height: CockpitSpacing.xl),
                            Text('Tap to reveal',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                )),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: CockpitSpacing.lg),
          if (flipped)
            Row(
              children: [
                _Grade(label: 'Again', sub: '<1d', color: theme.colorScheme.error, onTap: () => onGrade(0.0)),
                _Grade(label: 'Hard', sub: '1d', color: theme.colorScheme.tertiary, onTap: () => onGrade(0.4)),
                _Grade(label: 'Good', sub: '3d', color: theme.colorScheme.secondary, onTap: () => onGrade(0.7)),
                _Grade(label: 'Easy', sub: '7d', color: theme.colorScheme.primary, onTap: () => onGrade(1.0)),
              ],
            )
          else
            FilledButton(onPressed: onFlip, child: const Text('Show Answer')),
        ],
      ),
    );
  }
}

class _Grade extends StatelessWidget {
  const _Grade({required this.label, required this.sub, required this.color, required this.onTap});
  final String label;
  final String sub;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.xs),
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color),
            padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.md),
          ),
          child: Column(
            children: [
              Text(label),
              Text(sub, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}
