import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/entities/scenario.dart';
import 'mobile_header.dart';
import 'mobile_motion.dart';
import 'mobile_style.dart';

const _green = Color(0xFF30A46C);

enum _Step { brief, investigate, decide, outcome }

/// The phone's Scenario mode: a case in three steps on one page — the
/// brief, clues to turn over, then your call — each unlocking the next.
/// The button at the foot always says the next move.
class ScenarioMobile extends StatefulWidget {
  const ScenarioMobile({
    super.key,
    required this.scenario,
    required this.number,
    required this.total,
    required this.onBack,
    required this.onAnother,
    required this.onLesson,
    required this.onDecided,
  });

  final Scenario scenario;
  final int number;
  final int total;
  final VoidCallback onBack;
  final VoidCallback onAnother;

  /// Opens a related lesson by its name.
  final void Function(String topic) onLesson;

  /// The call was locked in: right or not.
  final void Function(bool correct) onDecided;

  @override
  State<ScenarioMobile> createState() => _ScenarioMobileState();
}

class _ScenarioMobileState extends State<ScenarioMobile> {
  final _scroll = ScrollController();
  final _investigateKey = GlobalKey();
  final _decideKey = GlobalKey();
  final _outcomeKey = GlobalKey();

  var _step = _Step.brief;
  final _found = <String>{};
  String? _picked;

  Scenario get _s => widget.scenario;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _reveal(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx == null) return;
      unawaited(
        Scrollable.ensureVisible(
          ctx,
          duration: smReduceMotion(context)
              ? Duration.zero
              : const Duration(milliseconds: 520),
          curve: Curves.easeOutCubic,
          alignment: 0.04,
        ),
      );
    });
  }

  /// The foot button: what it says, and whether it can be pressed.
  (String, IconData, VoidCallback?) get _next => switch (_step) {
    _Step.brief => (
      'Start investigating',
      Icons.arrow_downward_rounded,
      () {
        SmHaptics.thud();
        setState(
          () => _step = _s.clues.isEmpty ? _Step.decide : _Step.investigate,
        );
        _reveal(_s.clues.isEmpty ? _decideKey : _investigateKey);
      },
    ),
    _Step.investigate => (
      _found.isEmpty ? 'Turn over a clue first' : 'Make your call',
      Icons.arrow_downward_rounded,
      _found.isEmpty
          ? null
          : () {
              SmHaptics.thud();
              setState(() => _step = _Step.decide);
              _reveal(_decideKey);
            },
    ),
    _Step.decide => (
      _picked == null ? 'Choose an action' : 'Lock in',
      Icons.lock_outline_rounded,
      _picked == null ? null : _lockIn,
    ),
    _Step.outcome => (
      widget.total > 1 ? 'Try another' : 'Done',
      widget.total > 1 ? Icons.shuffle_rounded : Icons.check_rounded,
      () {
        SmHaptics.tap();
        if (widget.total > 1) {
          widget.onAnother();
        } else {
          widget.onBack();
        }
      },
    ),
  };

  void _lockIn() {
    final right = _s.isCorrect(_picked!);
    if (right) {
      SmHaptics.done();
    } else {
      SmHaptics.error();
    }
    widget.onDecided(right);
    setState(() => _step = _Step.outcome);
    _reveal(_outcomeKey);
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final top = MediaQuery.paddingOf(context).top + SmHeader.clearance;
    final (label, icon, onNext) = _next;
    final at = _step.index;

    return Scaffold(
      backgroundColor: c.background,
      body: SmHeaderPage(
        header: SmHeader(
          title: _s.title,
          onBack: widget.onBack,
          trailing: widget.total > 1
              ? SmPressable(
                  semanticLabel: 'Another scenario',
                  haptic: SmHaptics.tap,
                  scale: 0.9,
                  onTap: widget.onAnother,
                  child: SizedBox(
                    width: 38,
                    height: 38,
                    child: Icon(Icons.shuffle_rounded, size: 19, color: c.text),
                  ),
                )
              : null,
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: ListView(
                controller: _scroll,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(20, top + 2, 20, 120),
                children: [
                  _Steps(
                    at: math.min(at, 2),
                    number: widget.number,
                    total: widget.total,
                  ),
                  const SizedBox(height: 18),
                  SmAppear(index: 0, child: _Brief(scenario: _s)),
                  if (_s.clues.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    _Locked(
                      key: _investigateKey,
                      open: at >= _Step.investigate.index,
                      child: _Clues(
                        clues: _s.clues,
                        found: _found,
                        enabled:
                            _step == _Step.investigate || _step == _Step.decide,
                        onFlip: (id) {
                          SmHaptics.select();
                          setState(() => _found.add(id));
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  _Locked(
                    key: _decideKey,
                    open: at >= _Step.decide.index,
                    child: _Decide(
                      scenario: _s,
                      picked: _picked,
                      locked: _step == _Step.outcome,
                      onPick: (id) {
                        SmHaptics.select();
                        setState(() => _picked = id);
                      },
                    ),
                  ),
                  if (_step == _Step.outcome) ...[
                    const SizedBox(height: 18),
                    _Outcome(
                      key: _outcomeKey,
                      scenario: _s,
                      right: _s.isCorrect(_picked!),
                      onLesson: widget.onLesson,
                    ),
                  ],
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  14,
                  28,
                  14,
                  14 + MediaQuery.paddingOf(context).bottom,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, 0.45],
                    colors: [c.background.withValues(alpha: 0), c.background],
                  ),
                ),
                child: SmPressable(
                  semanticLabel: label,
                  haptic: () {},
                  onTap: onNext,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    height: 50,
                    decoration: BoxDecoration(
                      color: onNext == null ? c.raised : c.accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0, 0.3),
                            end: Offset.zero,
                          ).animate(a),
                          child: child,
                        ),
                      ),
                      child: Row(
                        key: ValueKey(label),
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              fontFamily: SmFonts.heading,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: onNext == null ? c.hint : Colors.white,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Icon(
                            icon,
                            size: 18,
                            color: onNext == null ? c.hint : Colors.white,
                          ),
                        ],
                      ),
                    ),
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

/// Brief · Investigate · Decide, and which scenario this is.
class _Steps extends StatelessWidget {
  const _Steps({required this.at, required this.number, required this.total});

  final int at;
  final int number;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    const names = ['BRIEF', 'INVESTIGATE', 'DECIDE'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (total > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Scenario $number of $total',
              style: t.small.copyWith(fontSize: 11.5),
            ),
          ),
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 320),
                      height: 4,
                      decoration: BoxDecoration(
                        color: i <= at ? c.accent : c.line,
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      names[i],
                      style: t.section.copyWith(
                        fontSize: 10,
                        color: i <= at ? c.text : c.hint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, this.icon, this.color});

  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final ink = color ?? c.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color ?? c.line, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: ink),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.small.copyWith(fontSize: 11.5, color: ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _Brief extends StatelessWidget {
  const _Brief({required this.scenario});

  final Scenario scenario;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final s = scenario;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            _Tag(icon: Icons.speed_rounded, label: s.difficultyLabel),
            _Tag(
              icon: Icons.schedule_rounded,
              label: '${s.estimatedMinutes} min',
            ),
            for (final skill in s.skills.take(3)) _Tag(label: skill),
          ],
        ),
        const SizedBox(height: 16),
        Text('THE SITUATION', style: t.section.copyWith(fontSize: 11)),
        const SizedBox(height: 8),
        Text(
          s.problem.trim(),
          style: TextStyle(
            fontFamily: SmFonts.reading,
            fontSize: 17,
            height: 1.62,
            color: c.text.withValues(alpha: 0.92),
          ),
        ),
        if (s.question.trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF2A1416) : const Color(0xFFFDECEC),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'YOUR TASK',
                  style: t.section.copyWith(
                    fontSize: 11,
                    color: dark
                        ? const Color(0xFFFF6B70)
                        : const Color(0xFFC81E2B),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  s.question.trim(),
                  style: TextStyle(
                    fontFamily: SmFonts.heading,
                    fontSize: 16,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                    color: dark
                        ? const Color(0xFFFFE3E4)
                        : const Color(0xFF5C0D12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A step not reached yet: faded, and taps pass it by.
class _Locked extends StatelessWidget {
  const _Locked({super.key, required this.open, required this.child});

  final bool open;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !open,
    child: AnimatedOpacity(
      duration: const Duration(milliseconds: 420),
      opacity: open ? 1 : 0.32,
      child: child,
    ),
  );
}

class _Clues extends StatelessWidget {
  const _Clues({
    required this.clues,
    required this.found,
    required this.enabled,
    required this.onFlip,
  });

  final List<ScenarioClue> clues;
  final Set<String> found;
  final bool enabled;
  final ValueChanged<String> onFlip;

  @override
  Widget build(BuildContext context) {
    final t = SmText.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('CLUES', style: t.section.copyWith(fontSize: 11)),
            const Spacer(),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, a) =>
                  ScaleTransition(scale: a, child: child),
              child: Text(
                '${found.length} of ${clues.length} found',
                key: ValueKey(found.length),
                style: t.small.copyWith(fontSize: 11.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Tap a card to inspect it.',
          style: t.small.copyWith(fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, box) {
            final w = (box.maxWidth - 8) / 2;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final clue in clues)
                  SizedBox(
                    width: w,
                    child: _ClueCard(
                      clue: clue,
                      open: found.contains(clue.id),
                      onTap: enabled && !found.contains(clue.id)
                          ? () => onFlip(clue.id)
                          : null,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Face down (dashed) until tapped; flips over to the finding.
class _ClueCard extends StatelessWidget {
  const _ClueCard({required this.clue, required this.open, this.onTap});

  final ScenarioClue clue;
  final bool open;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SmPressable(
      semanticLabel: open
          ? '${clue.label}: ${clue.detail}'
          : 'Inspect ${clue.label}',
      haptic: () {},
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: open ? 1 : 0),
        duration: smReduceMotion(context)
            ? Duration.zero
            : const Duration(milliseconds: 520),
        curve: Curves.easeOutBack,
        builder: (context, v, _) {
          final angle = v.clamp(0.0, 1.0) * math.pi;
          final back = angle > math.pi / 2;
          final Widget face = back
              ? Container(
                  key: const ValueKey('back'),
                  constraints: const BoxConstraints(minHeight: 108),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: dark
                        ? const Color(0xFF14202E)
                        : const Color(0xFFEAF2FB),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clue.label.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.section.copyWith(
                          fontSize: 10,
                          color: dark
                              ? const Color(0xFF85B7EB)
                              : const Color(0xFF185FA5),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        clue.detail.trim(),
                        style: TextStyle(
                          fontFamily: SmFonts.body,
                          fontSize: 12.5,
                          height: 1.45,
                          color: dark
                              ? const Color(0xFFD6E6F7)
                              : const Color(0xFF0C2F55),
                        ),
                      ),
                    ],
                  ),
                )
              : CustomPaint(
                  painter: _Dashes(color: c.line),
                  child: Container(
                    height: 108,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.raised,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.search_rounded, size: 20, color: c.hint),
                        const Spacer(),
                        Text(
                          clue.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.title.copyWith(fontSize: 13),
                        ),
                        Text('Inspect', style: t.small.copyWith(color: c.hint)),
                      ],
                    ),
                  ),
                );
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateY(angle),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()..rotateY(back ? math.pi : 0),
              child: face,
            ),
          );
        },
      ),
    );
  }
}

class _Dashes extends CustomPainter {
  _Dashes({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)),
      );
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 9) {
        canvas.drawPath(m.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Dashes old) => old.color != color;
}

class _Decide extends StatelessWidget {
  const _Decide({
    required this.scenario,
    required this.picked,
    required this.locked,
    required this.onPick,
  });

  final Scenario scenario;
  final String? picked;
  final bool locked;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('YOUR CALL', style: t.section.copyWith(fontSize: 11)),
        const SizedBox(height: 6),
        Text('What would you do first?', style: t.title.copyWith(fontSize: 17)),
        const SizedBox(height: 12),
        for (final (i, o) in scenario.options.indexed)
          Builder(
            builder: (context) {
              final mine = picked == o.id;
              final right = scenario.isCorrect(o.id);
              final state = !locked
                  ? (mine ? c.accent : null)
                  : right
                  ? _green
                  : mine
                  ? c.accent
                  : null;
              final dim = locked && state == null;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 260),
                  opacity: dim ? 0.4 : 1,
                  child: SmPressable(
                    semanticLabel: o.label,
                    haptic: () {},
                    onTap: locked ? null : () => onPick(o.id),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: state?.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: state ?? c.line, width: 1.5),
                      ),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: state,
                              border: Border.all(
                                color: state ?? c.line,
                                width: 1.5,
                              ),
                            ),
                            child: locked && state != null
                                ? Icon(
                                    right
                                        ? Icons.check_rounded
                                        : Icons.close_rounded,
                                    size: 14,
                                    color: Colors.white,
                                  )
                                : Text(
                                    'ABCDEFGH'[i % 8],
                                    style: t.small.copyWith(
                                      fontFamily: SmFonts.heading,
                                      fontWeight: FontWeight.w700,
                                      color: state != null
                                          ? Colors.white
                                          : c.hint,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Text(
                              o.label,
                              style: t.body.copyWith(fontSize: 14),
                            ),
                          ),
                        ],
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

class _Outcome extends StatelessWidget {
  const _Outcome({
    super.key,
    required this.scenario,
    required this.right,
    required this.onLesson,
  });

  final Scenario scenario;
  final bool right;
  final void Function(String topic) onLesson;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tint = right ? _green : c.accent;
    final bg = right
        ? (dark ? const Color(0xFF14281E) : const Color(0xFFE6F4EC))
        : (dark ? const Color(0xFF2E1517) : const Color(0xFFFCE9EA));
    final ink = right
        ? (dark ? const Color(0xFFCDEBDD) : const Color(0xFF0E3B25))
        : (dark ? const Color(0xFFF2D4D5) : const Color(0xFF5C0D12));
    final s = scenario;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SmAppear(
          index: 0,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      right ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      color: tint,
                      size: 22,
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        right ? 'Good call' : 'Not the best first move',
                        style: TextStyle(
                          fontFamily: SmFonts.heading,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: tint,
                        ),
                      ),
                    ),
                  ],
                ),
                if (s.outcomeLabel.trim().isNotEmpty) ...[
                  const SizedBox(height: 9),
                  _Tag(label: s.outcomeLabel.trim(), color: tint),
                ],
                if (s.reasoning.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    s.reasoning.trim(),
                    style: TextStyle(
                      fontFamily: SmFonts.reading,
                      fontSize: 15,
                      height: 1.58,
                      color: ink,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (s.skills.isNotEmpty) ...[
          const SizedBox(height: 20),
          SmAppear(
            index: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WHAT YOU PRACTISED',
                  style: t.section.copyWith(fontSize: 11),
                ),
                const SizedBox(height: 6),
                for (final skill in s.skills)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: _green,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            skill,
                            style: t.body.copyWith(fontSize: 13.5),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (s.relatedTopics.isNotEmpty) ...[
          const SizedBox(height: 18),
          SmAppear(
            index: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RELATED LESSONS',
                  style: t.section.copyWith(fontSize: 11),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final topic in s.relatedTopics)
                      SmPressable(
                        semanticLabel: 'Open $topic',
                        onTap: () => onLesson(topic),
                        child: _Tag(
                          icon: Icons.menu_book_rounded,
                          label: topic,
                          color: c.text.withValues(alpha: 0.6),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
