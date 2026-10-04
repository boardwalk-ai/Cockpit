import 'package:flutter/material.dart';

import '../motion.dart';
import '../shell_models.dart';
import '../shell_scope.dart';
import '../shell_theme.dart';
import 'voice_orb.dart';

/// Choose the voice the main chat speaks in. Tapping one picks it and plays
/// a short hello in it.
Future<void> showVoicePicker(BuildContext context) {
  final c = ShellColors.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: c.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const _VoicePicker(),
  );
}

class _VoicePicker extends StatefulWidget {
  const _VoicePicker();

  @override
  State<_VoicePicker> createState() => _VoicePickerState();
}

class _VoicePickerState extends State<_VoicePicker> {
  /// The voice saying hello, and how far along.
  String? _playing;
  var _preparing = false;
  var _level = 0.0;
  late final ShellServices _services = ShellScope.of(context);

  @override
  void dispose() {
    if (_playing != null) _services.voice.stop();
    super.dispose();
  }

  Future<void> _pick(ShellVoice voice) async {
    Haptics.select();
    _services.setVoice(voice.id);
    final engine = _services.voice;
    if (_playing != null) engine.stop();
    setState(() {
      _playing = voice.id;
      _preparing = true;
      _level = 0;
    });
    try {
      final hello = await engine.prepare(
        "Hi, I'm ${voice.name}. I'll be your voice in Octopilot.",
        voice: voice.id,
      );
      if (!mounted || _playing != voice.id) return;
      setState(() => _preparing = false);
      await engine.play(
        hello,
        onLevel: (level) {
          if (mounted && _playing == voice.id) setState(() => _level = level);
        },
        onProgress: (_) {},
      );
    } on Object {
      if (mounted && _playing == voice.id) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't play that voice right now.")),
        );
      }
    }
    if (mounted && _playing == voice.id) {
      setState(() {
        _playing = null;
        _preparing = false;
        _level = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    final voices = _services.voices;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Voice',
              style: TextStyle(
                color: c.text,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap one to hear it.',
              style: TextStyle(color: c.muted, fontSize: 14),
            ),
            const SizedBox(height: 18),
            ValueListenableBuilder(
              valueListenable: _services.voiceId,
              builder: (context, chosen, _) => GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.78,
                children: [
                  for (final (i, voice) in voices.indexed)
                    Reveal(
                      delay: Duration(milliseconds: 50 * i),
                      offset: const Offset(0, 0.2),
                      child: _VoiceCard(
                        voice: voice,
                        chosen: voice.id == chosen,
                        playing: _playing == voice.id,
                        preparing: _preparing && _playing == voice.id,
                        level: _playing == voice.id ? _level : 0,
                        onTap: () => _pick(voice),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceCard extends StatelessWidget {
  const _VoiceCard({
    required this.voice,
    required this.chosen,
    required this.playing,
    required this.preparing,
    required this.level,
    required this.onTap,
  });

  final ShellVoice voice;
  final bool chosen;
  final bool playing;
  final bool preparing;
  final double level;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    final color = voice.colors.first;
    return Semantics(
      button: true,
      selected: chosen,
      label: voice.name,
      child: Pressable(
        scale: 0.93,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: kShellEase,
          decoration: BoxDecoration(
            color: chosen
                ? Color.alphaBlend(color.withValues(alpha: 0.12), c.surface)
                : c.raised.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: chosen ? color : c.border,
              width: chosen ? 2 : 1,
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    VoiceOrb(
                      size: 78,
                      colors: voice.colors,
                      phase: preparing
                          ? VoicePhase.thinking
                          : playing
                          ? VoicePhase.speaking
                          : VoicePhase.idle,
                      level: level,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      voice.name,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      voice.female ? 'Female' : 'Male',
                      style: TextStyle(color: c.hint, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (chosen)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: color,
                    size: 20,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
