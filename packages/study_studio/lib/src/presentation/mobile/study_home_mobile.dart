import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/studio.dart';
import '../../domain/entities/topic.dart';
import '../format.dart';
import 'mobile_motion.dart';
import 'mobile_style.dart';

/// Study Studio's home on a phone: a greeting, the one main action, what to
/// continue, what to do next, and the studios. Hairlines, not cards.
class StudyHomeMobile extends StatelessWidget {
  const StudyHomeMobile({
    super.key,
    required this.studios,
    this.name,
    this.credits,
    this.onRefresh,
    this.now,
  });

  final List<Studio> studios;

  /// The user's name, for the greeting; null greets without it.
  final String? name;
  final int? credits;
  final Future<void> Function()? onRefresh;

  /// For the greeting's time of day (tests).
  final DateTime? now;

  /// How many studios the home lists; the rest are in the library.
  static const listed = 3;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final ordered = byRecent(studios);
    final current = ordered.isEmpty ? null : ordered.first;
    final next = weakestTopic(studios);

    var i = 0;
    Widget appear(Widget child) => SmAppear(index: i++, child: child);

    final children = <Widget>[
      appear(Text(_greeting(now ?? DateTime.now(), name), style: t.greeting)),
      const SizedBox(height: 6),
      appear(_Summary(studios: studios)),
      const SizedBox(height: 18),
      appear(_NewStudioButton(onTap: () => context.go('/study/upload'))),
      if (studios.isEmpty) ...[
        const SizedBox(height: 40),
        appear(const _Empty()),
      ],
      if (current != null) ...[
        _Section(label: 'CONTINUE', index: i++),
        appear(_ContinueRow(studio: current)),
      ],
      if (next != null) ...[
        _Section(label: 'UP NEXT', index: i++),
        appear(_UpNextRow(studio: next.studio, topic: next.topic)),
      ],
      if (studios.isNotEmpty) ...[
        _Section(
          label: 'YOUR STUDIOS',
          index: i++,
          action: studios.length > listed ? 'View all ${studios.length}' : null,
          onAction: () => context.go('/study/library'),
        ),
        for (final (k, studio) in ordered.take(listed).indexed)
          appear(
            StudioRow(
              studio: studio,
              divider: k < listed - 1 && k < ordered.length - 1,
            ),
          ),
      ],
      const SizedBox(height: 32),
    ];

    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      children: children,
    );

    return ColoredBox(
      color: c.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SmTopBar(credits: credits),
            Expanded(
              child: onRefresh == null
                  ? list
                  : RefreshIndicator(
                      color: c.accent,
                      backgroundColor: c.raised,
                      onRefresh: () async {
                        SmHaptics.tap();
                        await onRefresh!();
                      },
                      child: list,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _greeting(DateTime now, String? name) {
    final part = switch (now.hour) {
      >= 5 && < 12 => 'Good morning',
      >= 12 && < 17 => 'Good afternoon',
      >= 17 && < 22 => 'Good evening',
      _ => 'Still studying',
    };
    final first = name?.trim().split(RegExp(r'\s+')).first ?? '';
    if (first.isEmpty || first == 'Guest') return '$part.';
    return '$part,\n$first';
  }
}

/// Studios, most recently studied first (never studied: newest first).
List<Studio> byRecent(List<Studio> studios) {
  DateTime when(Studio s) => s.lastStudied ?? s.updatedAt;
  return [...studios]..sort((a, b) => when(b).compareTo(when(a)));
}

/// The topic with the least mastery, across every studio.
({Studio studio, Topic topic})? weakestTopic(List<Studio> studios) {
  ({Studio studio, Topic topic})? best;
  for (final s in studios) {
    for (final t in s.topics) {
      if (best == null || t.mastery < best.topic.mastery) {
        best = (studio: s, topic: t);
      }
    }
  }
  return best;
}

/// Back to wherever the user came from, and the OctoCredits.
class SmTopBar extends StatelessWidget {
  const SmTopBar({super.key, this.credits, this.title});

  final int? credits;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          const SizedBox(width: 6),
          SmPressable(
            semanticLabel: 'Back',
            haptic: SmHaptics.tap,
            scale: 0.9,
            onTap: () => context.canPop() ? context.pop() : context.go('/'),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 18,
                color: c.muted,
              ),
            ),
          ),
          if (title != null)
            Expanded(child: Text(title!, style: t.title))
          else
            const Spacer(),
          if (credits != null)
            Padding(
              padding: const EdgeInsets.only(right: 18),
              child: Row(
                children: [
                  Icon(Icons.bolt_rounded, size: 15, color: c.gold),
                  const SizedBox(width: 3),
                  Text(_thousands(credits!), style: t.small),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _thousands(int n) {
    final s = n.toString();
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return out.toString();
  }
}

/// "8 studios · 64 topics · 1% mastered".
class _Summary extends StatelessWidget {
  const _Summary({required this.studios});

  final List<Studio> studios;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final topics = studios.fold(0, (n, s) => n + s.topicCount);
    final mastery = studios.isEmpty
        ? 0
        : (studios.fold<double>(0, (n, s) => n + s.overallMastery) /
                  studios.length *
                  100)
              .round();
    String plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';
    return Text.rich(
      TextSpan(
        style: t.small.copyWith(fontSize: 12),
        children: [
          TextSpan(text: '${plural(studios.length, 'studio')} · '),
          TextSpan(text: '${plural(topics, 'topic')} · '),
          TextSpan(
            text: '$mastery% mastered',
            style: TextStyle(color: c.accentSoft),
          ),
        ],
      ),
    );
  }
}

class _NewStudioButton extends StatelessWidget {
  const _NewStudioButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    return SmPressable(
      semanticLabel: 'New study studio',
      haptic: SmHaptics.thud,
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: c.accent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, color: Colors.white, size: 20),
            SizedBox(width: 6),
            Text(
              'New study studio',
              style: TextStyle(
                fontFamily: SmFonts.heading,
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small grey label over a section, and an optional action on its right.
class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.index,
    this.action,
    this.onAction,
  });

  final String label;
  final int index;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return SmAppear(
      index: index,
      child: Padding(
        padding: const EdgeInsets.only(top: 26, bottom: 4),
        child: Row(
          children: [
            Expanded(child: Text(label, style: t.section)),
            if (action != null)
              SmPressable(
                semanticLabel: action,
                onTap: onAction,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    action!,
                    style: t.small.copyWith(
                      color: c.accentSoft,
                      fontWeight: FontWeight.w500,
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

/// The studio to pick up again: its ring, its name, play.
class _ContinueRow extends StatelessWidget {
  const _ContinueRow({required this.studio});

  final Studio studio;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final started = studio.lastStudied != null;
    return SmPressable(
      semanticLabel: 'Continue ${studio.title}',
      onTap: () => context.go('/study/${studio.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SmRing(value: studio.overallMastery, size: 50),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    studio.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.title,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${studio.topicCount} topics · '
                    '${studio.flashcardCount} cards · '
                    '${started ? relativeDay(studio.lastStudied).toLowerCase() : 'not started'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.small,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.play_arrow_rounded,
                color: c.accentSoft,
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The AI's pick: the weakest topic, to review now.
class _UpNextRow extends StatelessWidget {
  const _UpNextRow({required this.studio, required this.topic});

  final Studio studio;
  final Topic topic;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return SmPressable(
      semanticLabel: 'Review ${topic.title}',
      onTap: () => context.go('/study/${studio.id}/teach/${topic.id}'),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border.symmetric(horizontal: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            Icon(Icons.auto_awesome_rounded, size: 18, color: c.accentSoft),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Review ${topic.title}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.body,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Your weakest topic · ${topic.estimatedStudyTimeMinutes} min',
                    style: t.small.copyWith(color: c.hint),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.hint),
          ],
        ),
      ),
    );
  }
}

/// One studio in a list: name, size, mastery. Shared with the library.
class StudioRow extends StatelessWidget {
  const StudioRow({super.key, required this.studio, this.divider = true});

  final Studio studio;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final empty = studio.topicCount == 0;
    return SmPressable(
      semanticLabel: studio.title,
      onTap: () => context.go('/study/${studio.id}'),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: divider
              ? Border(bottom: BorderSide(color: c.line.withValues(alpha: 0.7)))
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    studio.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.body,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    empty
                        ? 'Empty'
                        : '${studio.topicCount} topics · '
                              '${studio.flashcardCount} cards',
                    style: t.small.copyWith(color: c.hint),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              empty ? '—' : '${(studio.overallMastery * 100).round()}%',
              style: t.small.copyWith(
                fontFamily: SmFonts.heading,
                fontWeight: FontWeight.w600,
                color: c.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return Column(
      children: [
        Icon(Icons.auto_stories_outlined, size: 34, color: c.hint),
        const SizedBox(height: 10),
        Text('Start your first studio', style: t.title),
        const SizedBox(height: 4),
        Text(
          'Upload lecture notes or a textbook chapter. AI turns it into '
          'topics, flashcards and quizzes.',
          textAlign: TextAlign.center,
          style: t.small,
        ),
      ],
    );
  }
}
