import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/quiz_question.dart';
import '../../domain/entities/topic.dart';
import 'mobile_header.dart';
import 'mobile_motion.dart';
import 'mobile_style.dart';

/// The lesson's colours: each kind of content keeps its own, so it can be
/// found again at a glance.
class _Ink {
  _Ink.of(BuildContext context)
    : dark = Theme.of(context).brightness == Brightness.dark;

  final bool dark;

  Color get keyBg => dark ? const Color(0xFF2A1416) : const Color(0xFFFDECEC);
  Color get keyLabel =>
      dark ? const Color(0xFFFF6B70) : const Color(0xFFC81E2B);
  Color get keyText => dark ? const Color(0xFFFFE3E4) : const Color(0xFF5C0D12);

  Color get exampleBg =>
      dark ? const Color(0xFF14202E) : const Color(0xFFEAF2FB);
  Color get exampleLabel =>
      dark ? const Color(0xFF85B7EB) : const Color(0xFF185FA5);
  Color get exampleText =>
      dark ? const Color(0xFFD6E6F7) : const Color(0xFF0C2F55);

  Color get hookBg => dark ? const Color(0xFF2B2312) : const Color(0xFFFFF4D6);
  Color get hookLabel =>
      dark ? const Color(0xFFF5C04A) : const Color(0xFF8A5A00);
  Color get hookText =>
      dark ? const Color(0xFFFFE7A8) : const Color(0xFF4F3500);

  Color get mistakeBg =>
      dark ? const Color(0xFF262727) : const Color(0xFFEFEDE8);
  static const right = Color(0xFF30A46C);
}

/// One lesson, made for reading: a key sentence, the explanation in a
/// reading serif, more on demand, an example, the usual mistake, a memory
/// hook, why it matters, a question to check yourself, and where it came
/// from in the user's notes. Only what the topic has is shown.
class LessonMobile extends StatefulWidget {
  const LessonMobile({
    super.key,
    required this.topic,
    required this.studioTitle,
    required this.number,
    required this.total,
    required this.onBack,
    required this.onAsk,
    required this.onDone,
    this.onAnswer,
    this.hasNext = true,
  });

  final Topic topic;
  final String studioTitle;

  /// Which lesson this is, from 1, of [total].
  final int number;
  final int total;
  final VoidCallback onBack;

  /// Opens Ask AI on this topic.
  final VoidCallback onAsk;

  /// "Got it": marks it learned and moves on.
  final VoidCallback onDone;
  final bool hasNext;

  /// The check-yourself answer, right or not.
  final void Function(bool correct)? onAnswer;

  static const sizeKey = 'study.lesson.size';

  /// Reading sizes Aa steps through.
  static const sizes = [15.5, 17.0, 19.0];

  @override
  State<LessonMobile> createState() => _LessonMobileState();
}

class _LessonMobileState extends State<LessonMobile> {
  final _scroll = ScrollController();
  final _read = ValueNotifier<double>(0);
  var _size = 1;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final max = _scroll.position.maxScrollExtent;
      _read.value = max <= 0 ? 1 : (_scroll.offset / max).clamp(0, 1);
    });
    unawaited(_loadSize());
  }

  Future<void> _loadSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(LessonMobile.sizeKey);
      if (saved != null && mounted) {
        setState(() => _size = saved.clamp(0, LessonMobile.sizes.length - 1));
      }
    } on Object {
      // The middle size.
    }
  }

  Future<void> _nextSize() async {
    SmHaptics.select();
    setState(() => _size = (_size + 1) % LessonMobile.sizes.length);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(LessonMobile.sizeKey, _size);
    } on Object {
      // For this lesson only.
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _read.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final topic = widget.topic;
    final top = MediaQuery.paddingOf(context).top + SmHeader.clearance;
    final size = LessonMobile.sizes[_size];
    final question = topic.quizQuestions
        .where((q) => q.choices.length >= 2)
        .firstOrNull;
    var i = 0;
    Widget appear(Widget child) => SmAppear(index: i++, child: child);

    final sections = <Widget>[
      appear(_Title(topic: topic, studioTitle: widget.studioTitle)),
      if (topic.definition.trim().isNotEmpty)
        appear(_KeySentence(text: topic.definition, size: size)),
      if (topic.simpleExplanation.trim().isNotEmpty)
        appear(_Reading(text: topic.simpleExplanation, size: size)),
      if (topic.detailedExplanation.trim().isNotEmpty)
        appear(_Deeper(text: topic.detailedExplanation, size: size)),
      if (topic.examples.isNotEmpty) ...[
        const _Heading('Example'),
        for (final (n, e) in topic.examples.take(2).indexed)
          appear(_Example(text: e, label: n == 0 ? 'FOR EXAMPLE' : 'ANOTHER')),
      ],
      if (topic.commonMistakes.isNotEmpty)
        appear(_Mistakes(mistakes: topic.commonMistakes)),
      if (topic.memoryHooks.isNotEmpty)
        appear(_Hook(text: topic.memoryHooks.first)),
      if (topic.whyItMatters.trim().isNotEmpty) ...[
        const _Heading('Why it matters'),
        appear(_Reading(text: topic.whyItMatters, size: size)),
      ],
      if (question != null) ...[
        const _Heading('Check yourself'),
        appear(_Check(question: question, onAnswer: widget.onAnswer)),
      ],
      if (topic.sources.isNotEmpty) appear(_Sources(topic: topic)),
    ];

    return Scaffold(
      backgroundColor: c.background,
      body: SmHeaderPage(
        header: SmHeader(
          title: topic.title,
          onBack: widget.onBack,
          trailing: SmPressable(
            semanticLabel: 'Text size',
            haptic: () {},
            scale: 0.9,
            onTap: _nextSize,
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _Ink.of(context).dark
                    ? const Color(0x14FFFFFF)
                    : c.raised.withValues(alpha: 0.8),
              ),
              child: Text(
                'Aa',
                style: TextStyle(
                  fontFamily: SmFonts.heading,
                  fontWeight: FontWeight.w700,
                  fontSize: 12 + _size * 1.5,
                  color: c.text,
                ),
              ),
            ),
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: SingleChildScrollView(
                controller: _scroll,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(24, top + 12, 24, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: sections,
                ),
              ),
            ),
            // How far through: a hairline under the header.
            Positioned(
              top: top - 10,
              left: 26,
              right: 26,
              child: Row(
                children: [
                  Text(
                    '${widget.number} of ${widget.total}',
                    style: SmText.of(
                      context,
                    ).small.copyWith(fontSize: 10.5, color: c.hint),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: SizedBox(
                        height: 3,
                        child: ValueListenableBuilder<double>(
                          valueListenable: _read,
                          builder: (context, v, _) => Stack(
                            children: [
                              Positioned.fill(child: ColoredBox(color: c.line)),
                              FractionallySizedBox(
                                widthFactor: v,
                                child: ColoredBox(color: c.accent),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _Foot(
                hasNext: widget.hasNext,
                onAsk: widget.onAsk,
                onDone: widget.onDone,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The reading serif at [size] and [weight].
TextStyle _serif(BuildContext context, double size, {int weight = 400}) =>
    TextStyle(
      fontFamily: SmFonts.reading,
      fontSize: size,
      height: 1.68,
      fontWeight: weight >= 500 ? FontWeight.w500 : FontWeight.w400,
      fontVariations: [
        FontVariation('wght', weight.toDouble()),
        FontVariation('opsz', size.clamp(12, 36)),
      ],
      color: SmColors.of(context).text,
    );

class _Title extends StatelessWidget {
  const _Title({required this.topic, required this.studioTitle});

  final Topic topic;
  final String studioTitle;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final minutes = topic.estimatedStudyTimeMinutes;
    final level = switch (topic.difficulty) {
      <= 2 => 'Easy',
      3 => 'Medium',
      _ => 'Hard',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          [
            studioTitle.toUpperCase(),
            if (minutes > 0) '$minutes MIN READ',
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.section.copyWith(fontSize: 11, letterSpacing: 1.3),
        ),
        const SizedBox(height: 8),
        Text(
          topic.title,
          style: TextStyle(
            fontFamily: SmFonts.heading,
            fontSize: 28,
            height: 1.14,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            color: c.text,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.speed_rounded, size: 15, color: c.hint),
            const SizedBox(width: 4),
            Text(level, style: t.small.copyWith(fontSize: 12)),
            if (topic.importance >= 4) ...[
              const SizedBox(width: 14),
              Icon(Icons.star_outline_rounded, size: 15, color: c.hint),
              const SizedBox(width: 4),
              Text('Key topic', style: t.small.copyWith(fontSize: 12)),
            ],
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontFamily: SmFonts.heading,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.3,
            color: color,
          ),
        ),
      ],
    ),
  );
}

class _Block extends StatelessWidget {
  const _Block({required this.color, required this.child, this.tilt = 0});

  final Color color;
  final Widget child;
  final double tilt;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Transform.rotate(
      angle: tilt,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: child,
      ),
    ),
  );
}

class _KeySentence extends StatelessWidget {
  const _KeySentence({required this.text, required this.size});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    return _Block(
      color: ink.keyBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label(
            icon: Icons.format_quote_rounded,
            text: 'IN ONE SENTENCE',
            color: ink.keyLabel,
          ),
          Text(
            text.trim(),
            style: _serif(
              context,
              size + 2,
              weight: 500,
            ).copyWith(height: 1.5, color: ink.keyText),
          ),
        ],
      ),
    );
  }
}

/// Paragraphs of the reading text.
class _Reading extends StatelessWidget {
  const _Reading({required this.text, required this.size});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final paragraphs = text
        .split(RegExp(r'\n\s*\n|\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in paragraphs)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Text(
              p,
              style: _serif(
                context,
                size,
              ).copyWith(color: c.text.withValues(alpha: 0.9)),
            ),
          ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 12),
    child: Text(
      text,
      style: TextStyle(
        fontFamily: SmFonts.heading,
        fontSize: 19,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: SmColors.of(context).text,
      ),
    ),
  );
}

/// The detailed explanation, folded until asked for.
class _Deeper extends StatefulWidget {
  const _Deeper({required this.text, required this.size});

  final String text;
  final double size;

  @override
  State<_Deeper> createState() => _DeeperState();
}

class _DeeperState extends State<_Deeper> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SmPressable(
            semanticLabel: _open ? 'Show less' : 'Go deeper',
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: c.accentSoft,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _open ? 'Show less' : 'Go deeper',
                    style: t.body.copyWith(
                      color: c.accentSoft,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _Reading(text: widget.text, size: widget.size),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _Example extends StatelessWidget {
  const _Example({required this.text, required this.label});

  final String text;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    return _Block(
      color: ink.exampleBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label(
            icon: Icons.lightbulb_outline_rounded,
            text: label,
            color: ink.exampleLabel,
          ),
          Text(
            text.trim(),
            style: TextStyle(
              fontFamily: SmFonts.body,
              fontSize: 14.5,
              height: 1.6,
              color: ink.exampleText,
            ),
          ),
        ],
      ),
    );
  }
}

class _Mistakes extends StatelessWidget {
  const _Mistakes({required this.mistakes});

  final List<String> mistakes;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final ink = _Ink.of(context);
    return _Block(
      color: ink.mistakeBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label(
            icon: Icons.warning_amber_rounded,
            text: mistakes.length == 1 ? 'COMMON MISTAKE' : 'COMMON MISTAKES',
            color: ink.keyLabel,
          ),
          for (final (i, m) in mistakes.take(3).indexed)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Icon(Icons.close_rounded, size: 16, color: c.accent),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      m.trim(),
                      style: TextStyle(
                        fontFamily: SmFonts.body,
                        fontSize: 14.5,
                        height: 1.55,
                        color: c.text.withValues(alpha: 0.88),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Hook extends StatelessWidget {
  const _Hook({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    return _Block(
      color: ink.hookBg,
      tilt: -0.01,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label(
            icon: Icons.psychology_outlined,
            text: 'MEMORY HOOK',
            color: ink.hookLabel,
          ),
          Text(
            text.trim(),
            style: TextStyle(
              fontFamily: SmFonts.heading,
              fontSize: 17,
              height: 1.45,
              fontWeight: FontWeight.w600,
              color: ink.hookText,
            ),
          ),
        ],
      ),
    );
  }
}

/// One question; tap an answer, see if it was right and why.
class _Check extends StatefulWidget {
  const _Check({required this.question, this.onAnswer});

  final QuizQuestion question;
  final void Function(bool correct)? onAnswer;

  @override
  State<_Check> createState() => _CheckState();
}

class _CheckState extends State<_Check> {
  String? _picked;

  void _pick(String choice) {
    if (_picked != null) return;
    final right = widget.question.isCorrect(choice);
    if (right) {
      SmHaptics.done();
    } else {
      SmHaptics.error();
    }
    setState(() => _picked = choice);
    widget.onAnswer?.call(right);
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final q = widget.question;
    const letters = 'ABCDEFGH';
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            q.question.trim(),
            style: t.body.copyWith(fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: 12),
          for (final (i, choice) in q.choices.indexed)
            Builder(
              builder: (context) {
                final answered = _picked != null;
                final right = q.isCorrect(choice);
                final mine = _picked == choice;
                final state = !answered
                    ? null
                    : right
                    ? _Ink.right
                    : mine
                    ? c.accent
                    : null;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SmPressable(
                    semanticLabel: choice,
                    haptic: () {},
                    onTap: answered ? null : () => _pick(choice),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: state?.withValues(alpha: 0.14) ?? c.raised,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: state ?? Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 240),
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
                            child: state == null
                                ? Text(
                                    letters[i % letters.length],
                                    style: t.small.copyWith(color: c.hint),
                                  )
                                : Icon(
                                    right
                                        ? Icons.check_rounded
                                        : Icons.close_rounded,
                                    size: 15,
                                    color: Colors.white,
                                  ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              choice,
                              style: t.body.copyWith(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            alignment: Alignment.topCenter,
            child: _picked == null || q.explanation.trim().isEmpty
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${q.isCorrect(_picked!) ? 'Right. ' : 'Not quite. '}'
                      '${q.explanation.trim()}',
                      style: t.small.copyWith(fontSize: 13, height: 1.55),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Sources extends StatelessWidget {
  const _Sources({required this.topic});

  final Topic topic;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final seen = <String>{};
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('FROM YOUR NOTES', style: t.section.copyWith(fontSize: 11)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in topic.sources)
                if (seen.add('${s.fileName}#${s.page}'))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: c.raised,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 14,
                          color: c.muted,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          s.page == null
                              ? s.fileName
                              : '${s.fileName} · p.${s.page}',
                          style: t.small.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ask AI and "Got it", over a fade.
class _Foot extends StatelessWidget {
  const _Foot({
    required this.hasNext,
    required this.onAsk,
    required this.onDone,
  });

  final bool hasNext;
  final VoidCallback onAsk;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    return Container(
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
      child: Row(
        children: [
          SmPressable(
            semanticLabel: 'Ask AI about this',
            haptic: SmHaptics.tap,
            scale: 0.9,
            onTap: onAsk,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: c.raised,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                color: c.accentSoft,
                size: 21,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SmPressable(
              semanticLabel: hasNext ? 'Got it, next topic' : 'Got it',
              haptic: SmHaptics.thud,
              onTap: onDone,
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: c.accent.withValues(alpha: 0.3),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      hasNext ? 'Got it · Next topic' : 'Got it',
                      style: const TextStyle(
                        fontFamily: SmFonts.heading,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      hasNext ? Icons.arrow_forward_rounded : Icons.check,
                      size: 18,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
