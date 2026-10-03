import 'package:flutter/material.dart';

import '../aurora.dart';
import '../motion.dart';
import '../shell_scope.dart';
import '../shell_theme.dart';
import 'voice_loop.dart';
import 'voice_orb.dart';

/// Voice mode: the orb, live captions, mute / end / keyboard. Turns land in
/// the open conversation.
class VoicePage extends StatefulWidget {
  const VoicePage({super.key});

  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<VoicePage> {
  VoiceLoop? _loop;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loop != null) return;
    final services = ShellScope.of(context);
    _loop = VoiceLoop(
      engine: services.voice,
      conversation: services.conversation,
    )..start();
  }

  @override
  void dispose() {
    _loop?.dispose();
    super.dispose();
  }

  void _close({bool typing = false}) {
    _loop?.end();
    Navigator.of(context).pop(typing);
  }

  @override
  Widget build(BuildContext context) {
    final loop = _loop!;
    final c = ShellColors.of(context);
    return Scaffold(
      body: ListenableBuilder(
        listenable: loop,
        builder: (context, _) {
          final speaking = loop.phase == VoicePhase.speaking;
          return AuroraBackground(
            energy: switch (loop.phase) {
              VoicePhase.speaking || VoicePhase.listening => 0.3 + loop.level,
              VoicePhase.thinking => 0.5,
              _ => 0,
            },
            colors: [...loop.phase.colors, const Color(0xFF8B83F0)],
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
                        _PhaseLabel(loop: loop),
                        const Spacer(),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  const Spacer(flex: 2),
                  GestureDetector(
                    onTap: loop.tapOrb,
                    child: Hero(
                      tag: 'voice-orb',
                      child: VoiceOrb(
                        size: 300,
                        phase: loop.phase,
                        level: loop.level,
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
                        _RoundButton(
                          tooltip: loop.muted ? 'Unmute' : 'Mute',
                          icon: loop.muted
                              ? Icons.mic_off_rounded
                              : Icons.mic_none_rounded,
                          active: loop.muted,
                          onTap: loop.toggleMute,
                        ),
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
  const _PhaseLabel({required this.loop});

  final VoiceLoop loop;

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    final text = loop.muted
        ? 'Muted'
        : switch (loop.phase) {
            VoicePhase.connecting => 'Connecting',
            VoicePhase.listening => 'Listening',
            VoicePhase.thinking => 'Thinking',
            VoicePhase.speaking => 'Speaking',
            VoicePhase.idle => 'Paused',
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
            if (loop.phase == VoicePhase.thinking && !loop.muted) ...[
              BouncingDots(color: loop.phase.colors.first, size: 5),
              const SizedBox(width: 8),
            ] else ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: loop.muted ? c.hint : loop.phase.colors.first,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              text,
              style: TextStyle(
                color: c.text,
                fontSize: 13,
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
    this.error,
  });

  final String text;
  final double shown;
  final bool mine;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    if (error != null) {
      return Center(
        child: Text(
          error!,
          textAlign: TextAlign.center,
          style: TextStyle(color: c.accent, fontSize: 16),
        ),
      );
    }
    if (text.isEmpty) {
      return Center(
        child: Text(
          'Go ahead, I\'m listening.',
          style: TextStyle(color: c.hint, fontSize: 17),
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
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool big;
  final bool danger;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    final size = big ? 76.0 : 58.0;
    final fill = danger
        ? c.accent
        : active
        ? c.text
        : c.surface.withValues(alpha: 0.75);
    final fg = danger
        ? c.onAccent
        : active
        ? c.background
        : c.text;
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
