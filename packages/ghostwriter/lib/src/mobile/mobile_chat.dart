import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mobile_composer.dart';
import 'mobile_details_sheet.dart';
import 'mobile_motion.dart';
import 'mobile_theme.dart';

/// Phone main page: the conversation while GhostWriter drafts, then the
/// finished essay, with the composer docked at the bottom.
class GhostWriterMobileChat extends StatefulWidget {
  const GhostWriterMobileChat({
    super.key,
    required this.finished,
    required this.title,
    required this.citationStyle,
    required this.wordCount,
    required this.messages,
    required this.assistantText,
    required this.essay,
    required this.bibliography,
    required this.sources,
    required this.onRetry,
    required this.composerController,
    required this.onSend,
    this.pendingQuestion,
    this.errorMessage,
  });

  final bool finished;
  final String title;
  final String citationStyle;
  final int wordCount;

  /// What the user has sent in this run, oldest first.
  final List<String> messages;

  /// GhostWriter's reply so far; grows while it streams.
  final String assistantText;

  final String essay;
  final String bibliography;
  final List<Map<String, dynamic>> sources;

  final String? pendingQuestion;
  final String? errorMessage;
  final VoidCallback onRetry;

  final TextEditingController composerController;
  final VoidCallback onSend;

  @override
  State<GhostWriterMobileChat> createState() => _GhostWriterMobileChatState();
}

class _GhostWriterMobileChatState extends State<GhostWriterMobileChat> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.composerController.addListener(_onComposerChanged);
  }

  void _onComposerChanged() => setState(() {});

  @override
  void didUpdateWidget(GhostWriterMobileChat oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.composerController != widget.composerController) {
      oldWidget.composerController.removeListener(_onComposerChanged);
      widget.composerController.addListener(_onComposerChanged);
    }

    if (widget.finished && !oldWidget.finished) {
      // Start reading the finished essay from the top.
      _afterLayout(() => _scroll.jumpTo(0));
    } else if (widget.assistantText != oldWidget.assistantText ||
        widget.messages.length != oldWidget.messages.length ||
        widget.pendingQuestion != oldWidget.pendingQuestion ||
        widget.errorMessage != oldWidget.errorMessage) {
      _followIfNearBottom();
    }
  }

  void _afterLayout(VoidCallback action) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) action();
    });
  }

  /// Keeps new text in view, unless the user has scrolled up to read.
  void _followIfNearBottom() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.maxScrollExtent - position.pixels > 220) return;

    _afterLayout(() => _scroll.jumpTo(_scroll.position.maxScrollExtent));
  }

  @override
  void dispose() {
    widget.composerController.removeListener(_onComposerChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _openDetails() {
    gwHaptic(GwHaptic.light);
    showGwDetailsSheet(
      context,
      title: widget.title,
      finished: widget.finished,
      citationStyle: widget.citationStyle,
      wordCount: widget.wordCount,
      sources: widget.sources,
      bibliography: widget.bibliography,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ThreadStrip(
          title: widget.title,
          finished: widget.finished,
          citationStyle: widget.citationStyle,
          wordCount: widget.wordCount,
          sourceCount: widget.sources.length,
          onDetails: _openDetails,
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 18),
                children: widget.finished ? _finishedItems() : _draftingItems(),
              ),
            ),
          ),
        ),
        GwComposer(
          controller: widget.composerController,
          canSend: widget.composerController.text.trim().isNotEmpty,
          onChanged: (_) {},
          onSend: widget.onSend,
          sendLabel: 'Send',
          hintText:
              widget.pendingQuestion ??
              (widget.finished ? 'Ask about your essay' : 'Steer the draft'),
        ),
      ],
    );
  }

  List<Widget> _draftingItems() {
    final waiting =
        widget.assistantText.isEmpty &&
        widget.pendingQuestion == null &&
        widget.errorMessage == null;

    return [
      for (final (index, message) in widget.messages.indexed)
        GwAppear(
          key: ValueKey('user-$index'),
          child: _UserBubble(text: message),
        ),
      if (waiting)
        const GwAppear(key: ValueKey('typing'), child: _TypingBubble()),
      if (widget.assistantText.isNotEmpty)
        GwAppear(
          key: const ValueKey('assistant'),
          child: _AssistantBubble(
            text: widget.assistantText,
            streaming:
                widget.pendingQuestion == null && widget.errorMessage == null,
          ),
        ),
      if (widget.pendingQuestion case final question?)
        GwAppear(
          key: ValueKey('question-$question'),
          child: _QuestionCard(question: question),
        ),
      if (widget.errorMessage case final error?)
        GwAppear(
          key: ValueKey('error-$error'),
          child: _ErrorCard(message: error, onRetry: widget.onRetry),
        ),
    ];
  }

  List<Widget> _finishedItems() {
    return [
      GwAppear(
        key: const ValueKey('prompt'),
        child: _UserBubble(text: widget.title),
      ),
      const GwAppear(key: ValueKey('done'), delay: 0.15, child: _DoneBanner()),
      GwAppear(
        key: const ValueKey('essay'),
        delay: 0.3,
        child: _DocumentCard(
          label: 'Final essay',
          text: widget.essay.isEmpty
              ? 'No essay content was returned by the backend.'
              : widget.essay,
          fontSize: 15,
        ),
      ),
      if (widget.bibliography.isNotEmpty)
        GwAppear(
          key: const ValueKey('references'),
          delay: 0.45,
          child: _DocumentCard(
            label: 'References',
            text: widget.bibliography,
            fontSize: 13.5,
          ),
        ),
      const GwAppear(key: ValueKey('editor'), delay: 0.6, child: _EditorCard()),
    ];
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

class _ThreadStrip extends StatelessWidget {
  const _ThreadStrip({
    required this.title,
    required this.finished,
    required this.citationStyle,
    required this.wordCount,
    required this.sourceCount,
    required this.onDetails,
  });

  final String title;
  final bool finished;
  final String citationStyle;
  final int wordCount;
  final int sourceCount;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 18, right: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
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
                const SizedBox(width: 8),
                GwPressable(
                  tooltip: 'Details',
                  onTap: onDetails,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF2A1416),
                      border: Border.all(color: const Color(0xFF7A2D31)),
                    ),
                    child: const Icon(
                      Icons.tune_rounded,
                      size: 19,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                _StatusChip(finished: finished),
                const SizedBox(width: 6),
                _Chip(icon: Icons.format_quote_rounded, label: citationStyle),
                if (wordCount > 0) ...[
                  const SizedBox(width: 6),
                  _Chip(icon: Icons.notes_rounded, label: '$wordCount words'),
                ],
                if (sourceCount > 0) ...[
                  const SizedBox(width: 6),
                  _Chip(
                    icon: Icons.menu_book_rounded,
                    label: sourceCount == 1
                        ? '1 source'
                        : '$sourceCount sources',
                  ),
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

/// "Writing" with a pulsing gold dot, or "Finished" with a green one.
class _StatusChip extends StatefulWidget {
  const _StatusChip({required this.finished});

  final bool finished;

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
    final animate =
        !widget.finished && !MediaQuery.disableAnimationsOf(context);
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
    final color = widget.finished ? const Color(0xFF3DDC84) : GwColors.gold;

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
              final glow = widget.finished ? 0.0 : _pulse.value;

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
            widget.finished ? 'Finished' : 'Writing',
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

const _bodyStyle = TextStyle(
  color: Color(0xFFE6E6E8),
  fontFamily: GwFonts.secondary,
  fontFamilyFallback: GwFonts.secondaryFallback,
  fontSize: 15,
  height: 1.55,
);

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
              style: _bodyStyle.copyWith(
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

/// Ghost avatar on the left with GhostWriter's content beside it.
class _AssistantRow extends StatelessWidget {
  const _AssistantRow({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xCC181919),
            ),
            child: Image.asset(GwAssets.ghost),
          ),
          const SizedBox(width: 8),
          Flexible(child: child),
        ],
      ),
    );
  }
}

const _assistantBubble = BoxDecoration(
  color: Color(0xE6181919),
  borderRadius: BorderRadius.only(
    topLeft: Radius.circular(6),
    topRight: Radius.circular(20),
    bottomLeft: Radius.circular(20),
    bottomRight: Radius.circular(20),
  ),
  border: Border.fromBorderSide(BorderSide(color: Color(0x1AFFFFFF))),
);

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.text, required this.streaming});

  final String text;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    return _AssistantRow(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: _assistantBubble,
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
          style: _bodyStyle,
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

/// Three dots bouncing in turn while GhostWriter has not replied yet.
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
      child: _AssistantRow(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: _assistantBubble,
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

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.question});

  final String question;

  @override
  Widget build(BuildContext context) {
    return _AssistantRow(
      child: Container(
        padding: const EdgeInsets.fromLTRB(15, 12, 15, 13),
        decoration: BoxDecoration(
          color: const Color(0xF02A1416),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF7A2D31)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.help_outline_rounded,
                  size: 15,
                  color: Color(0xFFFF777D),
                ),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'GhostWriter needs your input',
                    style: TextStyle(
                      color: Color(0xFFFF777D),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(question, style: _bodyStyle.copyWith(color: Colors.white)),
            const SizedBox(height: 7),
            Text(
              'Answer below and press send.',
              style: _bodyStyle.copyWith(color: GwColors.muted, fontSize: 12),
            ),
          ],
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: const Color(0xF0251013),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF4B52)),
      ),
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
              style: _bodyStyle.copyWith(
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

class _DoneBanner extends StatelessWidget {
  const _DoneBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 12),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: Color(0xFF3DDC84),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Your GhostWriter draft is complete.',
              style: _bodyStyle.copyWith(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

/// Essay or reference list in a card, with a button to copy the text.
class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.label,
    required this.text,
    required this.fontSize,
  });

  final String label;
  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xF0181919),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 6, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    style: const TextStyle(
                      color: GwColors.hint,
                      fontSize: 11,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _CopyButton(label: label, text: text),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SelectableText(
              text,
              style: _bodyStyle.copyWith(fontSize: fontSize, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// Copies [text]; the icon turns into a tick for a moment afterwards.
class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.label, required this.text});

  final String label;
  final String text;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton>
    with SingleTickerProviderStateMixin {
  /// Runs while the tick is showing.
  late final AnimationController _copied =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1600),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _copied.reset();
        setState(() {});
      });

  @override
  void dispose() {
    _copied.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = _copied.isAnimating;

    return GwPressable(
      tooltip: 'Copy ${widget.label.toLowerCase()}',
      onTap: () {
        Clipboard.setData(ClipboardData(text: widget.text));
        _copied.forward(from: 0);
      },
      child: SizedBox(
        width: kGwButton,
        height: kGwButton,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) =>
              ScaleTransition(scale: animation, child: child),
          child: Icon(
            done ? Icons.check_rounded : Icons.copy_rounded,
            key: ValueKey(done),
            size: 18,
            color: done ? const Color(0xFF3DDC84) : GwColors.muted,
          ),
        ),
      ),
    );
  }
}

class _EditorCard extends StatelessWidget {
  const _EditorCard();

  @override
  Widget build(BuildContext context) {
    // TODO: open the editor once it exists on mobile.
    return GwPressable(
      pressedScale: 0.97,
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
        decoration: BoxDecoration(
          color: const Color(0xF0181919),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF7A2D31)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF2A1416),
              ),
              child: const Icon(
                Icons.edit_note_rounded,
                color: GwColors.accentSoft,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Proceed to Editor',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Review and refine your essay',
                    style: _bodyStyle.copyWith(
                      color: GwColors.muted,
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_rounded,
              color: Colors.white70,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
