import 'dart:async';

import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../domain/entities/flashcard.dart';
import '../../domain/entities/studio.dart';
import '../../domain/entities/topic.dart';
import '../mobile/flashcards_mobile.dart';
import '../mobile/mobile_header.dart';
import '../mobile/mobile_style.dart';
import '../widgets/studio_palette.dart';
import '../widgets/studio_scaffold.dart';

/// Screen 9 — Flashcards.
///
/// Calm, reflective spaced-repetition review: a large flip card, a memory hook,
/// a confidence rating (Again/Hard/Good/Easy) that schedules future reviews, and
/// live review stats. Cards come from the studio's Study Objects (optionally
/// filtered to one topic); grades are recorded via [recordFlashcardReview].
class FlashcardsPage extends ConsumerStatefulWidget {
  const FlashcardsPage({super.key, required this.studioId, this.topicId});
  final String studioId;
  final String? topicId;

  @override
  ConsumerState<FlashcardsPage> createState() => _FlashcardsPageState();
}

class _FlashcardsPageState extends ConsumerState<FlashcardsPage> {
  int _index = 0;
  bool _revealed = false;
  bool _done = false;
  int _reviewed = 0;
  int _known = 0;

  List<Flashcard> _cards(Studio studio) {
    final topics = widget.topicId == null
        ? studio.topics
        : studio.topics.where((t) => t.id == widget.topicId);
    return [for (final t in topics) ...t.flashcards];
  }

  Topic? _topicFor(Studio studio, Flashcard card) {
    for (final t in studio.topics) {
      if (t.id == card.topicId) return t;
    }
    return null;
  }

  void _flip() => setState(() => _revealed = !_revealed);

  void _prev() {
    if (_index == 0) return;
    setState(() {
      _index--;
      _revealed = false;
    });
  }

  void _next(int total) {
    setState(() {
      _revealed = false;
      if (_index + 1 >= total) {
        _done = true;
      } else {
        _index++;
      }
    });
  }

  // Again/Hard/Good/Easy → quality 0..1; records the review and advances.
  Future<void> _grade(Flashcard card, double quality, int total) async {
    await ref.read(studioRepositoryProvider).recordFlashcardReview(
          studioId: widget.studioId,
          topicId: card.topicId,
          quality: quality,
        );
    _reviewed++;
    if (quality >= 0.7) _known++;
    _next(total);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(studioProvider(widget.studioId));
    final base = '/study/${widget.studioId}';
    // A phone gets its own deck (mobile/flashcards_mobile.dart).
    if (!isDesktop(context)) {
      final c = SmColors.of(context);
      void close() {
        ref.invalidate(studioProvider(widget.studioId));
        context.go(
          widget.topicId == null ? base : '$base/topics/${widget.topicId}',
        );
      }

      Widget plain(Widget child) => Scaffold(
        backgroundColor: c.background,
        body: SmHeaderPage(
          header: SmHeader(title: 'Flashcards', onBack: close),
          child: SafeArea(child: Center(child: child)),
        ),
      );
      return async.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => plain(
          CircularProgressIndicator(color: c.accent, strokeWidth: 2.5),
        ),
        error: (_, _) => plain(
          Text(
            'Couldn’t load the cards',
            style: SmText.of(context).small.copyWith(fontSize: 13),
          ),
        ),
        data: (studio) => FlashcardsMobile(
          cards: _cards(studio),
          topicTitles: {for (final t in studio.topics) t.id: t.title},
          onClose: close,
          onGrade: (card, grade) => unawaited(
            ref
                .read(studioRepositoryProvider)
                .reviewFlashcard(
                  studioId: widget.studioId,
                  topicId: card.topicId,
                  cardId: card.id,
                  grade: grade,
                )
                .catchError((Object _) {}),
          ),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (studio) {
            final cards = _cards(studio);
            if (cards.isEmpty) {
              return _Empty(title: studio.title, onBack: () => context.go(base));
            }
            if (_done) {
              return _Done(
                title: studio.title,
                reviewed: _reviewed,
                known: _known,
                onBack: () => context.go(base),
                onScenario: () => context.go('$base/scenario'),
              );
            }
            final i = _index.clamp(0, cards.length - 1);
            final card = cards[i];
            final topic = _topicFor(studio, card);
            return _Body(
              studio: studio,
              card: card,
              topic: topic,
              index: i,
              total: cards.length,
              revealed: _revealed,
              known: _known,
              onFlip: _flip,
              onPrev: _index == 0 ? null : _prev,
              onNext: () => _next(cards.length),
              onGrade: (q) => _grade(card, q, cards.length),
              onBack: () {
                ref.invalidate(studioProvider(widget.studioId));
                context.go(base);
              },
              onTeach: (topicId) => context.go('$base/teach/$topicId'),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body — responsive
// ---------------------------------------------------------------------------

class _Body extends StatelessWidget {
  const _Body({
    required this.studio,
    required this.card,
    required this.topic,
    required this.index,
    required this.total,
    required this.revealed,
    required this.known,
    required this.onFlip,
    required this.onPrev,
    required this.onNext,
    required this.onGrade,
    required this.onBack,
    required this.onTeach,
  });

  final Studio studio;
  final Flashcard card;
  final Topic? topic;
  final int index;
  final int total;
  final bool revealed;
  final int known;
  final VoidCallback onFlip;
  final VoidCallback? onPrev;
  final VoidCallback onNext;
  final ValueChanged<double> onGrade;
  final VoidCallback onBack;
  final ValueChanged<String> onTeach;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : (index + 1) / total;
    final related = _relatedTopics(studio, topic);

    final recommendation = _AiRecommendation(studio: studio, total: total);
    final hero = _FlashcardHero(
      card: card,
      revealed: revealed,
      index: index,
      total: total,
      onTap: onFlip,
    );
    final back = revealed
        ? _BackPanel(card: card, topic: topic)
        : null;
    final confidence = revealed
        ? _ConfidenceRating(onGrade: onGrade)
        : null;
    final relatedCard = related.isEmpty
        ? null
        : _RelatedTopics(
            related: related,
            onTeach: onTeach,
            onGoTeachMe: () => onTeach(topic?.id ?? related.first.id),
          );
    final stats = _ReviewStats(
      studio: studio,
      index: index,
      total: total,
      known: known,
    );

    return Column(
      children: [
        _Header(title: studio.title, onBack: onBack),
        _Progress(index: index, total: total, progress: progress),
        Expanded(
          child: isDesktop(context)
              ? _desktop(recommendation, hero, back, confidence, relatedCard, stats)
              : _mobile(recommendation, hero, back, confidence, relatedCard, stats),
        ),
        _Controls(onPrev: onPrev, onFlip: onFlip, onNext: onNext, revealed: revealed),
      ],
    );
  }

  Widget _mobile(Widget rec, Widget hero, Widget? back, Widget? conf,
      Widget? related, Widget stats) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        CockpitSpacing.lg,
        CockpitSpacing.sm,
        CockpitSpacing.lg,
        CockpitSpacing.lg,
      ),
      children: [
        rec,
        const SizedBox(height: CockpitSpacing.lg),
        hero,
        if (back != null) ...[
          const SizedBox(height: CockpitSpacing.lg),
          back,
        ],
        if (conf != null) ...[
          const SizedBox(height: CockpitSpacing.lg),
          conf,
        ],
        if (related != null) ...[
          const SizedBox(height: CockpitSpacing.lg),
          related,
        ],
        const SizedBox(height: CockpitSpacing.lg),
        stats,
      ],
    );
  }

  Widget _desktop(Widget rec, Widget hero, Widget? back, Widget? conf,
      Widget? related, Widget stats) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main — the card, its answer, and the confidence rating.
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  hero,
                  if (back != null) ...[
                    const SizedBox(height: CockpitSpacing.lg),
                    back,
                  ],
                  if (conf != null) ...[
                    const SizedBox(height: CockpitSpacing.lg),
                    conf,
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 24),
          // Side — recommendation, related topics, live stats.
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  rec,
                  if (related != null) ...[
                    const SizedBox(height: CockpitSpacing.lg),
                    related,
                  ],
                  const SizedBox(height: CockpitSpacing.lg),
                  stats,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Topic> _relatedTopics(Studio studio, Topic? topic) {
    if (topic == null) return const [];
    final out = <Topic>[];
    for (final id in topic.relatedTopicIds) {
      final match = studio.topics.where((t) => t.id == id);
      if (match.isNotEmpty) out.add(match.first);
    }
    return out.take(4).toList();
  }
}

// ---------------------------------------------------------------------------
// Header + progress
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onBack});
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CircleButton(icon: Icons.arrow_back_ios_new, onTap: onBack),
          const SizedBox(width: CockpitSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.style_rounded, size: 14, color: StudyPalette.violet),
                    const SizedBox(width: CockpitSpacing.xs),
                    Text('Flashcards',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: StudyPalette.violet,
                          fontWeight: FontWeight.w700,
                        )),
                  ],
                ),
              ],
            ),
          ),
          _CircleButton(icon: Icons.tune_rounded, onTap: () => soon('Filters')),
          const SizedBox(width: CockpitSpacing.xs),
          _CircleButton(icon: Icons.more_horiz, onTap: () => soon('More')),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({
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
        CockpitSpacing.xs,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('Card ${index + 1} of $total',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const Spacer(),
              Text('${(progress * 100).round()}% Complete',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
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
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AI recommendation banner
// ---------------------------------------------------------------------------

class _AiRecommendation extends StatelessWidget {
  const _AiRecommendation({required this.studio, required this.total});
  final Studio studio;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final minutes = ((total * 10) / 60).ceil().clamp(1, 999);
    final focus = studio.weakTopics.take(3).map((t) => t.title).toList();
    final focusText = focus.isEmpty ? 'All topics' : focus.join(', ');

    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CockpitRadii.xl),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: 0.08),
            scheme.secondary.withValues(alpha: 0.05),
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
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [scheme.primary, StudyPalette.violet],
                  ),
                ),
                child: const Icon(Icons.smart_toy_rounded,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: CockpitSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI Recommendation',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                        )),
                    const SizedBox(height: 2),
                    Text(
                      'These cards are selected from your weakest topics and '
                      'recent sessions.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: CockpitSpacing.md),
          _RecLine(
            icon: Icons.schedule_rounded,
            label: 'Est. review time',
            value: '$minutes minutes',
          ),
          const SizedBox(height: CockpitSpacing.sm),
          _RecLine(
            icon: Icons.track_changes_rounded,
            label: 'Focus areas',
            value: focusText,
            valueColor: scheme.primary,
          ),
        ],
      ),
    );
  }
}

class _RecLine extends StatelessWidget {
  const _RecLine({
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: CockpitSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              Text(value,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: valueColor,
                  )),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Flashcard hero (front)
// ---------------------------------------------------------------------------

class _FlashcardHero extends StatelessWidget {
  const _FlashcardHero({
    required this.card,
    required this.revealed,
    required this.index,
    required this.total,
    required this.onTap,
  });
  final Flashcard card;
  final bool revealed;
  final int index;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dots = total.clamp(0, 9);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(CockpitSpacing.xl),
        constraints: const BoxConstraints(minHeight: 260),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(CockpitRadii.xl),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.06),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CockpitSpacing.sm,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(CockpitRadii.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.open_in_full_rounded,
                          size: 12, color: scheme.primary),
                      const SizedBox(width: 4),
                      Text(revealed ? 'Back' : 'Front',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          )),
                    ],
                  ),
                ),
                const Spacer(),
                Icon(Icons.star_border_rounded,
                    size: 22, color: scheme.onSurfaceVariant),
              ],
            ),
            const SizedBox(height: CockpitSpacing.xl),
            Text(
              revealed ? card.back : card.front,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
            const SizedBox(height: CockpitSpacing.xl),
            if (!revealed)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.keyboard_double_arrow_up_rounded,
                      size: 18, color: scheme.primary),
                  const SizedBox(width: CockpitSpacing.xs),
                  Text('Tap to reveal',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      )),
                ],
              ),
            const SizedBox(height: CockpitSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < dots; i++)
                  Container(
                    width: i == (index % (dots == 0 ? 1 : dots)) ? 18 : 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: i == (index % (dots == 0 ? 1 : dots))
                          ? scheme.primary
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(CockpitRadii.pill),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Back panel (answer)
// ---------------------------------------------------------------------------

class _BackPanel extends StatelessWidget {
  const _BackPanel({required this.card, required this.topic});
  final Flashcard card;
  final Topic? topic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hook = (topic?.memoryHooks.isNotEmpty ?? false)
        ? topic!.memoryHooks.first
        : null;
    final (statusLabel, statusColor) = switch (card.status) {
      FlashcardStatus.review => ('Known', StudyPalette.success),
      FlashcardStatus.learning => ('Learning', StudyPalette.warning),
      FlashcardStatus.fresh => ('New', scheme.onSurfaceVariant),
    };

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: CockpitSpacing.sm, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(CockpitRadii.pill),
                ),
                child: Text('Back',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700)),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: CockpitSpacing.sm, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(CockpitRadii.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        size: 13, color: statusColor),
                    const SizedBox(width: 4),
                    Text(statusLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: statusColor, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.md),
          Text(topic?.title ?? 'Answer',
              style: theme.textTheme.titleLarge?.copyWith(
                color: StudyPalette.success,
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: CockpitSpacing.md),
          Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded,
                  size: 16, color: scheme.primary),
              const SizedBox(width: CockpitSpacing.xs),
              Text('Quick explanation',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  )),
            ],
          ),
          const SizedBox(height: CockpitSpacing.xs),
          Text(card.back, style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
          if (hook != null) ...[
            const SizedBox(height: CockpitSpacing.md),
            Row(
              children: [
                Icon(Icons.psychology_rounded, size: 16, color: scheme.primary),
                const SizedBox(width: CockpitSpacing.xs),
                Text('Memory hook',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    )),
              ],
            ),
            const SizedBox(height: CockpitSpacing.xs),
            Text('“$hook”',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                )),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Confidence rating
// ---------------------------------------------------------------------------

class _ConfidenceRating extends StatelessWidget {
  const _ConfidenceRating({required this.onGrade});
  final ValueChanged<double> onGrade;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text('How well did you know this?',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: CockpitSpacing.md),
        Row(
          children: [
            _Grade(emoji: '🔁', label: 'Again', sub: "Didn't know",
                color: StudyPalette.danger, onTap: () => onGrade(0.0)),
            _Grade(emoji: '😣', label: 'Hard', sub: 'Difficult',
                color: StudyPalette.warning, onTap: () => onGrade(0.4)),
            _Grade(emoji: '🙂', label: 'Good', sub: 'Knew most',
                color: StudyPalette.info, onTap: () => onGrade(0.7)),
            _Grade(emoji: '😎', label: 'Easy', sub: 'Very easy',
                color: StudyPalette.success, onTap: () => onGrade(1.0)),
          ],
        ),
      ],
    );
  }
}

class _Grade extends StatelessWidget {
  const _Grade({
    required this.emoji,
    required this.label,
    required this.sub,
    required this.color,
    required this.onTap,
  });
  final String emoji;
  final String label;
  final String sub;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(CockpitRadii.md),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(CockpitRadii.md),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(CockpitRadii.md),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: CockpitSpacing.sm, horizontal: 2),
                child: Column(
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 18)),
                    const SizedBox(height: 2),
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w800,
                        )),
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 9,
                        )),
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

// ---------------------------------------------------------------------------
// Related topics
// ---------------------------------------------------------------------------

class _RelatedTopics extends StatelessWidget {
  const _RelatedTopics({
    required this.related,
    required this.onTeach,
    required this.onGoTeachMe,
  });
  final List<Topic> related;
  final ValueChanged<String> onTeach;
  final VoidCallback onGoTeachMe;

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
              Flexible(
                child: Text('Related topics',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
              const Spacer(),
              InkWell(
                onTap: onGoTeachMe,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Go to Teach Me',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        )),
                    Icon(Icons.chevron_right, size: 16, color: scheme.primary),
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
              for (final t in related)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Material(
                    color: scheme.secondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(CockpitRadii.pill),
                    child: InkWell(
                      onTap: () => onTeach(t.id),
                      borderRadius: BorderRadius.circular(CockpitRadii.pill),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: CockpitSpacing.md,
                          vertical: CockpitSpacing.xs,
                        ),
                        child: Text(t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.secondary,
                              fontWeight: FontWeight.w600,
                            )),
                      ),
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

// ---------------------------------------------------------------------------
// Review stats
// ---------------------------------------------------------------------------

class _ReviewStats extends StatelessWidget {
  const _ReviewStats({
    required this.studio,
    required this.index,
    required this.total,
    required this.known,
  });
  final Studio studio;
  final int index;
  final int total;
  final int known;

  @override
  Widget build(BuildContext context) {
    final mastery = (studio.overallMastery * 100).round();
    return _Card(
      child: Row(
        children: [
          Expanded(child: _MasteryRing(pct: mastery)),
          _divider(context),
          Expanded(
            child: _Stat(
              icon: Icons.style_rounded,
              value: '${index + 1} / $total',
              label: "Today's review",
              detail: 'Cards seen',
            ),
          ),
          _divider(context),
          Expanded(
            child: _Stat(
              icon: Icons.calendar_today_rounded,
              value: 'Tomorrow',
              label: 'Next review',
              detail: 'Spaced repetition',
            ),
          ),
          _divider(context),
          Expanded(
            child: _Stat(
              icon: Icons.check_circle_rounded,
              value: '$known',
              label: 'Known',
              detail: 'This session',
              color: StudyPalette.success,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) => Container(
        width: 1,
        height: 52,
        margin: const EdgeInsets.symmetric(horizontal: CockpitSpacing.xs),
        color: Theme.of(context).colorScheme.outlineVariant,
      );
}

class _MasteryRing extends StatelessWidget {
  const _MasteryRing({required this.pct});
  final int pct;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 52,
          height: 52,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 52,
                height: 52,
                child: CircularProgressIndicator(
                  value: 1,
                  strokeWidth: 5,
                  valueColor:
                      AlwaysStoppedAnimation(scheme.surfaceContainerHighest),
                ),
              ),
              SizedBox(
                width: 52,
                height: 52,
                child: CircularProgressIndicator(
                  value: (pct / 100).clamp(0, 1),
                  strokeWidth: 5,
                  strokeCap: StrokeCap.round,
                  valueColor: AlwaysStoppedAnimation(scheme.primary),
                ),
              ),
              Text('$pct%',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        const SizedBox(height: CockpitSpacing.xs),
        Text('Mastery',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 10,
            )),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.value,
    required this.label,
    required this.detail,
    this.color,
  });
  final IconData icon;
  final String value;
  final String label;
  final String detail;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color ?? scheme.onSurfaceVariant),
        const SizedBox(height: CockpitSpacing.xs),
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w800, color: color)),
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(fontSize: 10)),
        Text(detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 9,
            )),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom controls
// ---------------------------------------------------------------------------

class _Controls extends StatelessWidget {
  const _Controls({
    required this.onPrev,
    required this.onFlip,
    required this.onNext,
    required this.revealed,
  });
  final VoidCallback? onPrev;
  final VoidCallback onFlip;
  final VoidCallback onNext;
  final bool revealed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        CockpitSpacing.lg,
        CockpitSpacing.md,
        CockpitSpacing.lg,
        CockpitSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: ContentColumn(
        maxWidth: 900,
        child: Row(
          children: [
            Expanded(
              child: _OutlineButton(
                icon: Icons.arrow_back_rounded,
                label: 'Previous',
                onTap: onPrev,
              ),
            ),
            const SizedBox(width: CockpitSpacing.sm),
            Expanded(
              child: _OutlineButton(
                icon: Icons.autorenew_rounded,
                label: revealed ? 'Front' : 'Flip',
                onTap: onFlip,
              ),
            ),
            const SizedBox(width: CockpitSpacing.sm),
            Expanded(
              child: _GradientButton(
                icon: Icons.arrow_forward_rounded,
                label: 'Next',
                onTap: onNext,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty / done
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
        _Header(title: title, onBack: onBack),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(CockpitSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.style_outlined,
                      size: 48, color: scheme.onSurfaceVariant),
                  const SizedBox(height: CockpitSpacing.md),
                  Text('No flashcards yet',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: CockpitSpacing.xs),
                  Text('This selection has no cards to review.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({
    required this.title,
    required this.reviewed,
    required this.known,
    required this.onBack,
    required this.onScenario,
  });
  final String title;
  final int reviewed;
  final int known;
  final VoidCallback onBack;
  final VoidCallback onScenario;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      children: [
        _Header(title: title, onBack: onBack),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.all(CockpitSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.task_alt_rounded,
                        size: 56, color: StudyPalette.success),
                    const SizedBox(height: CockpitSpacing.lg),
                    Text('Review complete',
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: CockpitSpacing.sm),
                    Text(
                      "You've memorized the concepts. Ready to apply them?",
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: CockpitSpacing.xl),
                    _GradientButton(
                      icon: Icons.arrow_forward_rounded,
                      label: 'Start Scenario Mode',
                      onTap: onScenario,
                    ),
                    const SizedBox(height: CockpitSpacing.sm),
                    TextButton(
                      onPressed: onBack,
                      child: const Text('Back to Studio'),
                    ),
                  ],
                ),
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
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
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
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
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
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
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
