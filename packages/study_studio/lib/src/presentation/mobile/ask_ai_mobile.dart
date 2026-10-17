import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/study_voice.dart';
import '../../data/api/sse_client.dart' show SseException;
import '../../domain/ask.dart';
import '../../domain/entities/topic.dart';
import 'mobile_header.dart';
import 'mobile_motion.dart';
import 'mobile_style.dart';

/// Three questions to start with, from the weakest topics (or the chosen
/// one): plain, a link between two of its ideas, and why it matters.
List<String> askSuggestions(List<Topic> topics, {Topic? focus}) {
  final weakest = focus != null
      ? [focus, focus, focus]
      : ([...topics]..sort((a, b) => a.mastery.compareTo(b.mastery)));
  if (weakest.isEmpty) return const [];
  Topic at(int i) => weakest[i % weakest.length];
  final second = at(1);
  final ideas = second.concepts;
  return {
    'Explain ${at(0).title} simply',
    ideas.length >= 2
        ? 'How does ${ideas[0].name} connect to ${ideas[1].name}?'
        : 'Give me an example of ${second.title}',
    'Why does ${at(2).title} matter?',
  }.toList();
}

/// The topic an answer is most about: titles count most, then its ideas.
Topic? askRelatedTopic(List<Topic> topics, String text) {
  final t = text.toLowerCase();
  Topic? best;
  var top = 0;
  for (final topic in topics) {
    var score = 0;
    if (topic.title.trim().length > 2 &&
        t.contains(topic.title.toLowerCase())) {
      score += 3;
    }
    for (final c in topic.concepts) {
      if (c.name.trim().length > 2 && t.contains(c.name.toLowerCase())) {
        score += 1;
      }
    }
    if (score > top) {
      top = score;
      best = topic;
    }
  }
  return best;
}

class _Turn {
  _Turn(this.question, this.topic);

  final String question;
  final Topic? topic;
  final text = StringBuffer();
  List<AskSource> sources = const [];
  var done = false;
  var failed = false;

  /// Shown instead of the generic failure (e.g. out of OctoCredits).
  String? problem;
  StreamSubscription<AskEvent>? sub;
}

/// Ask AI on a phone: a chat about the studio's files. Before the first
/// question it offers three from the weak spots; each answer cites its
/// sources and links to the topic it's about (lesson, quiz, cards).
class AskAiMobile extends StatefulWidget {
  const AskAiMobile({
    super.key,
    required this.topics,
    required this.fileCount,
    required this.ask,
    required this.onBack,
    required this.onLesson,
    required this.onQuiz,
    required this.onCards,
    this.voice,
  });

  final List<Topic> topics;
  final int fileCount;
  final Stream<AskEvent> Function(
    String question,
    Topic? topic,
    List<AskTurn> history,
  )
  ask;
  final VoidCallback onBack;
  final void Function(Topic topic) onLesson;
  final void Function(Topic topic) onQuiz;
  final void Function(Topic topic) onCards;
  final StudyVoice? voice;

  @override
  State<AskAiMobile> createState() => _AskAiMobileState();
}

class _AskAiMobileState extends State<AskAiMobile> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _turns = <_Turn>[];
  Topic? _topic;
  var _holding = false;

  bool get _busy => _turns.isNotEmpty && !_turns.last.done;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final t in _turns) {
      t.sub?.cancel();
    }
    widget.voice?.stop();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final q = (text ?? _input.text).trim();
    if (q.isEmpty || _busy) return;
    SmHaptics.thud();
    _input.clear();
    final history = [
      for (final t in _turns)
        if (t.done && !t.failed) AskTurn(t.question, t.text.toString().trim()),
    ];
    final turn = _Turn(q, _topic);
    setState(() => _turns.add(turn));
    _run(turn, history);
    _toEnd();
  }

  void _run(_Turn turn, List<AskTurn> history) {
    var first = true;
    turn.sub = widget
        .ask(turn.question, turn.topic, history)
        .listen(
          (e) {
            if (!mounted) return;
            setState(() {
              switch (e) {
                case AskSources(:final sources):
                  turn.sources = sources;
                case AskText(:final text):
                  if (first) SmHaptics.select();
                  first = false;
                  turn.text.write(text);
              }
            });
            _toEnd();
          },
          onError: (Object e) {
            if (!mounted) return;
            SmHaptics.error();
            setState(() {
              turn.problem = e is SseException && e.outOfCredits
                  ? e.message
                  : null;
              turn.failed = true;
              turn.done = true;
            });
          },
          onDone: () {
            if (!mounted) return;
            setState(() {
              turn.done = true;
              if (turn.text.toString().trim().isEmpty) turn.failed = true;
            });
            if (!turn.failed) SmHaptics.tap();
            _toEnd();
          },
        );
  }

  void _retry(_Turn turn) {
    final i = _turns.indexOf(turn);
    final history = [
      for (final t in _turns.take(i))
        if (t.done && !t.failed) AskTurn(t.question, t.text.toString().trim()),
    ];
    setState(() {
      turn.text.clear();
      turn.sources = const [];
      turn.failed = false;
      turn.problem = null;
      turn.done = false;
    });
    _run(turn, history);
  }

  void _clear() {
    for (final t in _turns) {
      t.sub?.cancel();
    }
    setState(_turns.clear);
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (smReduceMotion(context)) {
        _scroll.jumpTo(end);
      } else {
        _scroll.animateTo(
          end,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _holdStart() async {
    final voice = widget.voice;
    if (voice == null || _busy) return;
    SmHaptics.select();
    setState(() => _holding = true);
    String? said;
    try {
      said = await voice.listen(
        onPartial: (p) {
          if (mounted) _input.text = p;
        },
      );
    } on Object {
      said = null;
    }
    if (!mounted) return;
    setState(() => _holding = false);
    final words = (said ?? _input.text).trim();
    if (words.isEmpty) return;
    _send(words);
  }

  void _holdEnd() {
    if (_holding) widget.voice?.finishListening();
  }

  void _pick(Topic? topic) {
    if (_topic?.id == topic?.id) return;
    SmHaptics.select();
    setState(() => _topic = topic);
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final top = MediaQuery.paddingOf(context).top + SmHeader.clearance;
    return Scaffold(
      backgroundColor: c.background,
      body: SmHeaderPage(
        header: SmHeader(
          title: 'Ask AI',
          onBack: widget.onBack,
          trailing: _turns.isEmpty
              ? null
              : SmPressable(
                  semanticLabel: 'New chat',
                  haptic: SmHaptics.tap,
                  scale: 0.9,
                  onTap: _clear,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.edit_note_rounded, color: c.text),
                  ),
                ),
        ),
        child: Column(
          children: [
            SizedBox(height: top - 6),
            if (widget.topics.isNotEmpty)
              _Topics(topics: widget.topics, picked: _topic, onPick: _pick),
            Expanded(
              child: _turns.isEmpty
                  ? _Welcome(
                      fileCount: widget.fileCount,
                      suggestions: askSuggestions(widget.topics, focus: _topic),
                      onAsk: _send,
                    )
                  : ListView(
                      controller: _scroll,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                      children: [
                        for (final (i, turn) in _turns.indexed)
                          _TurnView(
                            key: ObjectKey(turn),
                            turn: turn,
                            last: i == _turns.length - 1,
                            related:
                                turn.topic ??
                                (turn.done
                                    ? askRelatedTopic(
                                        widget.topics,
                                        '${turn.question} ${turn.text}',
                                      )
                                    : null),
                            onRetry: () => _retry(turn),
                            onAsk: _send,
                            onLesson: widget.onLesson,
                            onQuiz: widget.onQuiz,
                            onCards: widget.onCards,
                          ),
                      ],
                    ),
            ),
            _Composer(
              controller: _input,
              focus: _focus,
              hint: _topic == null
                  ? 'Ask about your notes'
                  : 'Ask about ${_topic!.title}',
              busy: _busy,
              holding: _holding,
              canTalk: widget.voice != null,
              onSend: _send,
              onHoldStart: _holdStart,
              onHoldEnd: _holdEnd,
            ),
          ],
        ),
      ),
    );
  }
}

/// All topics, then each topic, weakest first: what to ask about.
class _Topics extends StatelessWidget {
  const _Topics({
    required this.topics,
    required this.picked,
    required this.onPick,
  });

  final List<Topic> topics;
  final Topic? picked;
  final void Function(Topic? topic) onPick;

  @override
  Widget build(BuildContext context) {
    final sorted = [...topics]..sort((a, b) => a.mastery.compareTo(b.mastery));
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          _TopicPill(
            label: 'All topics',
            on: picked == null,
            onTap: () => onPick(null),
          ),
          for (final t in sorted)
            _TopicPill(
              label: t.title,
              on: picked?.id == t.id,
              onTap: () => onPick(t),
            ),
        ],
      ),
    );
  }
}

class _TopicPill extends StatelessWidget {
  const _TopicPill({
    required this.label,
    required this.on,
    required this.onTap,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: SmPressable(
        semanticLabel: label,
        haptic: () {},
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: on ? c.accent : c.line),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.body.copyWith(
                fontSize: 12.5,
                color: on ? c.accentSoft : c.text,
                fontWeight: on ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Before the first question: an invitation and three to start with.
class _Welcome extends StatelessWidget {
  const _Welcome({
    required this.fileCount,
    required this.suggestions,
    required this.onAsk,
  });

  final int fileCount;
  final List<String> suggestions;
  final void Function(String question) onAsk;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    var i = 0;
    Widget appear(Widget child) => SmAppear(index: i++, child: child);
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            appear(
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: c.accent, width: 1.6),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: c.accentSoft,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(height: 14),
            appear(
              Text('What’s unclear?', style: t.greeting.copyWith(fontSize: 21)),
            ),
            const SizedBox(height: 6),
            appear(
              Text(
                fileCount == 1
                    ? 'Answers come from your file'
                    : 'Answers come from your $fileCount files',
                style: t.small.copyWith(fontSize: 13),
              ),
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 26),
              appear(
                Text(
                  'FROM YOUR WEAK SPOTS',
                  style: t.section.copyWith(fontSize: 11),
                ),
              ),
              const SizedBox(height: 10),
              for (final s in suggestions)
                appear(
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SmPressable(
                      semanticLabel: s,
                      onTap: () => onAsk(s),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: c.line),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                s,
                                style: t.body.copyWith(fontSize: 13.5),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.north_east_rounded,
                              size: 16,
                              color: c.hint,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A question, its answer as it streams, the sources, and where to go next.
class _TurnView extends StatelessWidget {
  const _TurnView({
    super.key,
    required this.turn,
    required this.last,
    required this.related,
    required this.onRetry,
    required this.onAsk,
    required this.onLesson,
    required this.onQuiz,
    required this.onCards,
  });

  final _Turn turn;
  final bool last;
  final Topic? related;
  final VoidCallback onRetry;
  final void Function(String question) onAsk;
  final void Function(Topic topic) onLesson;
  final void Function(Topic topic) onQuiz;
  final void Function(Topic topic) onCards;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final text = turn.text.toString().trim();
    final topic = related;
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SmAppear(
            index: 0,
            child: Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: c.line),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(5),
                    ),
                  ),
                  child: Text(
                    turn.question,
                    style: t.body.copyWith(fontSize: 14),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: c.accent, width: 1.4),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 12,
                  color: c.accentSoft,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  turn.topic == null
                      ? 'From your notes'
                      : 'From your notes · ${turn.topic!.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.small.copyWith(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (turn.failed)
            _Failed(onRetry: onRetry, message: turn.problem)
          else if (text.isEmpty)
            const Align(alignment: Alignment.centerLeft, child: _Thinking())
          else
            _Answer(text: text, streaming: !turn.done),
          if (turn.sources.isNotEmpty && !turn.failed) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final s in turn.sources) _SourcePill(source: s)],
            ),
          ],
          if (turn.done && !turn.failed) ...[
            if (topic != null) ...[
              const SizedBox(height: 16),
              SmAppear(
                index: 1,
                child: _InStudio(
                  topic: topic,
                  onLesson: () => onLesson(topic),
                  onQuiz: topic.quizQuestions.isEmpty
                      ? null
                      : () => onQuiz(topic),
                  onCards: topic.flashcards.isEmpty
                      ? null
                      : () => onCards(topic),
                ),
              ),
            ],
            if (last) ...[
              const SizedBox(height: 14),
              SmAppear(
                index: 2,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _FollowUp(
                      label: 'Explain simply',
                      onTap: () => onAsk('Explain that more simply'),
                    ),
                    _FollowUp(
                      label: 'Give an example',
                      onTap: () => onAsk('Give me an example of that'),
                    ),
                    if (topic != null && topic.quizQuestions.isNotEmpty)
                      _FollowUp(
                        label: 'Quiz me on this',
                        accent: true,
                        onTap: () => onQuiz(topic),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// The answer in the reading font: **key terms** in the accent, [n] as
/// small raised numbers, and a blinking cursor while it streams.
class _Answer extends StatelessWidget {
  const _Answer({required this.text, required this.streaming});

  final String text;
  final bool streaming;

  static final _marks = RegExp(r'\*\*(.+?)\*\*|\[(\d{1,2})\]');

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final base = TextStyle(
      fontFamily: SmFonts.reading,
      fontSize: 16,
      height: 1.6,
      color: c.text.withValues(alpha: 0.94),
    );
    final spans = <InlineSpan>[];
    var at = 0;
    for (final m in _marks.allMatches(text)) {
      if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
      if (m.group(1) != null) {
        spans.add(
          TextSpan(
            text: m.group(1),
            style: TextStyle(color: c.accentSoft, fontWeight: FontWeight.w600),
          ),
        );
      } else {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.top,
            child: Padding(
              padding: const EdgeInsets.only(left: 1, right: 1),
              child: Text(
                m.group(2)!,
                style: TextStyle(
                  fontFamily: SmFonts.body,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: c.accentSoft,
                ),
              ),
            ),
          ),
        );
      }
      at = m.end;
    }
    // A half-typed "**" or "[" at the end waits for the rest.
    var rest = text.substring(at);
    if (streaming) rest = rest.replaceFirst(RegExp(r'(\*\*[^*]*|\[\d*)$'), '');
    if (rest.isNotEmpty) spans.add(TextSpan(text: rest.replaceAll('**', '')));
    if (streaming) {
      spans.add(
        const WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _Cursor(),
        ),
      );
    }
    return Text.rich(TextSpan(style: base, children: spans));
  }
}

class _Cursor extends StatefulWidget {
  const _Cursor();

  @override
  State<_Cursor> createState() => _CursorState();
}

class _CursorState extends State<_Cursor> with SingleTickerProviderStateMixin {
  late final _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!smReduceMotion(context) && !_blink.isAnimating) {
      _blink.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    return FadeTransition(
      opacity: _blink,
      child: Container(
        width: 2,
        height: 17,
        margin: const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(
          color: c.accent,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// Three dots, rising in turn, until the first words arrive.
class _Thinking extends StatefulWidget {
  const _Thinking();

  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking>
    with SingleTickerProviderStateMixin {
  late final _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!smReduceMotion(context) && !_wave.isAnimating) _wave.repeat();
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    return Semantics(
      label: 'Thinking',
      child: AnimatedBuilder(
        animation: _wave,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Builder(
                builder: (context) {
                  final p = ((_wave.value - i * 0.18) % 1.0);
                  final lift = p < 0.4 ? (p < 0.2 ? p : 0.4 - p) * 20 : 0.0;
                  return Container(
                    width: 7,
                    height: 7,
                    margin: EdgeInsets.only(right: 5, bottom: lift),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color.lerp(c.hint, c.accent, lift / 4),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.onRetry, this.message});

  final VoidCallback onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            message ?? 'Couldn’t get an answer just now.',
            style: t.body.copyWith(fontSize: 14, color: c.muted),
          ),
        ),
        SmPressable(
          semanticLabel: 'Try again',
          haptic: SmHaptics.tap,
          onTap: onRetry,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: c.accent),
            ),
            child: Text(
              'Try again',
              style: t.body.copyWith(fontSize: 12.5, color: c.accentSoft),
            ),
          ),
        ),
      ],
    );
  }
}

/// "1 · Lecture 5.pdf": tap for the passage it came from.
class _SourcePill extends StatelessWidget {
  const _SourcePill({required this.source});

  final AskSource source;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return SmPressable(
      semanticLabel: 'Source ${source.number}, ${source.label}',
      onTap: () => _showSource(context, source),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: c.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${source.number}',
              style: t.small.copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: c.accentSoft,
              ),
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Text(
                source.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.small.copyWith(fontSize: 12, color: c.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showSource(BuildContext context, AskSource source) {
  final c = SmColors.of(context);
  final t = SmText.of(context);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.background,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.description_outlined, size: 18, color: c.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    source.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.title,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              source.snippet.trim().isEmpty
                  ? 'This part of your notes'
                  : '“${source.snippet.trim()}…”',
              style: TextStyle(
                fontFamily: SmFonts.reading,
                fontSize: 15,
                height: 1.6,
                color: c.text.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The topic the answer is about: how well it's known, and ways in.
class _InStudio extends StatelessWidget {
  const _InStudio({
    required this.topic,
    required this.onLesson,
    required this.onQuiz,
    required this.onCards,
  });

  final Topic topic;
  final VoidCallback onLesson;
  final VoidCallback? onQuiz;
  final VoidCallback? onCards;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    Widget way(IconData icon, String label, VoidCallback onTap) => Expanded(
      child: SmPressable(
        semanticLabel: label,
        haptic: SmHaptics.thud,
        onTap: onTap,
        child: Container(
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: c.line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: c.muted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.body.copyWith(fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('IN YOUR STUDIO', style: t.section.copyWith(fontSize: 10.5)),
        const SizedBox(height: 8),
        SmPressable(
          semanticLabel: 'Lesson: ${topic.title}',
          haptic: SmHaptics.thud,
          onTap: onLesson,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.line)),
            ),
            child: Row(
              children: [
                SmRing(value: topic.mastery, size: 34, stroke: 3, labelSize: 9),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    topic.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.title.copyWith(fontSize: 14),
                  ),
                ),
                Text('Lesson', style: t.small.copyWith(fontSize: 12.5)),
                Icon(Icons.chevron_right_rounded, size: 18, color: c.hint),
              ],
            ),
          ),
        ),
        if (onQuiz != null || onCards != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              if (onQuiz != null)
                way(
                  Icons.help_outline_rounded,
                  'Quiz · ${topic.quizQuestions.length}',
                  onQuiz!,
                ),
              if (onQuiz != null && onCards != null) const SizedBox(width: 8),
              if (onCards != null)
                way(
                  Icons.style_outlined,
                  'Cards · ${topic.flashcards.length}',
                  onCards!,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _FollowUp extends StatelessWidget {
  const _FollowUp({
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return SmPressable(
      semanticLabel: label,
      haptic: () {},
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: accent ? c.accent : c.line),
        ),
        child: Text(
          label,
          style: t.body.copyWith(
            fontSize: 12.5,
            color: accent ? c.accentSoft : c.text,
          ),
        ),
      ),
    );
  }
}

/// The pill input: a blinking accent cursor, no highlight. With nothing
/// typed, the button is a mic to hold (when there's a voice).
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focus,
    required this.hint,
    required this.busy,
    required this.holding,
    required this.canTalk,
    required this.onSend,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final String hint;
  final bool busy;
  final bool holding;
  final bool canTalk;
  final VoidCallback onSend;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final typed = controller.text.trim().isNotEmpty;
    final talk = canTalk && !typed && !busy;
    final ready = typed && !busy;
    final button = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: holding || ready ? c.accent : c.line,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (child, a) =>
            ScaleTransition(scale: a, child: child),
        child: Icon(
          busy
              ? Icons.more_horiz_rounded
              : talk
              ? Icons.mic_rounded
              : Icons.arrow_upward_rounded,
          key: ValueKey(busy ? 0 : (talk ? 1 : 2)),
          color: Colors.white,
          size: 21,
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        14,
        6,
        14,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(18, 5, 5, 5),
        decoration: BoxDecoration(
          color: c.raised,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: holding ? c.accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focus,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                cursorColor: c.accent,
                cursorWidth: 2,
                cursorRadius: const Radius.circular(2),
                style: t.body.copyWith(fontSize: 15.5),
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  hintText: holding ? 'Listening…' : hint,
                  hintStyle: t.body.copyWith(fontSize: 15.5, color: c.hint),
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (talk)
              Listener(
                onPointerDown: (_) => onHoldStart(),
                onPointerUp: (_) => onHoldEnd(),
                onPointerCancel: (_) => onHoldEnd(),
                child: Semantics(
                  button: true,
                  label: 'Hold to ask out loud',
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 160),
                    scale: holding ? 1.12 : 1,
                    child: button,
                  ),
                ),
              )
            else
              SmPressable(
                semanticLabel: 'Send',
                haptic: () {},
                scale: 0.88,
                onTap: ready ? onSend : null,
                child: button,
              ),
          ],
        ),
      ),
    );
  }
}
