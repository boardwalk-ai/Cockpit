import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../session/gw_session.dart';
import '../session/timeline.dart';
import 'mobile_cards.dart';
import 'mobile_composer.dart';
import 'mobile_details_sheet.dart';
import 'mobile_motion.dart';
import 'mobile_pills.dart';
import 'mobile_theme.dart';

/// Phone chat: the run's timeline (steps, questions, the word-count bar),
/// the Sources and Open Editor pills in the top-right corner, and the
/// composer docked at the bottom. The essay itself lives in the editor.
class GhostWriterMobileChat extends StatefulWidget {
  const GhostWriterMobileChat({
    super.key,
    required this.session,
    required this.composer,
    required this.onOpenEditor,
  });

  final GwSession session;
  final TextEditingController composer;
  final VoidCallback onOpenEditor;

  @override
  State<GhostWriterMobileChat> createState() => _GhostWriterMobileChatState();
}

class _GhostWriterMobileChatState extends State<GhostWriterMobileChat> {
  final ScrollController _scroll = ScrollController();

  GwSession get session => widget.session;
  RunTimeline get timeline => session.timeline;

  @override
  void initState() {
    super.initState();
    widget.composer.addListener(_rebuild);
    session.addListener(_onSession);
  }

  @override
  void didUpdateWidget(GhostWriterMobileChat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.composer != widget.composer) {
      oldWidget.composer.removeListener(_rebuild);
      widget.composer.addListener(_rebuild);
    }
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_onSession);
      widget.session.addListener(_onSession);
    }
  }

  void _rebuild() => setState(() {});

  void _onSession() {
    setState(() {});
    _followIfNearBottom();
  }

  /// Keeps new items in view, unless the user has scrolled up to read.
  void _followIfNearBottom() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.maxScrollExtent - position.pixels > 240) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd(3));
  }

  /// The list builds lazily, so its end is an estimate until the last items
  /// are laid out: scroll, look again, and finish the job.
  Future<void> _scrollToEnd(int tries) async {
    if (!mounted || !_scroll.hasClients || tries == 0) return;
    await _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.maxScrollExtent - position.pixels > 1) {
      await _scrollToEnd(tries - 1);
    }
  }

  @override
  void dispose() {
    widget.composer.removeListener(_rebuild);
    session.removeListener(_onSession);
    _scroll.dispose();
    super.dispose();
  }

  /// The citation style, once it has been answered.
  String? get _citationStyle {
    for (final item in timeline.items) {
      if (item is QuestionItem &&
          item.field == 'citationStyle' &&
          item.answered) {
        return item.answer?.toString();
      }
    }
    return null;
  }

  void _openSources() {
    showGwDetailsSheet(
      context,
      title: session.title,
      finished: timeline.phase == RunPhase.finished,
      citationStyle: _citationStyle ?? '—',
      wordCount: timeline.writing?.words ?? 0,
      sources: timeline.sources ?? const [],
      bibliography: '',
    );
  }

  void _send() {
    final text = widget.composer.text.trim();
    if (text.isEmpty) return;
    widget.composer.clear();
    session.send(text);
  }

  String get _hint {
    final pending = timeline.pending;
    if (timeline.ended) return 'Revisions are coming soon';
    if (pending != null &&
        (pending.inputType == 'text' || pending.inputType == 'number')) {
      return 'Type your answer';
    }
    if (pending?.field == 'essayFocus') return 'Or describe the angle you want';
    if (timeline.awaitingReply) return 'Reply to GhostWriter';
    return 'Steer the draft';
  }

  @override
  Widget build(BuildContext context) {
    final ended = timeline.ended;
    final canType = !ended && session.runId != null && !session.starting;
    final writing = timeline.writing;

    return Column(
      children: [
        _ThreadStrip(
          title: session.title.isEmpty ? 'New essay' : session.title,
          phase: timeline.phase,
          starting: session.starting,
          citationStyle: _citationStyle,
          words: writing?.words ?? 0,
          onStop: canType ? session.cancel : null,
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 18),
                      children: _items(),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 2,
                right: 12,
                child: GwCornerPills(
                  sourceCount: timeline.sources == null
                      ? null
                      : timeline.sourceCount,
                  onSources: _openSources,
                  showEditor: writing != null,
                  writing: writing != null && !writing.done && !ended,
                  onEditor: widget.onOpenEditor,
                ),
              ),
              if (session.reconnecting)
                const Positioned(
                  top: 6,
                  left: 0,
                  right: 0,
                  child: Center(child: _ReconnectingBadge()),
                ),
            ],
          ),
        ),
        GwComposer(
          controller: widget.composer,
          canSend: canType && widget.composer.text.trim().isNotEmpty,
          onChanged: (_) {},
          onSend: _send,
          sendLabel: 'Send',
          hintText: _hint,
        ),
      ],
    );
  }

  List<Widget> _items() {
    final widgets = <Widget>[];
    for (final (index, item) in timeline.items.indexed) {
      final Widget child = switch (item) {
        UserItem(:final text) => _UserBubble(text: text),
        AssistantItem(:final text, :final streaming) => _AssistantBubble(
          text: text,
          streaming: streaming,
        ),
        StepItem() => GwStepCard(step: item),
        QuestionItem() => GwQuestionCard(
          question: item,
          active: identical(item, timeline.pending) && !timeline.ended,
          onAnswer: (value) => session.answer(item.field, value),
        ),
        WritingItem() => GwWritingCard(
          writing: item,
          onOpenEditor: widget.onOpenEditor,
        ),
        EndItem() => GwEndCard(end: item, onOpenEditor: widget.onOpenEditor),
      };
      widgets.add(GwAppear(key: ValueKey('item-$index'), child: child));
    }

    if (_thinking) {
      widgets.add(
        const GwAppear(key: ValueKey('typing'), child: _TypingBubble()),
      );
    }
    if (session.actionError case final error?) {
      widgets.add(
        GwAppear(
          key: ValueKey('error-$error'),
          child: _ErrorCard(message: error, onRetry: session.retry),
        ),
      );
    }
    return widgets;
  }

  /// GhostWriter is busy with something that has no card of its own yet.
  bool get _thinking {
    if (session.actionError != null) return false;
    if (session.starting) return true;
    if (session.runId == null) return false;
    if (timeline.ended || timeline.phase == RunPhase.waiting) return false;
    final items = timeline.items;
    if (items.isEmpty) return true;
    return switch (items.last) {
      AssistantItem(:final streaming) => !streaming,
      StepItem(:final status) => status != StepStatus.running,
      WritingItem(:final done) => done,
      _ => true,
    };
  }
}

class _ThreadStrip extends StatelessWidget {
  const _ThreadStrip({
    required this.title,
    required this.phase,
    required this.starting,
    required this.citationStyle,
    required this.words,
    required this.onStop,
  });

  final String title;
  final RunPhase phase;
  final bool starting;
  final String? citationStyle;
  final int words;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final (label, color, pulse) = starting
        ? ('Starting', GwColors.gold, true)
        : switch (phase) {
            RunPhase.running => ('Working', GwColors.gold, true),
            RunPhase.waiting => ('Your turn', GwColors.accentSoft, true),
            RunPhase.finished => ('Finished', const Color(0xFF3DDC84), false),
            RunPhase.cancelled => ('Stopped', GwColors.muted, false),
            RunPhase.failed => ('Failed', const Color(0xFFFF777D), false),
          };

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 18, right: 12),
            child: SizedBox(
              height: 36,
              child: Row(
                children: [
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.centerLeft,
                        children: [...previous, ?current],
                      ),
                      child: Text(
                        title,
                        key: ValueKey(title),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ),
                  if (onStop != null) ...[
                    const SizedBox(width: 8),
                    GwPressable(
                      tooltip: 'Stop',
                      haptic: GwHaptic.medium,
                      onTap: onStop,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF2A1416),
                          border: Border.all(color: const Color(0xFF7A2D31)),
                        ),
                        child: const Icon(
                          Icons.stop_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                _StatusChip(label: label, color: color, pulse: pulse),
                if (citationStyle case final style?) ...[
                  const SizedBox(width: 6),
                  _Chip(icon: Icons.format_quote_rounded, label: style),
                ],
                if (words > 0) ...[
                  const SizedBox(width: 6),
                  _Chip(icon: Icons.notes_rounded, label: '$words words'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: const Color(0xCC181919),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: GwColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: GwColors.muted),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFD7D7D9),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The run's state, with a dot that pulses while something is going on.
class _StatusChip extends StatefulWidget {
  const _StatusChip({
    required this.label,
    required this.color,
    required this.pulse,
  });

  final String label;
  final Color color;
  final bool pulse;

  @override
  State<_StatusChip> createState() => _StatusChipState();
}

class _StatusChipState extends State<_StatusChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_StatusChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final animate = widget.pulse && !MediaQuery.disableAnimationsOf(context);
    if (animate && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!animate) {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              final glow = widget.pulse ? _pulse.value : 0.0;
              return Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.7 * glow),
                      blurRadius: 8 * glow,
                      spreadRadius: 2 * glow,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 7),
          Text(
            widget.label,
            style: TextStyle(
              color: color,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReconnectingBadge extends StatelessWidget {
  const _ReconnectingBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xE6181919),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x26FFFFFF)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: GwColors.muted,
            ),
          ),
          SizedBox(width: 8),
          Text(
            'Reconnecting…',
            style: TextStyle(
              color: GwColors.muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Plays a fade-and-rise once, when the item first appears in the list.
class GwAppear extends StatefulWidget {
  const GwAppear({super.key, required this.child, this.delay = 0});

  final Widget child;

  /// Fraction of the animation to wait before starting (0..0.8).
  final double delay;

  @override
  State<GwAppear> createState() => _GwAppearState();
}

class _GwAppearState extends State<GwAppear>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (460 * (1 + widget.delay * 2)).round()),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (_controller.status == AnimationStatus.dismissed) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.delay * 2 / (1 + widget.delay * 2);

    return GwReveal(
      animation: _controller,
      from: start,
      to: 1,
      offset: const Offset(0, 16),
      child: widget.child,
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: FractionallySizedBox(
        widthFactor: 0.84,
        alignment: Alignment.centerRight,
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFF4A4F), Color(0xFFD9202A)],
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(6),
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x33FF343C),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Text(
              text,
              style: kGwBody.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.text, required this.streaming});

  final String text;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    // GhostWriter speaks in plain text beside its avatar, no bubble.
    return GwAssistantRow(
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text.rich(
          TextSpan(
            text: text,
            children: [
              if (streaming)
                const WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: _Caret(),
                ),
            ],
          ),
          style: kGwBody,
        ),
      ),
    );
  }
}

/// Blinking red cursor at the end of text that is still streaming in.
class _Caret extends StatefulWidget {
  const _Caret();

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _blink.value = 1;
    } else if (!_blink.isAnimating) {
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
    return FadeTransition(
      opacity: _blink,
      child: Container(
        width: 8,
        height: 17,
        margin: const EdgeInsets.only(left: 3),
        decoration: BoxDecoration(
          color: GwColors.accent,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// Three dots bouncing in turn while GhostWriter is busy.
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _bounce.stop();
    } else if (!_bounce.isAnimating) {
      _bounce.repeat();
    }
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'GhostWriter is writing',
      child: GwAssistantRow(
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: AnimatedBuilder(
              animation: _bounce,
              builder: (context, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var dot = 0; dot < 3; dot++)
                      Padding(
                        padding: EdgeInsets.only(left: dot == 0 ? 0 : 5),
                        child: _dot(dot),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _dot(int index) {
    // Each dot lifts a little after the one before it.
    final phase = (_bounce.value - index * 0.16) % 1.0;
    final lift = phase < 0.4 ? math.sin(phase / 0.4 * math.pi) : 0.0;

    return Transform.translate(
      offset: Offset(0, -5 * lift),
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color.lerp(GwColors.muted, GwColors.accentSoft, lift),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 0, 12),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 19,
            color: Color(0xFFFF777D),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: kGwBody.copyWith(
                color: const Color(0xFFFF9A9E),
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GwPressable(
            onTap: onRetry,
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0x33FF4B52),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh_rounded, size: 16, color: Colors.white),
                  SizedBox(width: 5),
                  Text(
                    'Retry',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
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
