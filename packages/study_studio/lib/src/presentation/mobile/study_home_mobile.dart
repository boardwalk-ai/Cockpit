import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/studio.dart';
import '../../domain/entities/topic.dart';
import '../format.dart';
import 'mobile_motion.dart';
import 'mobile_style.dart';

/// Study Studio's home on a phone, centred: the studio to pick up again as
/// one large mastery ring with Continue and New, the AI's next topic, and
/// the other studios. Hairlines and space, not cards.
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

  /// The other studios listed under the ring; the rest are in the library.
  static const listed = 2;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final ordered = byRecent(studios);
    final next = weakestTopic(studios);
    void newStudio() => context.go('/study/upload');

    var i = 0;
    Widget appear(Widget child) => SmAppear(index: i++, child: child);

    final hello = appear(
      Text(
        greeting(now ?? DateTime.now(), name),
        textAlign: TextAlign.center,
        style: t.small.copyWith(fontSize: 13),
      ),
    );

    // Three groups spread over the screen's height (a short screen
    // scrolls): the studio to continue, what is next, the other studios.
    final List<Widget> groups;
    if (ordered.isEmpty) {
      groups = [
        hello,
        appear(const _Empty()),
        appear(_NewStudioButton(filled: true, onTap: newStudio)),
      ];
    } else {
      final current = ordered.first;
      final others = ordered.skip(1).take(listed).toList();
      groups = [
        Column(
          children: [
            hello,
            const SizedBox(height: 4),
            appear(
              Text(
                'Pick up where you left off',
                textAlign: TextAlign.center,
                style: t.greeting.copyWith(fontSize: 23),
              ),
            ),
            const SizedBox(height: 24),
            appear(
              SmPressable(
                semanticLabel: 'Open ${current.title}',
                scale: 0.96,
                onTap: () => context.go('/study/${current.id}'),
                child: SmRing(
                  value: current.overallMastery,
                  size: 170,
                  stroke: 10,
                  labelSize: 34,
                  caption: 'mastered',
                ),
              ),
            ),
            const SizedBox(height: 16),
            appear(
              Column(
                children: [
                  Text(
                    current.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.title.copyWith(fontSize: 17),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _detail(current),
                    textAlign: TextAlign.center,
                    style: t.small.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            appear(
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Pill(
                    label: 'Continue',
                    icon: Icons.play_arrow_rounded,
                    filled: true,
                    onTap: () => context.go('/study/${current.id}'),
                  ),
                  const SizedBox(width: 10),
                  _Pill(
                    label: 'New',
                    icon: Icons.add_rounded,
                    filled: false,
                    haptic: SmHaptics.thud,
                    onTap: newStudio,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            appear(_Totals(studios: studios)),
          ],
        ),
        if (next != null)
          Column(
            children: [
              appear(const _Label('UP NEXT')),
              const SizedBox(height: 6),
              appear(_UpNext(studio: next.studio, topic: next.topic)),
            ],
          ),
        Column(
          children: [
            if (others.isNotEmpty) ...[
              appear(const _Label('YOUR STUDIOS')),
              const SizedBox(height: 8),
              for (final (k, studio) in others.indexed)
                appear(
                  StudioRow(studio: studio, divider: true, topDivider: k == 0),
                ),
            ],
            appear(
              SmPressable(
                semanticLabel: 'View all studios',
                onTap: () => context.go('/study/library'),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    'View all ${studios.length}',
                    style: t.small.copyWith(
                      fontSize: 12,
                      color: c.accentSoft,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ];
    }

    final body = LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight - 16),
          child: Column(
            mainAxisAlignment: ordered.isEmpty
                ? MainAxisAlignment.spaceEvenly
                : MainAxisAlignment.spaceBetween,
            children: [
              for (final (k, group) in groups.indexed) ...[
                if (k > 0) const SizedBox(height: 26),
                group,
              ],
            ],
          ),
        ),
      ),
    );

    return ColoredBox(
      color: c.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SmTopBar(credits: credits, home: true),
            Expanded(
              child: onRefresh == null
                  ? body
                  : RefreshIndicator(
                      color: c.accent,
                      backgroundColor: c.raised,
                      onRefresh: () async {
                        SmHaptics.tap();
                        await onRefresh!();
                      },
                      child: body,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _detail(Studio s) {
    if (s.topicCount == 0) return 'Empty';
    final when = s.lastStudied == null
        ? 'not started'
        : relativeDay(s.lastStudied).toLowerCase();
    return '${s.topicCount} topics · ${s.flashcardCount} cards · $when';
  }

  /// "Good afternoon, Dev" (no name: "Good afternoon").
  static String greeting(DateTime now, String? name) {
    final part = switch (now.hour) {
      >= 5 && < 12 => 'Good morning',
      >= 12 && < 17 => 'Good afternoon',
      >= 17 && < 22 => 'Good evening',
      _ => 'Still studying',
    };
    final first = name?.trim().split(RegExp(r'\s+')).first ?? '';
    if (first.isEmpty || first == 'Guest') return part;
    return '$part, $first';
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

/// Back (or, on the home, Home) and the OctoCredits.
class SmTopBar extends StatelessWidget {
  const SmTopBar({super.key, this.credits, this.title, this.home = false});

  final int? credits;
  final String? title;

  /// The leading button goes to the app's home instead of back.
  final bool home;

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
            semanticLabel: home ? 'Home' : 'Back',
            haptic: SmHaptics.tap,
            scale: 0.9,
            onTap: () =>
                home || !context.canPop() ? context.go('/') : context.pop(),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                home ? Icons.home_outlined : Icons.arrow_back_ios_new_rounded,
                size: home ? 22 : 18,
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

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: SmText.of(context).section,
  );
}

/// The AI's pick: the weakest topic, to review now.
class _UpNext extends StatelessWidget {
  const _UpNext({required this.studio, required this.topic});

  final Studio studio;
  final Topic topic;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return SmPressable(
      semanticLabel: 'Review ${topic.title}',
      onTap: () => context.go('/study/${studio.id}/teach/${topic.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.auto_awesome_rounded, size: 14, color: c.accentSoft),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'Your weakest topic · ${topic.estimatedStudyTimeMinutes} min',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.small.copyWith(fontSize: 12, color: c.accentSoft),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              'Review ${topic.title}',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.body.copyWith(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

/// "+ New study studio": tinted red under the carousel, solid red when
/// there are no studios yet. Either way it is easy to find.
class _NewStudioButton extends StatelessWidget {
  const _NewStudioButton({required this.filled, required this.onTap});

  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final fg = filled ? Colors.white : c.accentSoft;
    return SmPressable(
      semanticLabel: 'New study studio',
      haptic: SmHaptics.thud,
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: filled ? c.accent : c.accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: filled ? c.accent : c.accent.withValues(alpha: 0.55),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, color: fg, size: 20),
            const SizedBox(width: 6),
            Text(
              'New study studio',
              style: TextStyle(
                fontFamily: SmFonts.heading,
                color: fg,
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

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
    this.haptic = SmHaptics.tap,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;
  final void Function() haptic;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final fg = filled ? Colors.white : c.text;
    return SmPressable(
      semanticLabel: label,
      haptic: haptic,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: filled ? 28 : 20,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: filled ? c.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: filled ? null : Border.all(color: c.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: fg, size: 19),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: SmFonts.heading,
                color: fg,
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

/// "8 studios · 64 topics · 1% mastered".
class _Totals extends StatelessWidget {
  const _Totals({required this.studios});

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
      textAlign: TextAlign.center,
      TextSpan(
        style: t.small.copyWith(color: c.hint),
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

/// One studio in a list: name, size, mastery. Used by the library.
class StudioRow extends StatelessWidget {
  const StudioRow({
    super.key,
    required this.studio,
    this.divider = true,
    this.topDivider = false,
  });

  final Studio studio;
  final bool divider;
  final bool topDivider;

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
        Icon(Icons.auto_stories_outlined, size: 40, color: c.hint),
        const SizedBox(height: 12),
        Text('Start your first studio', style: t.title.copyWith(fontSize: 18)),
        const SizedBox(height: 6),
        Text(
          'Upload lecture notes or a textbook chapter. AI turns it into '
          'topics, flashcards and quizzes.',
          textAlign: TextAlign.center,
          style: t.small.copyWith(fontSize: 12),
        ),
      ],
    );
  }
}
