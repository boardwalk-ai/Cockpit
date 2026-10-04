import 'dart:async';

import 'package:flutter/material.dart';

import '../aurora.dart';
import '../motion.dart';
import '../shell_scope.dart';
import '../shell_theme.dart';
import 'voice_loop.dart';
import 'voice_orb.dart';
import 'voice_picker.dart';

/// Voice mode: a greeting, then hold the orb to talk and let go to send;
/// live captions, end and keyboard. Turns land in the open conversation.
class VoicePage extends StatefulWidget {
  const VoicePage({super.key});

  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<VoicePage> {
  VoiceLoop? _loop;
  ShellServices? _services;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loop != null) return;
    final services = _services = ShellScope.of(context);
    _loop = VoiceLoop(
      engine: services.voice,
      conversation: services.conversation,
      voice: () => services.currentVoice?.id ?? '',
      greeting: services.takeGreeting,
    )..start();
  }

  @override
  void dispose() {
    _loop?.dispose();
    // The next opening's greeting, made while the app is quiet.
    unawaited(_services?.prepareGreeting());
    super.dispose();
  }

  void _close({bool typing = false}) {
    typing ? Haptics.tap() : Haptics.end();
    _loop?.end();
    Navigator.of(context).pop(typing);
  }

  /// The picker plays samples, so the conversation stops speaking first.
  Future<void> _pickVoice(VoiceLoop loop) async {
    loop.interrupt();
    await showVoicePicker(context);
  }

  @override
  Widget build(BuildContext context) {
    final loop = _loop!;
    final services = ShellScope.of(context);
    final c = ShellColors.of(context);
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([loop, services.voiceId]),
        builder: (context, _) {
          final speaking = loop.phase == VoicePhase.speaking;
          final voice = services.currentVoice;
          final palette = voice?.colors ?? loop.phase.colors;
          return AuroraBackground(
            energy: switch (loop.phase) {
              VoicePhase.speaking || VoicePhase.listening => 0.3 + loop.level,
              VoicePhase.thinking => 0.5,
              _ => 0,
            },
            colors: [...palette, palette.first.withValues(alpha: 0.6)],
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Close voice',
                          color: c.text,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          iconSize: 30,
                          onPressed: _close,
                        ),
                        const Spacer(),
                        _PhaseLabel(loop: loop, color: palette.first),
                        const Spacer(),
                        if (voice == null)
                          const SizedBox(width: 48)
                        else
                          _VoiceChip(
                            name: voice.name,
                            color: palette.first,
                            onTap: () => _pickVoice(loop),
                          ),
                      ],
                    ),
                  ),
                  const Spacer(flex: 2),
                  // Held, not tapped: the microphone is open only while the
                  // finger is down, so noise cannot end or start a turn.
                  Listener(
                    onPointerDown: (_) => loop.holdStart(),
                    onPointerUp: (_) => loop.holdEnd(),
                    onPointerCancel: (_) => loop.holdEnd(),
                    child: Semantics(
                      button: true,
                      label: 'Hold to talk',
                      child: Hero(
                        tag: 'voice-orb',
                        child: VoiceOrb(
                          size: 300,
                          phase: loop.phase,
                          level: loop.level,
                          colors: voice?.colors,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: SizedBox(
                      height: 132,
                      child: _Caption(
                        text: speaking ? loop.reply : loop.heard,
                        shown: speaking ? loop.spoken : 1,
                        mine: !speaking,
                        hint: loop.holding
                            ? "I'm listening. Let go to send."
                            : loop.missed
                            ? "I didn't catch that. Hold the orb while you talk."
                            : 'Hold the orb and talk. Let go to send.',
                        error: loop.error,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Keeps End in the middle.
                        const SizedBox(width: 58),
                        _RoundButton(
                          tooltip: 'End voice',
                          icon: Icons.close_rounded,
                          big: true,
                          danger: true,
                          onTap: _close,
                        ),
                        _RoundButton(
                          tooltip: 'Type instead',
                          icon: Icons.keyboard_alt_outlined,
                          onTap: () => _close(typing: true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PhaseLabel extends StatelessWidget {
  const _PhaseLabel({required this.loop, required this.color});

  final VoiceLoop loop;

  /// The voice's colour, for the dot.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    final text = switch (loop.phase) {
      VoicePhase.connecting => 'Connecting',
      VoicePhase.listening => 'Listening',
      VoicePhase.thinking => 'Thinking',
      VoicePhase.speaking => 'Speaking',
      VoicePhase.idle => 'Hold to talk',
    };
    return AnimatedSwitcher(
      duration: motion(context, const Duration(milliseconds: 350)),
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.4),
            end: Offset.zero,
          ).animate(a),
          child: child,
        ),
      ),
      child: Container(
        key: ValueKey(text),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: c.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loop.phase == VoicePhase.thinking) ...[
              BouncingDots(color: color, size: 5),
              const SizedBox(width: 8),
            ] else ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              text,
              style: TextStyle(
                color: c.text,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The words being said; while the reply is spoken, the spoken part lights
/// up word by word.
class _Caption extends StatelessWidget {
  const _Caption({
    required this.text,
    required this.shown,
    required this.mine,
    required this.hint,
    this.error,
  });

  final String text;
  final double shown;
  final bool mine;

  /// Shown while nothing has been said yet.
  final String hint;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    if (error != null) {
      return Center(
        child: Text(
          error!,
          textAlign: TextAlign.center,
          style: TextStyle(color: c.accent, fontSize: 14),
        ),
      );
    }
    if (text.isEmpty) {
      return Center(
        child: Text(
          hint,
          textAlign: TextAlign.center,
          style: TextStyle(color: c.hint, fontSize: 15),
        ),
      );
    }
    final words = text.split(' ');
    final lit = (words.length * shown).ceil();
    final style = TextStyle(
      fontSize: mine ? 22 : 19,
      height: 1.4,
      fontWeight: mine ? FontWeight.w600 : FontWeight.w500,
    );
    return SingleChildScrollView(
      reverse: true,
      child: Text.rich(
        TextSpan(
          children: [
            for (var i = 0; i < words.length; i++)
              TextSpan(
                text: i == 0 ? words[i] : ' ${words[i]}',
                style: style.copyWith(
                  color: i < lit ? c.text : c.text.withValues(alpha: 0.28),
                ),
              ),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.big = false,
    this.danger = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool big;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    final size = big ? 76.0 : 58.0;
    final fill = danger ? c.accent : c.surface.withValues(alpha: 0.75);
    final fg = danger ? c.onAccent : c.text;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Pressable(
          scale: 0.9,
          onTap: onTap,
          child: AnimatedContainer(
            duration: motion(context, const Duration(milliseconds: 250)),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: Border.all(color: danger ? fill : c.border),
              boxShadow: danger
                  ? [
                      BoxShadow(
                        color: c.accent.withValues(alpha: 0.45),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Icon(icon, color: fg, size: big ? 32 : 24),
          ),
        ),
      ),
    );
  }
}

/// The voice speaking; tap to choose another.
class _VoiceChip extends StatelessWidget {
  const _VoiceChip({
    required this.name,
    required this.color,
    required this.onTap,
  });

  final String name;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    return Tooltip(
      message: 'Change voice',
      child: Pressable(
        scale: 0.92,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
          decoration: BoxDecoration(
            color: c.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.graphic_eq_rounded, size: 16, color: color),
              const SizedBox(width: 5),
              Text(
                name,
                style: TextStyle(
                  color: c.text,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
