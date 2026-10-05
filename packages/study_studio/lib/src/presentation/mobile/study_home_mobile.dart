import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/studio.dart';
import '../../domain/entities/topic.dart';
import 'mobile_motion.dart';
import 'mobile_style.dart';

/// Study Studio's home on a phone, centred: today's focus (the AI's pick, to
/// start now), the studios as a ring carousel to swipe through, and a clear
/// way to make a new one. Hairlines and space, not cards.
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

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final ordered = byRecent(studios);
    final focus = weakestTopic(studios);
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

    // Three groups spread over the screen's height: what to do today at
    // the top, the studios in the middle, making a new one at the bottom.
    // A short screen scrolls instead.
    final List<Widget> groups;
    if (studios.isEmpty) {
      groups = [
        hello,
        appear(const _Empty()),
        appear(_NewStudioButton(filled: true, onTap: newStudio)),
      ];
    } else {
      groups = [
        Column(
          children: [
            hello,
            if (focus != null) ...[
              const SizedBox(height: 26),
              appear(_Label("TODAY'S FOCUS")),
              const SizedBox(height: 8),
              appear(_Focus(studio: focus.studio, topic: focus.topic)),
            ],
          ],
        ),
        Column(
          children: [
            appear(_Label('YOUR STUDIOS')),
            const SizedBox(height: 12),
            appear(_StudioCarousel(studios: ordered, onNew: newStudio)),
          ],
        ),
        Column(
          children: [
            appear(_NewStudioButton(filled: false, onTap: newStudio)),
            const SizedBox(height: 16),
            appear(_Totals(studios: studios)),
            appear(
              SmPressable(
                semanticLabel: 'View all studios',
                onTap: () => context.go('/study/library'),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    'View all ${studios.length}',
                    style: t.small.copyWith(
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
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight - 24),
          child: Column(
            mainAxisAlignment: studios.isEmpty
                ? MainAxisAlignment.spaceEvenly
                : MainAxisAlignment.spaceBetween,
            children: [
              for (final (k, group) in groups.indexed) ...[
                if (k > 0) const SizedBox(height: 28),
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

/// The AI's pick for today: how long it takes, what it is, and Start.
class _Focus extends StatelessWidget {
  const _Focus({required this.studio, required this.topic});

  final Studio studio;
  final Topic topic;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return Column(
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${topic.estimatedStudyTimeMinutes}',
                style: TextStyle(
                  fontFamily: SmFonts.heading,
                  fontSize: 56,
                  height: 1.05,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.5,
                  color: c.text,
                ),
              ),
              TextSpan(
                text: ' min',
                style: TextStyle(
                  fontFamily: SmFonts.heading,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: c.muted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Review ${topic.title}',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: t.title.copyWith(fontSize: 16),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome_rounded, size: 13, color: c.accentSoft),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                'Your weakest topic · ${studio.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.small.copyWith(color: c.accentSoft),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Pill(
          label: 'Start',
          icon: Icons.play_arrow_rounded,
          filled: true,
          onTap: () => context.go('/study/${studio.id}/teach/${topic.id}'),
        ),
      ],
    );
  }
}

/// The studios as mastery rings to swipe through; the one in the middle is
/// big, its neighbours shrink and fade. A last ring makes a new studio.
class _StudioCarousel extends StatefulWidget {
  const _StudioCarousel({required this.studios, required this.onNew});

  final List<Studio> studios;
  final VoidCallback onNew;

  @override
  State<_StudioCarousel> createState() => _StudioCarouselState();
}

class _StudioCarouselState extends State<_StudioCarousel> {
  final _pages = PageController(viewportFraction: 0.42);
  var _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int page) {
    _pages.animateToPage(
      page,
      duration: smReduceMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final count = widget.studios.length + 1; // and the "new" ring
    final current = _page < widget.studios.length
        ? widget.studios[_page]
        : null;

    return Column(
      children: [
        SizedBox(
          height: 150,
          child: PageView.builder(
            controller: _pages,
            itemCount: count,
            onPageChanged: (page) {
              SmHaptics.select();
              setState(() => _page = page);
            },
            itemBuilder: (context, index) => AnimatedBuilder(
              animation: _pages,
              builder: (context, child) {
                final position =
                    _pages.hasClients && _pages.position.haveDimensions
                    ? _pages.page ?? _page.toDouble()
                    : _page.toDouble();
                final distance = (position - index).abs().clamp(0.0, 1.0);
                return Opacity(
                  opacity: 1 - distance * 0.6,
                  child: Transform.scale(
                    scale: 1 - distance * 0.45,
                    child: child,
                  ),
                );
              },
              child: Center(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (index != _page) {
                      SmHaptics.select();
                      _go(index);
                    } else if (index == widget.studios.length) {
                      SmHaptics.thud();
                      widget.onNew();
                    } else {
                      SmHaptics.select();
                      context.go('/study/${widget.studios[index].id}');
                    }
                  },
                  child: index == widget.studios.length
                      ? const _NewRing()
                      : SmRing(
                          value: widget.studios[index].overallMastery,
                          size: 138,
                          stroke: 8,
                          labelSize: 24,
                        ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: smReduceMotion(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          child: Column(
            key: ValueKey(current?.id ?? 'new'),
            children: [
              Text(
                current?.title ?? 'A new studio',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.title,
              ),
              const SizedBox(height: 2),
              Text(
                current == null
                    ? 'From your notes, a textbook, slides'
                    : current.topicCount == 0
                    ? 'Empty'
                    : '${current.topicCount} topics · '
                          '${current.flashcardCount} cards',
                style: t.small,
              ),
              const SizedBox(height: 8),
              SmPressable(
                semanticLabel: current == null
                    ? 'New study studio'
                    : 'Open ${current.title}',
                onTap: current == null
                    ? widget.onNew
                    : () => context.go('/study/${current.id}'),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(
                    current == null ? 'Create ›' : 'Open ›',
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
        const SizedBox(height: 4),
        _Dots(count: count, current: _page),
      ],
    );
  }
}

/// The last ring of the carousel: a dashed "+".
class _NewRing extends StatelessWidget {
  const _NewRing();

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    return SizedBox(
      width: 138,
      height: 138,
      child: CustomPaint(
        painter: _DashedCircle(c.line),
        child: Icon(Icons.add_rounded, size: 34, color: c.muted),
      ),
    );
  }
}

class _DashedCircle extends CustomPainter {
  _DashedCircle(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final rect = (Offset.zero & size).deflate(2);
    const dashes = 28;
    for (var i = 0; i < dashes; i++) {
      final start = i * 2 * math.pi / dashes;
      canvas.drawArc(rect, start, math.pi / dashes, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedCircle old) => old.color != color;
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    // Long lists show a window of dots around the current one.
    const most = 9;
    final first = (current - most ~/ 2).clamp(0, math.max(0, count - most));
    final last = math.min(count, first + most);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = first; i < last; i++)
          AnimatedContainer(
            duration: smReduceMotion(context)
                ? Duration.zero
                : const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            width: i == current ? 16 : 5,
            height: 5,
            decoration: BoxDecoration(
              color: i == current ? c.accent : c.line,
              borderRadius: BorderRadius.circular(9),
            ),
          ),
      ],
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
  });

  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final fg = filled ? Colors.white : c.text;
    return SmPressable(
      semanticLabel: label,
      haptic: SmHaptics.tap,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 11),
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
