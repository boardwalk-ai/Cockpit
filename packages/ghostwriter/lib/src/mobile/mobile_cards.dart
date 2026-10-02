import 'package:flutter/material.dart';

import '../session/timeline.dart';
import 'mobile_motion.dart';
import 'mobile_theme.dart';

/// Ghost avatar on the left with GhostWriter's content beside it.
class GwAssistantRow extends StatelessWidget {
  const GwAssistantRow({super.key, required this.child, this.avatar = true});

  final Widget child;

  /// False keeps the indent without the avatar, for a card that continues
  /// the message above it.
  final bool avatar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 30,
            height: 30,
            child: avatar
                ? Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xCC181919),
                    ),
                    child: Image.asset(GwAssets.ghost),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ── Steps ──────────────────────────────────────────────────────────────────

/// One tool the agent ran: a plain line whose spinner turns into a tick (or
/// a cross). Tap to see what it did along the way.
class GwStepCard extends StatefulWidget {
  const GwStepCard({super.key, required this.step});

  final StepItem step;

  @override
  State<GwStepCard> createState() => _GwStepCardState();
}

class _GwStepCardState extends State<GwStepCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    final lines = [...step.details, ...step.thoughts];
    final subtitle = switch (step.status) {
      StepStatus.running => step.details.isEmpty ? null : step.details.last,
      StepStatus.done => step.summary,
      StepStatus.failed => step.error ?? 'This step failed.',
      StepStatus.stopped => 'Stopped.',
    };

    return GwAssistantRow(
      avatar: false,
      child: GwPressable(
        haptic: GwHaptic.selection,
        pressedScale: 0.98,
        onTap: lines.isEmpty ? null : () => setState(() => _open = !_open),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _StepIcon(status: step.status),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.title.isEmpty ? step.tool : step.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (subtitle != null && subtitle.isNotEmpty)
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: Text(
                                subtitle,
                                key: ValueKey(subtitle),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: kGwBody.copyWith(
                                  fontSize: 12.5,
                                  height: 1.35,
                                  color: step.status == StepStatus.failed
                                      ? const Color(0xFFFF9A9E)
                                      : GwColors.muted,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (lines.isNotEmpty)
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 220),
                        child: const Icon(
                          Icons.expand_more_rounded,
                          size: 18,
                          color: GwColors.hint,
                        ),
                      ),
                  ],
                ),
                if (_open)
                  Padding(
                    padding: const EdgeInsets.only(left: 28, top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final line in lines)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              line,
                              style: kGwBody.copyWith(
                                fontSize: 12.5,
                                height: 1.4,
                                color: const Color(0xFFBDBEC1),
                              ),
                            ),
                          ),
                      ],
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

class _StepIcon extends StatelessWidget {
  const _StepIcon({required this.status});

  final StepStatus status;

  @override
  Widget build(BuildContext context) {
    final Widget icon = switch (status) {
      StepStatus.running => const SizedBox(
        key: ValueKey('running'),
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: GwColors.accentSoft,
        ),
      ),
      StepStatus.done => const Icon(
        Icons.check_circle_rounded,
        key: ValueKey('done'),
        size: 18,
        color: Color(0xFF3DDC84),
      ),
      StepStatus.failed => const Icon(
        Icons.cancel_rounded,
        key: ValueKey('failed'),
        size: 18,
        color: Color(0xFFFF777D),
      ),
      StepStatus.stopped => const Icon(
        Icons.pause_circle_rounded,
        key: ValueKey('stopped'),
        size: 18,
        color: GwColors.hint,
      ),
    };
    return SizedBox(
      width: 18,
      height: 18,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          transitionBuilder: (child, animation) =>
              ScaleTransition(scale: animation, child: child),
          child: icon,
        ),
      ),
    );
  }
}

// ── Writing progress ───────────────────────────────────────────────────────

/// `320 / 800 words`, with a bar that fills as the essay is written. The essay
/// itself is in the editor, not the chat.
class GwWritingCard extends StatelessWidget {
  const GwWritingCard({super.key, required this.writing, this.onOpenEditor});

  final WritingItem writing;
  final VoidCallback? onOpenEditor;

  @override
  Widget build(BuildContext context) {
    final target = writing.targetWords;
    final fraction = target <= 0
        ? (writing.done ? 1.0 : 0.0)
        : (writing.words / target).clamp(0.0, 1.0);
    final done = writing.done;

    return GwAssistantRow(
      avatar: false,
      child: GwPressable(
        pressedScale: 0.98,
        onTap: onOpenEditor,
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    done ? Icons.task_alt_rounded : Icons.edit_note_rounded,
                    size: 18,
                    color: done ? const Color(0xFF3DDC84) : GwColors.accentSoft,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      done ? 'Essay written' : 'Writing your essay',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _CountingWords(words: writing.words, target: target),
                ],
              ),
              const SizedBox(height: 10),
              _ProgressBar(fraction: fraction, active: !done),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountingWords extends StatelessWidget {
  const _CountingWords({required this.words, required this.target});

  final int words;
  final int target;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: words.toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => Text(
        target > 0
            ? '${value.round()} / $target words'
            : '${value.round()} words',
        style: const TextStyle(
          color: GwColors.muted,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// A rounded bar that eases to [fraction], with a light sweeping across it
/// while [active].
class _ProgressBar extends StatefulWidget {
  const _ProgressBar({required this.fraction, required this.active});

  final double fraction;
  final bool active;

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_ProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final animate = widget.active && !MediaQuery.disableAnimationsOf(context);
    if (animate && !_sweep.isAnimating) {
      _sweep.repeat();
    } else if (!animate && _sweep.isAnimating) {
      _sweep.stop();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 7,
        color: const Color(0x1AFFFFFF),
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: widget.fraction),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => FractionallySizedBox(
            widthFactor: value,
            child: AnimatedBuilder(
              animation: _sweep,
              builder: (context, _) {
                final x = -1.5 + 3 * _sweep.value;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: widget.active
                          ? const [Color(0xFFFF4A4F), Color(0xFFFF8A65)]
                          : const [Color(0xFF2FBF71), Color(0xFF3DDC84)],
                    ),
                  ),
                  child: widget.active
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment(x - 0.5, 0),
                              end: Alignment(x + 0.5, 0),
                              colors: const [
                                Color(0x00FFFFFF),
                                Color(0x55FFFFFF),
                                Color(0x00FFFFFF),
                              ],
                            ),
                          ),
                        )
                      : null,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── Questions ──────────────────────────────────────────────────────────────

/// A question from GhostWriter, with the control its `inputType` calls for.
/// Once answered it folds down to the question and the answer.
class GwQuestionCard extends StatefulWidget {
  const GwQuestionCard({
    super.key,
    required this.question,
    required this.active,
    required this.onAnswer,
  });

  final QuestionItem question;

  /// Pending and answerable now (not an old question from a finished run).
  final bool active;
  final Future<void> Function(Object value) onAnswer;

  @override
  State<GwQuestionCard> createState() => _GwQuestionCardState();
}

class _GwQuestionCardState extends State<GwQuestionCard> {
  final Set<String> _picked = {};
  final List<QuestionOption> _custom = [];
  final TextEditingController _text = TextEditingController();
  bool _sending = false;

  QuestionItem get q => widget.question;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send(Object value) async {
    if (_sending) return;
    setState(() => _sending = true);
    gwHaptic(GwHaptic.medium);
    try {
      await widget.onAnswer(value);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _sendText() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    if (q.inputType == 'number') {
      final n = num.tryParse(text.replaceAll(',', ''));
      if (n == null) return;
      _send(n);
    } else {
      _send(text);
    }
  }

  void _addCustom() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _custom.add(QuestionOption(text, text));
      _picked.add(text);
      _text.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final answered = q.answered;
    // The one card in the chat: a question waiting for the user.
    final open = !answered && widget.active;

    return GwAssistantRow(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        padding: open
            ? const EdgeInsets.fromLTRB(15, 12, 15, 13)
            : const EdgeInsets.only(top: 4, bottom: 2),
        decoration: BoxDecoration(
          color: open ? const Color(0xF02A1416) : const Color(0x002A1416),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: open ? const Color(0xFF7A2D31) : const Color(0x007A2D31),
          ),
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!answered && widget.active) ...[
                const Row(
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
              ],
              Text(
                q.question,
                style: kGwBody.copyWith(
                  color: answered ? GwColors.muted : Colors.white,
                  fontSize: answered ? 13.5 : 15,
                  height: 1.45,
                ),
              ),
              if (answered) ...[
                const SizedBox(height: 8),
                _AnswerChips(answer: q.answer, options: q.options),
              ] else if (widget.active) ...[
                const SizedBox(height: 11),
                AbsorbPointer(
                  absorbing: _sending,
                  child: AnimatedOpacity(
                    opacity: _sending ? 0.5 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: _controls(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _controls() {
    switch (q.inputType) {
      case 'select':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ChipWrap(
              children: [
                for (final o in q.options)
                  GwChoiceChip(label: o.label, onTap: () => _send(o.value)),
              ],
            ),
            if (q.allowCustom) ...[
              const SizedBox(height: 10),
              _InlineField(
                controller: _text,
                hint: 'Something else',
                onSubmit: _sendText,
              ),
            ],
          ],
        );

      case 'multiselect':
        final options = [...q.options, ..._custom];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ChipWrap(
              children: [
                for (final o in options)
                  GwChoiceChip(
                    label: o.label,
                    selected: _picked.contains(o.value),
                    checkbox: true,
                    onTap: () => setState(() {
                      if (!_picked.remove(o.value)) _picked.add(o.value);
                    }),
                  ),
                GwChoiceChip(
                  label: 'Suggest more',
                  icon: Icons.auto_awesome_rounded,
                  onTap: () => _send('__suggest_more__'),
                ),
              ],
            ),
            if (q.allowCustom) ...[
              const SizedBox(height: 10),
              _InlineField(
                controller: _text,
                hint: 'Add your own angle',
                icon: Icons.add_rounded,
                onSubmit: _addCustom,
              ),
            ],
            const SizedBox(height: 12),
            _ConfirmButton(
              label: _picked.isEmpty
                  ? 'Pick at least one'
                  : 'Continue with ${_picked.length}',
              onTap: _picked.isEmpty
                  ? null
                  : () => _send([
                      for (final o in options)
                        if (_picked.contains(o.value)) o.value,
                    ]),
            ),
          ],
        );

      case 'number':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (q.suggestions.isNotEmpty)
              _ChipWrap(
                children: [
                  for (final s in q.suggestions)
                    GwChoiceChip(
                      label: s,
                      onTap: () => _send(num.tryParse(s) ?? s),
                    ),
                ],
              ),
            if (q.allowCustom || q.suggestions.isEmpty) ...[
              const SizedBox(height: 10),
              _InlineField(
                controller: _text,
                hint: 'Or type a number',
                number: true,
                onSubmit: _sendText,
              ),
            ],
          ],
        );

      case 'sourceReview':
        return _ConfirmButton(
          label: 'Use all ${q.sources.length} sources',
          onTap: () => _send([
            for (final s in q.sources) {'url': s['url']},
          ]),
        );

      default:
        return _InlineField(
          controller: _text,
          hint: 'Type your answer',
          onSubmit: _sendText,
        );
    }
  }
}

class _ChipWrap extends StatelessWidget {
  const _ChipWrap({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 7, runSpacing: 7, children: children);
}

/// A rounded choice; with [checkbox] it toggles a tick.
class GwChoiceChip extends StatelessWidget {
  const GwChoiceChip({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.checkbox = false,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool checkbox;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final leading = checkbox
        ? (selected
              ? Icons.check_box_rounded
              : Icons.check_box_outline_blank_rounded)
        : icon;

    return GwPressable(
      haptic: GwHaptic.selection,
      pressedScale: 0.94,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        constraints: const BoxConstraints(minHeight: 38),
        padding: EdgeInsets.fromLTRB(leading == null ? 14 : 10, 8, 14, 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0x33FF343C) : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFFFF5258) : const Color(0x26FFFFFF),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[
              Icon(
                leading,
                size: 17,
                color: selected ? GwColors.accentSoft : GwColors.muted,
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFFD7D7D9),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineField extends StatelessWidget {
  const _InlineField({
    required this.controller,
    required this.hint,
    required this.onSubmit,
    this.icon = Icons.arrow_upward_rounded,
    this.number = false,
  });

  final TextEditingController controller;
  final String hint;
  final VoidCallback onSubmit;
  final IconData icon;
  final bool number;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onSubmitted: (_) => onSubmit(),
              keyboardType: number ? TextInputType.number : TextInputType.text,
              textInputAction: TextInputAction.send,
              cursorColor: GwColors.accent,
              style: kGwBody.copyWith(fontSize: 14, color: Colors.white),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                filled: false,
                contentPadding: EdgeInsets.zero,
                hintText: hint,
                hintStyle: kGwBody.copyWith(fontSize: 14, color: GwColors.hint),
              ),
            ),
          ),
          GwPressable(
            tooltip: hint,
            onTap: onSubmit,
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: GwColors.accent,
              ),
              child: Icon(icon, size: 19, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GwPressable(
      haptic: GwHaptic.medium,
      pressedScale: 0.96,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: enabled
              ? const LinearGradient(
                  colors: [Color(0xFFFF4A4F), Color(0xFFE8202A)],
                )
              : null,
          color: enabled ? null : const Color(0x14FFFFFF),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: enabled ? Colors.white : GwColors.hint,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// What was answered, as chips.
class _AnswerChips extends StatelessWidget {
  const _AnswerChips({required this.answer, required this.options});

  final Object? answer;
  final List<QuestionOption> options;

  String _label(Object? value) {
    final text = value?.toString() ?? '';
    for (final o in options) {
      if (o.value == text) return o.label;
    }
    if (text == '__suggest_more__') return 'Suggest more';
    if (text.startsWith('__chat_refinement__:')) {
      return text.substring('__chat_refinement__:'.length);
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final values = switch (answer) {
      final List<Object?> list => list.map((v) => v is Map ? v['url'] : v),
      final other => [other],
    };
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final v in values)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0x26FF343C),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _label(v),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

// ── The end of a run ───────────────────────────────────────────────────────

/// Finished (with "Proceed to Editor" when there is an essay), failed, or
/// stopped.
class GwEndCard extends StatelessWidget {
  const GwEndCard({super.key, required this.end, this.onOpenEditor});

  final EndItem end;
  final VoidCallback? onOpenEditor;

  @override
  Widget build(BuildContext context) {
    final (icon, color, text) = switch (end.phase) {
      RunPhase.finished => (
        Icons.check_circle_rounded,
        const Color(0xFF3DDC84),
        'Your essay is ready.',
      ),
      RunPhase.cancelled => (
        Icons.stop_circle_rounded,
        GwColors.muted,
        'Stopped.',
      ),
      _ => (
        Icons.error_outline_rounded,
        const Color(0xFFFF777D),
        end.error ?? 'GhostWriter stopped.',
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: kGwBody.copyWith(
                    fontSize: 14,
                    height: 1.35,
                    color: end.phase == RunPhase.failed
                        ? const Color(0xFFFF9A9E)
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (end.wroteEssay && onOpenEditor != null)
          GwEditorCard(onTap: onOpenEditor!),
      ],
    );
  }
}

/// "Proceed to Editor": a plain row, no card. Shown at the end of a run as
/// well as the pill, so a first-time user cannot miss where the essay went.
class GwEditorCard extends StatelessWidget {
  const GwEditorCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GwPressable(
      pressedScale: 0.97,
      haptic: GwHaptic.medium,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 14),
        child: Row(
          children: [
            const Icon(
              Icons.edit_note_rounded,
              color: GwColors.accentSoft,
              size: 22,
            ),
            const SizedBox(width: 10),
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
                  Text(
                    'Read and refine your essay',
                    style: kGwBody.copyWith(
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
              color: GwColors.accentSoft,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
