import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/card_schedule.dart';
import '../../domain/entities/flashcard.dart';
import 'mobile_motion.dart';
import 'mobile_style.dart';

const _green = Color(0xFF30A46C);

/// The four ratings: label, colour, haptic.
const _grades = [
  ('Again', Color(0xFFFF5258)),
  ('Hard', Color(0xFFF5A623)),
  ('Good', _green),
  ('Easy', Color(0xFF378ADD)),
];

/// The phone's flashcards: the cards due now as a deck, tap to flip, rate
/// how well you knew it (each rating says when the card comes back), or
/// swipe: right for Good, left for Again. Again brings it back this session.
class FlashcardsMobile extends StatefulWidget {
  const FlashcardsMobile({
    super.key,
    required this.cards,
    required this.topicTitles,
    required this.onClose,
    required this.onGrade,
    this.now,
  });

  /// Every card in scope; the session takes the ones due.
  final List<Flashcard> cards;
  final Map<String, String> topicTitles;
  final VoidCallback onClose;
  final void Function(Flashcard card, int grade) onGrade;

  /// The clock (tests).
  final DateTime Function()? now;

  @override
  State<FlashcardsMobile> createState() => _FlashcardsMobileState();
}

class _FlashcardsMobileState extends State<FlashcardsMobile>
    with TickerProviderStateMixin {
  /// Cards as they stand after this session's ratings.
  late final Map<String, Flashcard> _cards = {
    for (final c in widget.cards) c.id: c,
  };
  late List<String> _queue;
  var _total = 0;
  var _rated = 0;
  var _knew = 0;
  var _again = 0;
  var _started = false;

  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final AnimationController _fly = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  var _drag = Offset.zero;
  var _flyDir = 0.0;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    final due = [
      for (final c in widget.cards)
        if (CardSchedule.isDue(c, _now)) c.id,
    ];
    _start(due);
    _started = due.isNotEmpty;
  }

  void _start(List<String> ids) {
    _queue = ids;
    _total = ids.length;
    _rated = 0;
    _knew = 0;
    _again = 0;
    _flip.value = 0;
    _fly.value = 0;
    _drag = Offset.zero;
  }

  @override
  void dispose() {
    _flip.dispose();
    _fly.dispose();
    super.dispose();
  }

  bool get _flipped => _flip.value > 0.5;

  void _toggle() {
    if (_fly.isAnimating) return;
    SmHaptics.select();
    if (_flipped) {
      unawaited(_flip.reverse());
    } else {
      unawaited(_flip.forward());
    }
    setState(() {});
  }

  Future<void> _rate(int grade) async {
    if (_queue.isEmpty || _fly.isAnimating) return;
    switch (grade) {
      case 0:
        unawaited(HapticFeedback.mediumImpact());
      case 3:
        SmHaptics.done();
      default:
        SmHaptics.tap();
    }
    final id = _queue.first;
    final card = _cards[id]!;
    widget.onGrade(card, grade);
    _cards[id] = CardSchedule.review(card, grade, _now);
    _flyDir = grade == 0 ? -1 : 1;
    if (!smReduceMotion(context)) await _fly.forward(from: 0);
    if (!mounted) return;
    setState(() {
      _queue.removeAt(0);
      if (grade == 0) {
        _again++;
        _queue.add(id);
      } else {
        _rated++;
        if (grade >= 2) _knew++;
      }
      _flip.value = 0;
      _fly.value = 0;
      _drag = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;

    final Widget body;
    if (!_started) {
      body = _CaughtUp(
        cards: _cards.values.toList(),
        now: _now,
        onStudyAnyway: () => setState(() {
          _start([for (final c in widget.cards) c.id]);
          _started = true;
        }),
        onClose: widget.onClose,
      );
    } else if (_queue.isEmpty) {
      body = _Done(
        total: _total,
        knew: _knew,
        again: _again,
        cards: _cards.values.toList(),
        now: _now,
        onAgain: () => setState(() {
          final due = [
            for (final c in _cards.values)
              if (CardSchedule.isDue(c, _now)) c.id,
          ];
          _start(due.isEmpty ? [for (final c in widget.cards) c.id] : due);
        }),
        onClose: widget.onClose,
      );
    } else {
      final card = _cards[_queue.first]!;
      body = Column(
        children: [
          _Tally(knew: _knew, again: _again, left: _queue.length),
          // The card sits a little below the middle of the room it has.
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final h = math.min(box.maxHeight - 40, 420.0);
                return Padding(
                  padding: EdgeInsets.only(
                    top: math.max(16, (box.maxHeight - h) * 0.62),
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      height: h,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: _deck(card),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(
            height: 112 + bottom,
            child: AnimatedBuilder(
              animation: _flip,
              builder: (context, _) {
                final shown = _flip.value > 0.5;
                return Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 34,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: shown ? 0 : 1,
                        child: Text(
                          'Tap the card to see the answer',
                          textAlign: TextAlign.center,
                          style: SmText.of(
                            context,
                          ).small.copyWith(fontSize: 12.5, color: c.hint),
                        ),
                      ),
                    ),
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      left: 14,
                      right: 14,
                      top: shown ? 14 : 40,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 240),
                        opacity: shown ? 1 : 0,
                        child: IgnorePointer(
                          ignoring: !shown,
                          child: _Ratings(card: card, now: _now, onRate: _rate),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          SizedBox(height: top + 6),
          _TopBar(
            done: _rated,
            total: _started ? _total : 0,
            onClose: widget.onClose,
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: KeyedSubtree(
                key: ValueKey(
                  !_started
                      ? 'caught-up'
                      : _queue.isEmpty
                      ? 'done'
                      : 'deck',
                ),
                child: body,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The card on top of a visible stack; it flips, follows a swipe, and
  /// flies off when rated.
  Widget _deck(Flashcard card) {
    final c = SmColors.of(context);
    final behind = _queue.length - 1;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (behind >= 2)
          _Ghost(
            offset: 18,
            scale: 0.9,
            color: c.raised.withValues(alpha: 0.5),
          ),
        if (behind >= 1) _Ghost(offset: 9, scale: 0.95, color: c.raised),
        AnimatedBuilder(
          animation: Listenable.merge([_flip, _fly]),
          builder: (context, _) {
            final fly = Curves.easeIn.transform(_fly.value);
            final dx = _drag.dx + _flyDir * 460 * fly;
            final turn = (dx / 900).clamp(-0.4, 0.4);
            final hint = _flipped ? (_drag.dx / 120).clamp(-1.0, 1.0) : 0.0;
            return Opacity(
              opacity: (1 - fly).clamp(0, 1),
              child: Transform.translate(
                offset: Offset(dx, _drag.dy * 0.15),
                child: Transform.rotate(
                  angle: turn,
                  child: GestureDetector(
                    onTap: _toggle,
                    onHorizontalDragUpdate: _flipped
                        ? (d) => setState(() => _drag += d.delta)
                        : null,
                    onHorizontalDragEnd: _flipped
                        ? (d) {
                            final v = d.primaryVelocity ?? 0;
                            if (_drag.dx > 110 || v > 900) {
                              unawaited(_rate(2));
                            } else if (_drag.dx < -110 || v < -900) {
                              unawaited(_rate(0));
                            } else {
                              setState(() => _drag = Offset.zero);
                            }
                          }
                        : null,
                    child: _FlipCard(
                      card: card,
                      topic: widget.topicTitles[card.topicId] ?? '',
                      turn: _flip.value,
                      swipe: hint,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Ghost extends StatelessWidget {
  const _Ghost({
    required this.offset,
    required this.scale,
    required this.color,
  });

  final double offset;
  final double scale;
  final Color color;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: Transform.translate(
      offset: Offset(0, offset),
      child: Transform.scale(
        scale: scale,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(28),
          ),
        ),
      ),
    ),
  );
}

/// Both faces: the question on the page's raised colour, the answer on the
/// opposite one, so they never look alike.
class _FlipCard extends StatelessWidget {
  const _FlipCard({
    required this.card,
    required this.topic,
    required this.turn,
    required this.swipe,
  });

  final Flashcard card;
  final String topic;

  /// 0 the question, 1 the answer.
  final double turn;

  /// -1..1 while swiping: Again (left) or Good (right).
  final double swipe;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final eased = Curves.easeInOutBack.transform(turn.clamp(0, 1));
    final angle = eased * math.pi;
    final back = angle > math.pi / 2;
    final face = back
        ? _Face(
            label: 'ANSWER',
            text: card.back,
            foot: card.front,
            bg: c.text,
            fg: c.background,
            accent: c.accent,
            weight: 500,
          )
        : _Face(
            label: topic.toUpperCase(),
            text: card.front,
            foot: null,
            bg: c.raised,
            fg: c.text,
            accent: c.hint,
            weight: 400,
          );
    final stamp = swipe.abs() < 0.15
        ? null
        : Positioned(
            top: 22,
            left: swipe > 0 ? 22 : null,
            right: swipe < 0 ? 22 : null,
            child: Opacity(
              opacity: swipe.abs().clamp(0, 1),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: swipe > 0 ? _green : _grades[0].$2,
                    width: 2,
                  ),
                ),
                child: Text(
                  swipe > 0 ? 'GOOD' : 'AGAIN',
                  style: t.small.copyWith(
                    fontFamily: SmFonts.heading,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: swipe > 0 ? _green : _grades[0].$2,
                  ),
                ),
              ),
            ),
          );
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0012)
        ..rotateY(angle),
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..rotateY(back ? math.pi : 0),
        child: Stack(
          children: [
            Positioned.fill(child: face),
            ?stamp,
          ],
        ),
      ),
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({
    required this.label,
    required this.text,
    required this.foot,
    required this.bg,
    required this.fg,
    required this.accent,
    required this.weight,
  });

  final String label;
  final String text;
  final String? foot;
  final Color bg;
  final Color fg;
  final Color accent;
  final double weight;

  @override
  Widget build(BuildContext context) {
    final len = text.length;
    final size = len < 60
        ? 24.0
        : len < 120
        ? 21.0
        : 18.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: SmFonts.heading,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
              color: accent,
            ),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Text(
                  text.trim(),
                  style: TextStyle(
                    fontFamily: SmFonts.reading,
                    fontSize: size,
                    height: 1.4,
                    fontVariations: [FontVariation('wght', weight)],
                    color: fg,
                  ),
                ),
              ),
            ),
          ),
          if (foot != null)
            Text(
              foot!.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: SmFonts.body,
                fontSize: 12,
                height: 1.4,
                color: fg.withValues(alpha: 0.5),
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.touch_app_outlined, size: 14, color: accent),
                const SizedBox(width: 5),
                Text(
                  'tap to flip',
                  style: TextStyle(
                    fontFamily: SmFonts.body,
                    fontSize: 12,
                    color: accent,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Again / Hard / Good / Easy as outline pills, each with when the card
/// comes back.
class _Ratings extends StatelessWidget {
  const _Ratings({required this.card, required this.now, required this.onRate});

  final Flashcard card;
  final DateTime now;
  final ValueChanged<int> onRate;

  @override
  Widget build(BuildContext context) {
    final t = SmText.of(context);
    return Row(
      children: [
        for (final (g, (label, color)) in _grades.indexed) ...[
          if (g > 0) const SizedBox(width: 7),
          Expanded(
            child: SmPressable(
              semanticLabel: label,
              haptic: () {},
              scale: 0.93,
              onTap: () => onRate(g),
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: color.withValues(alpha: 0.75),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: SmFonts.heading,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      CardSchedule.wait(card, g, now),
                      style: t.small.copyWith(fontSize: 10.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.done,
    required this.total,
    required this.onClose,
  });

  final int done;
  final int total;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 18, 0),
      child: Row(
        children: [
          SmPressable(
            semanticLabel: 'Close flashcards',
            haptic: SmHaptics.tap,
            scale: 0.9,
            onTap: onClose,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(Icons.close_rounded, size: 22, color: c.text),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: SizedBox(
                height: 5,
                child: Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: c.line)),
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: total == 0 ? 0 : done / total),
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => FractionallySizedBox(
                        widthFactor: v,
                        child: ColoredBox(color: c.accent),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            total == 0 ? '' : '${math.min(done + 1, total)}/$total',
            style: t.small.copyWith(
              fontFamily: SmFonts.heading,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tally extends StatelessWidget {
  const _Tally({required this.knew, required this.again, required this.left});

  final int knew;
  final int again;
  final int left;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    Widget item(int n, String label, Color color) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, a) =>
              ScaleTransition(scale: a, child: child),
          child: Text(
            '$n',
            key: ValueKey(n),
            style: TextStyle(
              fontFamily: SmFonts.heading,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: t.small.copyWith(fontSize: 12)),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          item(knew, 'knew', _green),
          const SizedBox(width: 18),
          item(again, 'again', _grades[0].$2),
          const SizedBox(width: 18),
          item(left, 'left', c.text),
        ],
      ),
    );
  }
}

/// "Next review in 1 day · 3 cards", from the cards' schedules.
String? _nextReview(List<Flashcard> cards, DateTime now) {
  final later = [
    for (final c in cards)
      if (c.dueDate != null && c.dueDate!.isAfter(now)) c.dueDate!,
  ]..sort();
  if (later.isEmpty) return null;
  final first = later.first;
  final batch = later
      .where((d) => !d.isAfter(first.add(const Duration(hours: 1))))
      .length;
  return 'Next review in ${CardSchedule.label(first.difference(now))}'
      ' · $batch ${batch == 1 ? 'card' : 'cards'}';
}

class _Done extends StatelessWidget {
  const _Done({
    required this.total,
    required this.knew,
    required this.again,
    required this.cards,
    required this.now,
    required this.onAgain,
    required this.onClose,
  });

  final int total;
  final int knew;
  final int again;
  final List<Flashcard> cards;
  final DateTime now;
  final VoidCallback onAgain;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final next = _nextReview(cards, now);
    Widget stat(int n, String label, Color color) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.raised,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$n',
              style: TextStyle(
                fontFamily: SmFonts.heading,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(label, style: t.small.copyWith(fontSize: 12)),
          ],
        ),
      ),
    );
    return _EndPage(
      icon: Icons.style_rounded,
      title: 'Deck done',
      line:
          '$total ${total == 1 ? 'card' : 'cards'}'
          '${again > 0 ? ' · $again came back' : ''}',
      body: Column(
        children: [
          Row(
            children: [
              stat(knew, 'knew it', _green),
              const SizedBox(width: 10),
              stat(total - knew, 'to practise', const Color(0xFFF5A623)),
            ],
          ),
          if (next != null) ...[
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.event_outlined, size: 15, color: c.muted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(next, style: t.small.copyWith(fontSize: 12.5)),
                ),
              ],
            ),
          ],
        ],
      ),
      primary: 'Study again',
      onPrimary: onAgain,
      onClose: onClose,
    );
  }
}

/// Nothing due: when the next cards are, and Study anyway.
class _CaughtUp extends StatelessWidget {
  const _CaughtUp({
    required this.cards,
    required this.now,
    required this.onStudyAnyway,
    required this.onClose,
  });

  final List<Flashcard> cards;
  final DateTime now;
  final VoidCallback onStudyAnyway;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final next = _nextReview(cards, now);
    return _EndPage(
      icon: Icons.check_rounded,
      title: cards.isEmpty ? 'No flashcards yet' : 'All caught up',
      line: cards.isEmpty
          ? 'Cards appear as your studio finishes building.'
          : next ?? 'Nothing is due right now.',
      body: const SizedBox.shrink(),
      primary: cards.isEmpty ? null : 'Study anyway',
      onPrimary: onStudyAnyway,
      onClose: onClose,
    );
  }
}

class _EndPage extends StatelessWidget {
  const _EndPage({
    required this.icon,
    required this.title,
    required this.line,
    required this.body,
    required this.primary,
    required this.onPrimary,
    required this.onClose,
  });

  final IconData icon;
  final String title;
  final String line;
  final Widget body;
  final String? primary;
  final VoidCallback onPrimary;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  SmAppear(
                    index: 0,
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _green.withValues(alpha: 0.16),
                      ),
                      child: Icon(icon, size: 44, color: _green),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SmAppear(
                    index: 1,
                    child: Column(
                      children: [
                        Text(title, style: t.greeting.copyWith(fontSize: 24)),
                        const SizedBox(height: 4),
                        Text(
                          line,
                          textAlign: TextAlign.center,
                          style: t.small.copyWith(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SmAppear(index: 2, child: body),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            14,
            8,
            14,
            14 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Row(
            children: [
              if (primary != null) ...[
                Expanded(
                  child: SmPressable(
                    semanticLabel: primary,
                    haptic: SmHaptics.thud,
                    onTap: onPrimary,
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(
                        color: c.accent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.refresh_rounded,
                            color: Colors.white,
                            size: 19,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            primary!,
                            style: const TextStyle(
                              fontFamily: SmFonts.heading,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              SmPressable(
                semanticLabel: 'Finish',
                haptic: SmHaptics.tap,
                onTap: onClose,
                child: Container(
                  width: primary == null ? 160 : 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: c.raised,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Icon(Icons.check_rounded, color: c.text),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
