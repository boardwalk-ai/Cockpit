import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../application/study_voice.dart';
import 'mobile_motion.dart';
import 'mobile_style.dart';

const _green = Color(0xFF30A46C);
const _amber = Color(0xFFF5A623);

/// One rapid-fire question.
class RecallItem {
  const RecallItem({
    required this.topicId,
    required this.question,
    required this.answer,
    this.hint = '',
    this.explanation = '',
  });

  final String topicId;
  final String question;
  final String answer;
  final String hint;
  final String explanation;

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\b(the|a|an)\b'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Lenient: the same words, one inside the other, or most of the
  /// answer's words said.
  bool matches(String said) {
    final a = _norm(answer);
    final n = _norm(said);
    if (n.isEmpty || a.isEmpty) return false;
    if (n == a) return true;
    if (a.length > 3 && n.contains(a)) return true;
    if (n.length > 3 && a.contains(n)) return true;
    final words = a.split(' ').toSet();
    final heard = n.split(' ').toSet();
    if (words.length >= 2) {
      final hit = words.intersection(heard).length;
      return hit / words.length >= 0.6;
    }
    return false;
  }
}

enum _Phase { reading, answering, feedback, done }

/// The phone's Lightning recall: seven seconds a question on a ring in the
/// middle of the screen, around the mic. Questions are read aloud (unless
/// muted) and the clock starts after; answer by holding the mic and
/// speaking, or by typing. Right answers move on by themselves.
class LightningMobile extends StatefulWidget {
  const LightningMobile({
    super.key,
    required this.items,
    required this.topicTitles,
    required this.onClose,
    required this.onAnswer,
    required this.onReview,
    this.voice,
    this.seconds = 7,
    this.judge,
  });

  final List<RecallItem> items;
  final Map<String, String> topicTitles;
  final VoidCallback onClose;
  final void Function(RecallItem item, bool correct) onAnswer;
  final void Function(String topicId) onReview;

  /// A second opinion on an answer the word check missed (the server's AI);
  /// null, or a null result, keeps the word check's verdict.
  final Future<bool?> Function(RecallItem item, String said)? judge;

  /// The app's microphone and speaker; without it, typing only.
  final StudyVoice? voice;
  final int seconds;

  static const typingKey = 'study.recall.typing';
  static const mutedKey = 'study.recall.muted';

  @override
  State<LightningMobile> createState() => _LightningMobileState();
}

class _LightningMobileState extends State<LightningMobile> {
  /// The clock: the share of the question's time left, 1 → 0.
  final _left = ValueNotifier<double>(1);
  Timer? _tick;
  static const _step = Duration(milliseconds: 50);
  late Duration _remaining = Duration(seconds: widget.seconds);

  void _runClock() {
    _tick?.cancel();
    _tick = Timer.periodic(_step, (_) {
      _remaining -= _step;
      _left.value = (_remaining.inMilliseconds / (widget.seconds * 1000)).clamp(
        0.0,
        1.0,
      );
      if (_remaining <= Duration.zero) {
        _stopClock();
        if (_phase == _Phase.answering) unawaited(_grade(null));
      }
    });
  }

  void _stopClock() {
    _tick?.cancel();
    _tick = null;
  }

  void _resetClock() {
    _stopClock();
    _remaining = Duration(seconds: widget.seconds);
    _left.value = 1;
  }

  final _input = TextEditingController();
  final _focus = FocusNode();

  var _index = 0;
  var _phase = _Phase.reading;
  var _typing = false;
  var _muted = false;
  var _paused = false;
  var _holding = false;
  var _heard = '';
  String? _given;
  var _showHint = false;
  var _right = false;

  var _streak = 0;
  var _best = 0;
  var _answered = 0;
  var _correct = 0;
  final _missed = <String>{};

  StudyVoice? get _voice => widget.voice;
  RecallItem get _item => widget.items[_index];

  @override
  void initState() {
    super.initState();
    _typing = _voice == null;
    _input.addListener(() => setState(() {}));
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        if (_voice != null) {
          _typing = prefs.getBool(LightningMobile.typingKey) ?? false;
        }
        _muted = prefs.getBool(LightningMobile.mutedKey) ?? false;
      });
    } on Object {
      // Defaults.
    }
    _ask();
  }

  Future<void> _save(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } on Object {
      // This session only.
    }
  }

  @override
  void dispose() {
    _voice?.stop();
    _stopClock();
    _left.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Shows the current question, reads it, then starts the clock.
  Future<void> _ask() async {
    if (!mounted) return;
    final asked = _index;
    setState(() {
      _phase = _Phase.reading;
      _heard = '';
      _given = null;
      _showHint = false;
      _input.clear();
    });
    _resetClock();
    final voice = _voice;
    if (voice != null && !_muted) {
      if (_index + 1 < widget.items.length) {
        voice.warm(widget.items[_index + 1].question);
      }
      try {
        await voice.say(_item.question);
      } on Object {
        // Read or not, the question is on screen.
      }
    }
    if (!mounted || asked != _index || _phase != _Phase.reading) return;
    _start();
  }

  void _start() {
    setState(() => _phase = _Phase.answering);
    if (!_paused) _runClock();
    if (_typing) _focus.requestFocus();
  }

  var _checking = false;

  Future<void> _grade(String? said) async {
    if (_phase != _Phase.answering && _phase != _Phase.reading) return;
    if (_checking) return;
    _stopClock();
    _voice?.stop();
    var right = said != null && _item.matches(said);
    final judge = widget.judge;
    if (!right && judge != null && said != null && said.trim().isNotEmpty) {
      final asked = _index;
      setState(() => _checking = true);
      bool? verdict;
      try {
        verdict = await judge(_item, said).timeout(const Duration(seconds: 6));
      } on Object {
        verdict = null;
      }
      if (!mounted || asked != _index) return;
      _checking = false;
      right = verdict ?? false;
    }
    widget.onAnswer(_item, right);
    setState(() {
      _given = said;
      _right = right;
      _answered++;
      if (right) {
        _correct++;
        _streak++;
        _best = math.max(_best, _streak);
      } else {
        _streak = 0;
        _missed.add(_item.topicId);
      }
      _phase = _Phase.feedback;
    });
    if (right) {
      // Stronger as the streak grows.
      if (_streak >= 5) {
        unawaited(HapticFeedback.heavyImpact());
      } else if (_streak >= 3) {
        unawaited(HapticFeedback.mediumImpact());
      } else {
        SmHaptics.done();
      }
      Future<void>.delayed(const Duration(milliseconds: 850), () {
        if (mounted && _phase == _Phase.feedback && _given == said) _next();
      });
    } else {
      SmHaptics.error();
    }
  }

  void _skip() {
    if (_phase != _Phase.answering && _phase != _Phase.reading) return;
    SmHaptics.tap();
    _stopClock();
    _voice?.stop();
    setState(() => _streak = 0);
    _next();
  }

  void _next() {
    if (_index + 1 >= widget.items.length) {
      _voice?.stop();
      setState(() => _phase = _Phase.done);
      SmHaptics.done();
      return;
    }
    setState(() => _index++);
    unawaited(_ask());
  }

  void _togglePause() {
    SmHaptics.tap();
    setState(() => _paused = !_paused);
    if (_paused) {
      _stopClock();
      _voice?.stop();
    } else if (_phase == _Phase.answering) {
      _runClock();
    } else if (_phase == _Phase.reading) {
      _start();
    }
  }

  void _toggleTyping() {
    if (_voice == null) return;
    SmHaptics.select();
    setState(() => _typing = !_typing);
    unawaited(_save(LightningMobile.typingKey, _typing));
    if (_typing && _phase == _Phase.answering) {
      _focus.requestFocus();
    } else {
      _focus.unfocus();
    }
  }

  void _toggleMute() {
    SmHaptics.select();
    setState(() => _muted = !_muted);
    unawaited(_save(LightningMobile.mutedKey, _muted));
    if (_muted && _phase == _Phase.reading) {
      _voice?.stop();
      _start();
    }
  }

  Future<void> _holdStart() async {
    final voice = _voice;
    if (voice == null || _typing || _holding) return;
    if (_phase == _Phase.reading) {
      voice.stop();
      _start();
    }
    if (_phase != _Phase.answering) return;
    SmHaptics.select();
    setState(() {
      _holding = true;
      _heard = '';
    });
    _stopClock();
    String? said;
    try {
      said = await voice.listen(
        onPartial: (p) {
          if (mounted) setState(() => _heard = p);
        },
      );
    } on Object {
      said = null;
    }
    if (!mounted) return;
    final words = (said ?? _heard).trim();
    setState(() => _holding = false);
    if (_phase != _Phase.answering) return;
    if (words.isEmpty) {
      if (!_paused) _runClock();
      return;
    }
    unawaited(_grade(words));
  }

  void _holdEnd() {
    if (_holding) _voice?.finishListening();
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final total = widget.items.length;

    if (_phase == _Phase.done) {
      return Scaffold(
        backgroundColor: c.background,
        body: _Done(
          answered: _answered,
          correct: _correct,
          best: _best,
          weak: [for (final id in _missed) (id, widget.topicTitles[id] ?? '')],
          onReview: widget.onReview,
          onAgain: () {
            setState(() {
              _index = 0;
              _streak = 0;
              _best = 0;
              _answered = 0;
              _correct = 0;
              _missed.clear();
            });
            unawaited(_ask());
          },
          onClose: widget.onClose,
        ),
      );
    }

    final item = _item;
    final feedbackWrong = _phase == _Phase.feedback && !_right;
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
                  streak: _streak,
                  muted: _muted,
                  canSpeak: _voice != null,
                  paused: _paused,
                  onClose: widget.onClose,
                  onMute: _toggleMute,
                  onPause: _togglePause,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 6, 22, 0),
                  child: _Progress(
                    index: _index,
                    total: total,
                    streak: _streak,
                  ),
                ),
                // The question above, the clock in the middle, what was
                // said below.
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) => SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: box.maxHeight),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _Question(
                              key: ValueKey(_index),
                              text: item.question,
                              reading:
                                  _phase == _Phase.reading &&
                                  !_muted &&
                                  _voice != null,
                            ),
                            const SizedBox(height: 22),
                            _Clock(
                              left: _left,
                              seconds: widget.seconds,
                              typing: _typing,
                              holding: _holding,
                              right: _phase == _Phase.feedback && _right,
                              onHoldStart: _holdStart,
                              onHoldEnd: _holdEnd,
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              height: 64,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                ),
                                child: _Below(
                                  typing: _typing,
                                  input: _input,
                                  focus: _focus,
                                  heard: _heard,
                                  hint: _showHint ? item.hint : null,
                                  right: _phase == _Phase.feedback && _right
                                      ? item.answer
                                      : null,
                                  enabled:
                                      _phase == _Phase.answering ||
                                      _phase == _Phase.reading,
                                  onSubmit: () {
                                    final v = _input.text.trim();
                                    if (v.isNotEmpty) unawaited(_grade(v));
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + bottom),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _OutlinePill(
                          icon: Icons.lightbulb_outline_rounded,
                          label: 'Hint',
                          onTap: item.hint.isEmpty || _showHint
                              ? null
                              : () {
                                  SmHaptics.tap();
                                  setState(() => _showHint = true);
                                },
                        ),
                        if (_voice != null) ...[
                          const SizedBox(width: 10),
                          _OutlinePill(
                            icon: _typing
                                ? Icons.mic_none_rounded
                                : Icons.keyboard_outlined,
                            label: _typing ? 'Speak' : 'Type',
                            onTap: _toggleTyping,
                          ),
                        ],
                        const SizedBox(width: 10),
                        _OutlinePill(
                          icon: Icons.skip_next_rounded,
                          label: 'Skip',
                          onTap: _skip,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutBack,
            left: 12,
            right: 12,
            bottom: feedbackWrong ? 12 + bottom : -360,
            child: feedbackWrong
                ? _Missed(item: item, said: _given, onNext: _next)
                : const SizedBox.shrink(),
          ),
          if (_paused)
            Positioned.fill(
              child: _Paused(
                answered: _answered,
                correct: _correct,
                best: _best,
                onResume: _togglePause,
                onEnd: () {
                  setState(() {
                    _paused = false;
                    _phase = _Phase.done;
                  });
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.streak,
    required this.muted,
    required this.canSpeak,
    required this.paused,
    required this.onClose,
    required this.onMute,
    required this.onPause,
  });

  final int streak;
  final bool muted;
  final bool canSpeak;
  final bool paused;
  final VoidCallback onClose;
  final VoidCallback onMute;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    Widget icon(IconData i, String label, VoidCallback onTap, {Color? color}) =>
        SmPressable(
          semanticLabel: label,
          haptic: () {},
          scale: 0.88,
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(i, size: 21, color: color ?? c.text),
          ),
        );
    final hot = streak >= 3;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          icon(Icons.close_rounded, 'Close', onClose),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'Lightning recall',
              style: SmText.of(context).title.copyWith(fontSize: 14),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: hot ? _amber : c.line, width: 1.5),
              boxShadow: hot
                  ? [
                      BoxShadow(
                        color: _amber.withValues(alpha: 0.3),
                        blurRadius: 14,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.local_fire_department_rounded,
                  size: 15,
                  color: hot ? _amber : c.muted,
                ),
                const SizedBox(width: 3),
                Text(
                  '$streak',
                  style: TextStyle(
                    fontFamily: SmFonts.heading,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: hot ? const Color(0xFFF5C04A) : c.text,
                  ),
                ),
              ],
            ),
          ),
          if (canSpeak)
            icon(
              muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              muted ? 'Read questions aloud' : 'Mute',
              onMute,
              color: muted ? c.hint : c.text,
            ),
          icon(
            paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            paused ? 'Resume' : 'Pause',
            onPause,
          ),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({
    required this.index,
    required this.total,
    required this.streak,
  });

  final int index;
  final int total;
  final int streak;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final (flow, color) = switch (streak) {
      >= 5 => ('Excellent', const Color(0xFFF5C04A)),
      >= 2 => ('Warming up', const Color(0xFF5DCAA5)),
      _ => ('Getting started', c.hint),
    };
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(
            height: 4,
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: c.line)),
                TweenAnimationBuilder<double>(
                  tween: Tween(end: total == 0 ? 0 : index / total),
                  duration: const Duration(milliseconds: 300),
                  builder: (context, v, _) => FractionallySizedBox(
                    widthFactor: v,
                    child: ColoredBox(color: c.accent),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                'Question ${index + 1} of $total',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.small.copyWith(fontSize: 11.5),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(
                flow,
                key: ValueKey(flow),
                style: t.small.copyWith(fontSize: 11.5, color: color),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Question extends StatelessWidget {
  const _Question({super.key, required this.text, required this.reading});

  final String text;
  final bool reading;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    return SmAppear(
      index: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26),
        child: Column(
          children: [
            Text(
              text.trim(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: SmFonts.reading,
                fontSize: text.length > 90 ? 20 : 24,
                height: 1.36,
                color: c.text,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 16,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: reading ? 1 : 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.volume_up_rounded,
                      size: 13,
                      color: c.accentSoft,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'reading',
                      style: SmText.of(
                        context,
                      ).small.copyWith(color: c.accentSoft),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The seven-second ring around the mic (or, typing, around the seconds).
class _Clock extends StatelessWidget {
  const _Clock({
    required this.left,
    required this.seconds,
    required this.typing,
    required this.holding,
    required this.right,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  /// Share of the time left, 1 → 0.
  final ValueListenable<double> left;
  final int seconds;
  final bool typing;
  final bool holding;
  final bool right;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    return ValueListenableBuilder<double>(
      valueListenable: left,
      builder: (context, share, _) {
        final left = (seconds * share).ceil();
        final ringColor = Color.lerp(
          _amber,
          c.accent,
          ((0.4 - share) / 0.3).clamp(0.0, 1.0),
        )!;
        final face = right ? _green : c.accent;
        return SizedBox(
          width: 196,
          height: 196,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _Ring(value: share, track: c.line, color: ringColor),
                ),
              ),
              Listener(
                onPointerDown: typing ? null : (_) => onHoldStart(),
                onPointerUp: typing ? null : (_) => onHoldEnd(),
                onPointerCancel: typing ? null : (_) => onHoldEnd(),
                child: Semantics(
                  button: !typing,
                  label: typing ? '$left seconds' : 'Hold to answer',
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 160),
                    scale: holding ? 1.07 : 1,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      width: 122,
                      height: 122,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: typing ? c.raised : face,
                        boxShadow: typing
                            ? null
                            : [
                                BoxShadow(
                                  color: face.withValues(
                                    alpha: holding ? 0.55 : 0.3,
                                  ),
                                  blurRadius: holding ? 34 : 20,
                                ),
                              ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (!typing)
                            Icon(
                              right ? Icons.check_rounded : Icons.mic_rounded,
                              size: 40,
                              color: Colors.white,
                            ),
                          Text(
                            '$left',
                            style: TextStyle(
                              fontFamily: SmFonts.heading,
                              fontWeight: FontWeight.w800,
                              fontSize: typing ? 38 : 14,
                              color: typing ? c.text : Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Ring extends CustomPainter {
  _Ring({required this.value, required this.track, required this.color});

  final double value;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 8.0;
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
  bool shouldRepaint(_Ring old) =>
      old.value != value || old.color != color || old.track != track;
}

/// Under the clock: the typing pill, or what is being said, a hint, or the
/// right answer.
class _Below extends StatelessWidget {
  const _Below({
    required this.typing,
    required this.input,
    required this.focus,
    required this.heard,
    required this.hint,
    required this.right,
    required this.enabled,
    required this.onSubmit,
  });

  final bool typing;
  final TextEditingController input;
  final FocusNode focus;
  final String heard;
  final String? hint;
  final String? right;
  final bool enabled;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    if (right != null) {
      return Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, color: _green, size: 20),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                right!,
                style: const TextStyle(
                  fontFamily: SmFonts.heading,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: Color(0xFF5DCAA5),
                ),
              ),
            ),
          ],
        ),
      );
    }
    final hintLine = hint == null
        ? null
        : Text(
            '💡 $hint',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.small.copyWith(
              fontSize: 12.5,
              color: const Color(0xFFF5C04A),
            ),
          );
    if (typing) {
      final ready = input.text.trim().isNotEmpty && enabled;
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 4, 4, 4),
            decoration: BoxDecoration(
              color: c.raised,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    focusNode: focus,
                    enabled: enabled,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => onSubmit(),
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
                      hintText: 'Type the answer',
                      hintStyle: t.body.copyWith(fontSize: 16, color: c.hint),
                    ),
                  ),
                ),
                SmPressable(
                  semanticLabel: 'Check',
                  haptic: () {},
                  scale: 0.88,
                  onTap: ready ? onSubmit : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ready ? c.accent : c.line,
                    ),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 20,
                      color: ready ? Colors.white : c.hint,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (hintLine != null) ...[const SizedBox(height: 6), hintLine],
        ],
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (heard.isNotEmpty)
          Text(
            heard,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: SmFonts.reading,
              fontSize: 19,
              color: c.text.withValues(alpha: 0.85),
            ),
          )
        else
          hintLine ??
              Text(
                enabled ? 'Hold to answer' : '',
                style: t.small.copyWith(fontSize: 12.5, color: c.hint),
              ),
      ],
    );
  }
}

class _OutlinePill extends StatelessWidget {
  const _OutlinePill({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final on = onTap != null;
    return SmPressable(
      semanticLabel: label,
      haptic: () {},
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: on ? 1 : 0.4,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.line, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: c.muted),
              const SizedBox(width: 6),
              Text(label, style: t.body.copyWith(fontSize: 13, color: c.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wrong or out of time: the answer, why, Next.
class _Missed extends StatelessWidget {
  const _Missed({required this.item, required this.said, required this.onNext});

  final RecallItem item;
  final String? said;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = dark ? const Color(0xFFF2D4D5) : const Color(0xFF5C0D12);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF2E1517) : const Color(0xFFFCE9EA),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                said == null ? Icons.timer_off_outlined : Icons.cancel_rounded,
                color: c.accent,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                said == null ? 'Time’s up' : 'Not quite',
                style: TextStyle(
                  fontFamily: SmFonts.heading,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: c.accent,
                ),
              ),
            ],
          ),
          if (said != null) ...[
            const SizedBox(height: 6),
            Text(
              'You said “$said”',
              style: TextStyle(
                fontFamily: SmFonts.body,
                fontSize: 13,
                color: text.withValues(alpha: 0.75),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            item.answer,
            style: TextStyle(
              fontFamily: SmFonts.heading,
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: text,
            ),
          ),
          if (item.explanation.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 120),
              child: SingleChildScrollView(
                child: Text(
                  item.explanation.trim(),
                  style: TextStyle(
                    fontFamily: SmFonts.reading,
                    fontSize: 14.5,
                    height: 1.5,
                    color: text,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          SmPressable(
            semanticLabel: 'Next question',
            haptic: SmHaptics.tap,
            onTap: onNext,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: c.accent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Next question',
                    style: TextStyle(
                      fontFamily: SmFonts.heading,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 6),
                  Icon(
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

class _Paused extends StatelessWidget {
  const _Paused({
    required this.answered,
    required this.correct,
    required this.best,
    required this.onResume,
    required this.onEnd,
  });

  final int answered;
  final int correct;
  final int best;
  final VoidCallback onResume;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final acc = answered == 0 ? 0 : (correct / answered * 100).round();
    return ColoredBox(
      color: c.background.withValues(alpha: 0.94),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Paused', style: t.greeting.copyWith(fontSize: 24)),
            const SizedBox(height: 6),
            Text(
              '$answered answered · $acc% · best 🔥 $best',
              style: t.small.copyWith(fontSize: 13),
            ),
            const SizedBox(height: 22),
            SmPressable(
              semanticLabel: 'Resume',
              haptic: () {},
              onTap: onResume,
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 34),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Resume',
                  style: TextStyle(
                    fontFamily: SmFonts.heading,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SmPressable(
              semanticLabel: 'End session',
              haptic: SmHaptics.tap,
              onTap: onEnd,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'End session',
                  style: t.body.copyWith(color: c.muted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({
    required this.answered,
    required this.correct,
    required this.best,
    required this.weak,
    required this.onReview,
    required this.onAgain,
    required this.onClose,
  });

  final int answered;
  final int correct;
  final int best;
  final List<(String, String)> weak;
  final void Function(String topicId) onReview;
  final VoidCallback onAgain;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final acc = answered == 0 ? 0 : (correct / answered * 100).round();
    Widget stat(String value, String label) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: c.raised,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontFamily: SmFonts.heading,
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: c.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: t.small),
          ],
        ),
      ),
    );
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(
                children: [
                  const SmAppear(
                    index: 0,
                    child: Icon(Icons.bolt_rounded, size: 52, color: _amber),
                  ),
                  SmAppear(
                    index: 1,
                    child: Text(
                      'Session done',
                      style: t.greeting.copyWith(fontSize: 24),
                    ),
                  ),
                  const SizedBox(height: 22),
                  SmAppear(
                    index: 2,
                    child: Row(
                      children: [
                        stat('$answered', 'answered'),
                        const SizedBox(width: 8),
                        stat('$acc%', 'accuracy'),
                        const SizedBox(width: 8),
                        stat('🔥 $best', 'best streak'),
                      ],
                    ),
                  ),
                  if (weak.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    SmAppear(
                      index: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'WEAK TOPICS',
                            style: t.section.copyWith(fontSize: 11),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final (id, title) in weak)
                                SmPressable(
                                  semanticLabel: 'Review $title',
                                  onTap: () => onReview(id),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(99),
                                      border: Border.all(
                                        color: c.line,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Text(
                                      title,
                                      style: t.small.copyWith(
                                        fontSize: 12.5,
                                        color: c.text,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
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
              Expanded(
                child: SmPressable(
                  semanticLabel: 'Go again',
                  haptic: SmHaptics.thud,
                  onTap: onAgain,
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bolt_rounded, color: Colors.white, size: 19),
                        SizedBox(width: 6),
                        Text(
                          'Go again',
                          style: TextStyle(
                            fontFamily: SmFonts.heading,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SmPressable(
                semanticLabel: 'Finish',
                haptic: SmHaptics.tap,
                onTap: onClose,
                child: Container(
                  width: 50,
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
