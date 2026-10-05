import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/entities/quiz_question.dart';
import 'mobile_motion.dart';
import 'mobile_style.dart';

const _right = Color(0xFF30A46C);

/// The phone's Quiz me: one question at a time, marked as soon as it is
/// answered, a sheet with the why, and a score at the end with what to
/// review. Multiple choice, true or false (two big tiles), fill the blank
/// and short answer (typed).
class QuizMobile extends StatefulWidget {
  const QuizMobile({
    super.key,
    required this.questions,
    required this.topicTitles,
    required this.onClose,
    required this.onAnswer,
    required this.onReview,
  });

  final List<QuizQuestion> questions;

  /// Topic titles by id, for the label and "Review these".
  final Map<String, String> topicTitles;
  final VoidCallback onClose;
  final void Function(QuizQuestion question, bool correct) onAnswer;

  /// Opens a topic to review.
  final void Function(String topicId) onReview;

  @override
  State<QuizMobile> createState() => _QuizMobileState();
}

class _QuizMobileState extends State<QuizMobile> {
  late List<QuizQuestion> _round = widget.questions;
  final _results = <bool>[];
  var _index = 0;
  String? _given;
  bool? _correct;

  bool get _finished => _index >= _round.length;

  void _answer(String given) {
    if (_correct != null) return;
    final q = _round[_index];
    final right = q.isCorrect(given);
    if (right) {
      SmHaptics.done();
    } else {
      SmHaptics.error();
    }
    setState(() {
      _given = given;
      _correct = right;
      _results.add(right);
    });
    widget.onAnswer(q, right);
  }

  void _next() {
    SmHaptics.tap();
    setState(() {
      _index++;
      _given = null;
      _correct = null;
    });
  }

  void _retryMissed() {
    SmHaptics.thud();
    final missed = [
      for (final (i, q) in _round.indexed)
        if (!_results[i]) q,
    ];
    setState(() {
      _round = missed;
      _results.clear();
      _index = 0;
      _given = null;
      _correct = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final q = _finished ? null : _round[_index];
    return Scaffold(
      backgroundColor: c.background,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: Column(
              children: [
                SizedBox(height: top + 6),
                _Bar(
                  total: _round.length,
                  results: _results,
                  index: _index,
                  onClose: widget.onClose,
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeOutCubic,
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(
                        position: Tween(
                          begin: const Offset(0.06, 0),
                          end: Offset.zero,
                        ).animate(a),
                        child: child,
                      ),
                    ),
                    child: q == null
                        ? _Results(
                            key: const ValueKey('results'),
                            round: _round,
                            results: _results,
                            topicTitles: widget.topicTitles,
                            onReview: widget.onReview,
                            onRetry: _retryMissed,
                            onDone: widget.onClose,
                          )
                        : _Question(
                            key: ValueKey('$_index-${q.id}-${_round.length}'),
                            question: q,
                            topic: widget.topicTitles[q.topicId] ?? '',
                            given: _given,
                            correct: _correct,
                            onAnswer: _answer,
                          ),
                  ),
                ),
              ],
            ),
          ),
          // The why, rising once the question is answered.
          AnimatedPositioned(
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutBack,
            left: 0,
            right: 0,
            bottom: _correct == null ? -320 : 0,
            child: q == null || _correct == null
                ? const SizedBox.shrink()
                : _Why(
                    correct: _correct!,
                    question: q,
                    last: _index == _round.length - 1,
                    bottom: bottom,
                    onNext: _next,
                  ),
          ),
        ],
      ),
    );
  }
}

/// ✕, a segment per question (green right, red wrong), the count.
class _Bar extends StatelessWidget {
  const _Bar({
    required this.total,
    required this.results,
    required this.index,
    required this.onClose,
  });

  final int total;
  final List<bool> results;
  final int index;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final done = index >= total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 18, 0),
      child: Row(
        children: [
          SmPressable(
            semanticLabel: 'Close quiz',
            haptic: SmHaptics.tap,
            scale: 0.9,
            onTap: onClose,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(Icons.close_rounded, color: c.text, size: 22),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < total; i++)
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 5,
                      margin: EdgeInsets.only(right: i < total - 1 ? 3 : 0),
                      decoration: BoxDecoration(
                        color: i < results.length
                            ? (results[i] ? _right : c.accent)
                            : i == index
                            ? c.muted.withValues(alpha: 0.6)
                            : c.line,
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            done ? 'Done' : '${index + 1}/$total',
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

class _Question extends StatefulWidget {
  const _Question({
    super.key,
    required this.question,
    required this.topic,
    required this.given,
    required this.correct,
    required this.onAnswer,
  });

  final QuizQuestion question;
  final String topic;
  final String? given;
  final bool? correct;
  final ValueChanged<String> onAnswer;

  @override
  State<_Question> createState() => _QuestionState();
}

class _QuestionState extends State<_Question> {
  final _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  bool get _typed =>
      widget.question.choices.length < 2 ||
      widget.question.type == QuizType.fillBlank ||
      widget.question.type == QuizType.shortAnswer;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final q = widget.question;
    final label = switch (q.type) {
      _ when _typed && q.type == QuizType.fillBlank => 'FILL THE BLANK',
      _ when _typed => 'SHORT ANSWER',
      QuizType.trueFalse => 'TRUE OR FALSE',
      _ => 'MULTIPLE CHOICE',
    };
    final blank = q.type == QuizType.fillBlank && q.question.contains('____');
    final questionStyle = TextStyle(
      fontFamily: SmFonts.reading,
      fontSize: 21,
      height: 1.42,
      color: c.text,
    );

    final Widget answers;
    if (_typed) {
      answers = _Typed(
        controller: _input,
        given: widget.given,
        correct: widget.correct,
        answer: q.answer,
        hint: blank ? 'Type the missing word' : 'Your answer',
        onSubmit: () {
          if (_input.text.trim().isNotEmpty) widget.onAnswer(_input.text);
        },
      );
    } else if (q.type == QuizType.trueFalse && q.choices.length == 2) {
      answers = Row(
        children: [
          for (final (i, choice) in q.choices.indexed) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: _Choice(
                choice: choice,
                tile: true,
                icon: i == 0 ? Icons.check_rounded : Icons.close_rounded,
                question: q,
                given: widget.given,
                onTap: () => widget.onAnswer(choice),
              ),
            ),
          ],
        ],
      );
    } else {
      answers = Column(
        children: [
          for (final (i, choice) in q.choices.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _Choice(
                choice: choice,
                letter: 'ABCDEFGH'[i % 8],
                question: q,
                given: widget.given,
                onTap: () => widget.onAnswer(choice),
              ),
            ),
        ],
      );
    }

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 300),
      children: [
        Text(
          [
            label,
            if (widget.topic.isNotEmpty) widget.topic.toUpperCase(),
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.section.copyWith(fontSize: 11, letterSpacing: 1.3),
        ),
        const SizedBox(height: 12),
        if (blank)
          _BlankQuestion(
            question: q.question,
            filled: widget.given ?? _input.text,
            style: questionStyle,
          )
        else
          Text(q.question.trim(), style: questionStyle),
        const SizedBox(height: 24),
        answers,
      ],
    );
  }
}

/// The question with its blank showing what is being typed.
class _BlankQuestion extends StatelessWidget {
  const _BlankQuestion({
    required this.question,
    required this.filled,
    required this.style,
  });

  final String question;
  final String filled;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final i = question.indexOf('____');
    final end = i + question.substring(i).indexOf(RegExp(r'[^_]|$'));
    final word = filled.trim().isEmpty ? '   ?   ' : ' ${filled.trim()} ';
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: question.substring(0, i)),
          TextSpan(
            text: word,
            style: TextStyle(
              fontFamily: SmFonts.heading,
              fontWeight: FontWeight.w700,
              color: c.accentSoft,
              decoration: TextDecoration.underline,
              decorationColor: c.accent,
              decorationThickness: 2,
            ),
          ),
          TextSpan(text: question.substring(end == i ? i + 4 : end)),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.choice,
    required this.question,
    required this.given,
    required this.onTap,
    this.letter,
    this.icon,
    this.tile = false,
  });

  final String choice;
  final QuizQuestion question;
  final String? given;
  final VoidCallback onTap;
  final String? letter;
  final IconData? icon;
  final bool tile;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final answered = given != null;
    final right = question.isCorrect(choice);
    final mine = given == choice;
    final state = !answered
        ? null
        : right
        ? _right
        : mine
        ? c.accent
        : null;
    final dim = answered && state == null;
    final mark = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: state,
        border: Border.all(color: state ?? c.line, width: 1.5),
      ),
      child: state == null
          ? (icon != null
                ? Icon(icon, size: 15, color: c.hint)
                : Text(
                    letter ?? '',
                    style: t.small.copyWith(
                      fontFamily: SmFonts.heading,
                      fontWeight: FontWeight.w700,
                      color: c.hint,
                    ),
                  ))
          : Icon(
              right ? Icons.check_rounded : Icons.close_rounded,
              size: 16,
              color: Colors.white,
            ),
    );
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: dim ? 0.45 : 1,
      child: SmPressable(
        semanticLabel: choice,
        haptic: () {},
        onTap: answered ? null : onTap,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          scale: state != null && (mine || right) ? 1.02 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: tile
                ? const EdgeInsets.symmetric(vertical: 22, horizontal: 10)
                : const EdgeInsets.symmetric(vertical: 14, horizontal: 15),
            decoration: BoxDecoration(
              color: state?.withValues(alpha: 0.14) ?? c.raised,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: state ?? Colors.transparent,
                width: 1.5,
              ),
            ),
            child: tile
                ? Column(
                    children: [
                      mark,
                      const SizedBox(height: 8),
                      Text(
                        choice,
                        style: t.body.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      mark,
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          choice,
                          style: t.body.copyWith(fontSize: 15),
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

/// A pill to type in, with its own send button; no box lights up, only
/// the cursor blinks. Wrong answers shake.
class _Typed extends StatefulWidget {
  const _Typed({
    required this.controller,
    required this.given,
    required this.correct,
    required this.answer,
    required this.hint,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String? given;
  final bool? correct;
  final String answer;
  final String hint;
  final VoidCallback onSubmit;

  @override
  State<_Typed> createState() => _TypedState();
}

class _TypedState extends State<_Typed> with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  @override
  void didUpdateWidget(_Typed old) {
    super.didUpdateWidget(old);
    if (old.correct == null &&
        widget.correct == false &&
        !smReduceMotion(context)) {
      unawaited(_shake.forward(from: 0));
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final answered = widget.correct != null;
    final ready = widget.controller.text.trim().isNotEmpty && !answered;
    final state = !answered
        ? null
        : widget.correct!
        ? _right
        : c.accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedBuilder(
          animation: _shake,
          builder: (context, child) => Transform.translate(
            offset: Offset(
              math.sin(_shake.value * math.pi * 6) * 6 * (1 - _shake.value),
              0,
            ),
            child: child,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.fromLTRB(18, 5, 5, 5),
            decoration: BoxDecoration(
              color: state?.withValues(alpha: 0.12) ?? c.raised,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: state ?? Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    enabled: !answered,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => widget.onSubmit(),
                    cursorColor: c.accent,
                    cursorWidth: 2,
                    cursorRadius: const Radius.circular(2),
                    style: t.body.copyWith(fontSize: 16),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      hintText: widget.hint,
                      hintStyle: t.body.copyWith(fontSize: 16, color: c.hint),
                    ),
                  ),
                ),
                SmPressable(
                  semanticLabel: 'Check',
                  haptic: () {},
                  scale: 0.88,
                  onTap: ready ? widget.onSubmit : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: state ?? (ready ? c.accent : c.line),
                    ),
                    child: AnimatedRotation(
                      duration: const Duration(milliseconds: 260),
                      turns: ready ? -0.25 : 0,
                      child: Icon(
                        answered
                            ? (widget.correct!
                                  ? Icons.check_rounded
                                  : Icons.close_rounded)
                            : Icons.arrow_forward_rounded,
                        size: 20,
                        color: ready || answered ? Colors.white : c.hint,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          child: widget.correct == false
              ? Padding(
                  padding: const EdgeInsets.only(top: 10, left: 6),
                  child: Text.rich(
                    TextSpan(
                      text: 'Answer: ',
                      children: [
                        TextSpan(
                          text: widget.answer,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    style: t.small.copyWith(fontSize: 13, color: c.accentSoft),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Right or not, why, and Continue.
class _Why extends StatelessWidget {
  const _Why({
    required this.correct,
    required this.question,
    required this.last,
    required this.bottom,
    required this.onNext,
  });

  final bool correct;
  final QuizQuestion question;
  final bool last;
  final double bottom;
  final VoidCallback onNext;

  static const _cheers = ['Nice!', 'Spot on', 'Correct', 'You got it'];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final c = SmColors.of(context);
    final tint = correct ? _right : c.accent;
    final bg = correct
        ? (dark ? const Color(0xFF14281E) : const Color(0xFFE6F4EC))
        : (dark ? const Color(0xFF2E1517) : const Color(0xFFFCE9EA));
    final text = correct
        ? (dark ? const Color(0xFFCDEBDD) : const Color(0xFF0E3B25))
        : (dark ? const Color(0xFFF2D4D5) : const Color(0xFF5C0D12));
    return Container(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 16 + bottom),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: tint,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                correct
                    ? _cheers[question.id.hashCode.abs() % _cheers.length]
                    : 'Not quite',
                style: TextStyle(
                  fontFamily: SmFonts.heading,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: tint,
                ),
              ),
            ],
          ),
          if (question.explanation.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: Text(
                  question.explanation.trim(),
                  style: TextStyle(
                    fontFamily: SmFonts.reading,
                    fontSize: 15.5,
                    height: 1.55,
                    color: text,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          SmPressable(
            semanticLabel: last ? 'See results' : 'Continue',
            haptic: () {},
            onTap: onNext,
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    last ? 'See results' : 'Continue',
                    style: const TextStyle(
                      fontFamily: SmFonts.heading,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    super.key,
    required this.round,
    required this.results,
    required this.topicTitles,
    required this.onReview,
    required this.onRetry,
    required this.onDone,
  });

  final List<QuizQuestion> round;
  final List<bool> results;
  final Map<String, String> topicTitles;
  final void Function(String topicId) onReview;
  final VoidCallback onRetry;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final right = results.where((r) => r).length;
    final total = round.length;
    final pct = total == 0 ? 0.0 : right / total;
    final missedTopics = <String>{
      for (final (i, q) in round.indexed)
        if (!results[i]) q.topicId,
    }.toList();
    final missed = total - right;
    final good = pct >= 0.75;
    final title = pct == 1
        ? 'Perfect run'
        : good
        ? 'Great work'
        : pct >= 0.5
        ? 'Getting there'
        : 'Keep at it';
    return Column(
      children: [
        Expanded(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 20),
            children: [
              SmAppear(
                index: 0,
                child: Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: pct),
                    duration: smReduceMotion(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 1100),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => SizedBox(
                      width: 156,
                      height: 156,
                      child: CustomPaint(
                        painter: _ScoreRing(
                          value: v,
                          track: c.line,
                          color: good ? _right : c.accent,
                        ),
                        child: Center(
                          child: Text(
                            '$right/$total',
                            style: TextStyle(
                              fontFamily: SmFonts.heading,
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              color: c.text,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SmAppear(
                index: 1,
                child: Column(
                  children: [
                    Text(title, style: t.greeting.copyWith(fontSize: 23)),
                    const SizedBox(height: 4),
                    Text(
                      right == 0
                          ? 'Every answer still counts toward mastery'
                          : 'Mastery went up on $right '
                                '${right == 1 ? 'answer' : 'answers'}',
                      style: t.small.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (missedTopics.isNotEmpty) ...[
                const SizedBox(height: 28),
                SmAppear(
                  index: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'REVIEW THESE',
                        style: t.section.copyWith(fontSize: 11),
                      ),
                      const SizedBox(height: 6),
                      for (final id in missedTopics)
                        SmPressable(
                          semanticLabel: 'Review ${topicTitles[id] ?? ''}',
                          onTap: () => onReview(id),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(top: BorderSide(color: c.line)),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.menu_book_rounded,
                                  size: 18,
                                  color: c.accentSoft,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    topicTitles[id] ?? 'Topic',
                                    style: t.body.copyWith(fontSize: 14),
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: c.hint,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            14,
            8,
            14,
            14 + MediaQuery.paddingOf(context).bottom,
          ),
          child: missed > 0
              ? Row(
                  children: [
                    Expanded(
                      child: _Button(
                        label: 'Retry $missed missed',
                        icon: Icons.refresh_rounded,
                        color: c.accent,
                        onTap: onRetry,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _Button(
                      icon: Icons.check_rounded,
                      color: c.raised,
                      textColor: c.text,
                      label: 'Done',
                      round: true,
                      onTap: onDone,
                    ),
                  ],
                )
              : _Button(
                  label: 'Done',
                  icon: Icons.check_rounded,
                  color: _right,
                  onTap: onDone,
                ),
        ),
      ],
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.textColor = Colors.white,
    this.round = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color textColor;
  final VoidCallback onTap;
  final bool round;

  @override
  Widget build(BuildContext context) => SmPressable(
    semanticLabel: label,
    haptic: SmHaptics.tap,
    onTap: onTap,
    child: Container(
      height: 50,
      width: round ? 50 : null,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: round
          ? Icon(icon, color: textColor, size: 20)
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: textColor, size: 19),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: SmFonts.heading,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ],
            ),
    ),
  );
}

class _ScoreRing extends CustomPainter {
  _ScoreRing({required this.value, required this.track, required this.color});

  final double value;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 11.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (value > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * value,
        false,
        paint..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_ScoreRing old) =>
      old.value != value || old.color != color || old.track != track;
}
