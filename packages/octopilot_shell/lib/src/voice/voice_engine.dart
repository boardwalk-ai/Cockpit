import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Speech made ready to play: the whole reply, already synthesised.
class Speech {
  const Speech({required this.text, required this.duration, this.audio});

  final String text;
  final Duration duration;

  /// The engine's own audio; the shell never looks inside.
  final Object? audio;
}

/// The microphone or the speaker can't be used, with words fit for the user.
class VoiceUnavailable implements Exception {
  const VoiceUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The microphone and the speaker for voice chat. The words in between go
/// through the main chat like typed ones, so a voice conversation lands in
/// the same history.
abstract class VoiceEngine {
  /// Listens until the user stops talking (or [finishListening]). Returns
  /// what they said; null if nothing. [held]: the user holds a button while
  /// talking, so a pause is not the end; only [finishListening] is (the
  /// recognizer may still end on its own, and is then asked again).
  Future<String?> listen({
    required ValueChanged<String> onPartial,
    required ValueChanged<double> onLevel,
    bool held = false,
  });

  /// Take what has been heard so far as the whole turn. Also counts when
  /// it comes right after [listen] was called, before the microphone opened.
  void finishListening();

  /// Synthesises [text] in [voice]. The reply is shown only once this is
  /// done, then its words light up as [play] speaks them. [keep]: the same
  /// text will be asked for again (a greeting), so the engine may keep it.
  Future<Speech> prepare(
    String text, {
    required String voice,
    bool keep = false,
  });

  /// Plays [speech]. [onProgress] goes 0→1 as it is spoken.
  Future<void> play(
    Speech speech, {
    required ValueChanged<double> onLevel,
    required ValueChanged<double> onProgress,
  });

  /// Stops listening or speaking at once.
  void stop();
}

/// A pretend microphone and speaker, until the real ones are wired: it
/// "hears" a sample question and moves the levels as if speaking.
class DemoVoiceEngine implements VoiceEngine {
  DemoVoiceEngine({
    this.wordTime = const Duration(milliseconds: 260),
    this.frame = const Duration(milliseconds: 50),
  });

  /// How long a spoken word takes.
  final Duration wordTime;
  final Duration frame;

  static const _questions = [
    'How do I write an essay here?',
    'What can Octopilot do for me?',
    'How do OctoCredits work?',
  ];

  var _turn = 0;
  final _random = math.Random(7);
  Completer<void>? _cut;
  var _finish = false;

  @override
  Future<String?> listen({
    required ValueChanged<String> onPartial,
    required ValueChanged<double> onLevel,
    bool held = false,
  }) async {
    final words = _questions[_turn++ % _questions.length].split(' ');
    _finish = false;
    final cut = _cut = Completer<void>();
    // A breath before they start.
    if (await _wait(wordTime * 3, cut) || _finish) return null;
    final heard = <String>[];
    for (final word in words) {
      heard.add(word);
      onPartial(heard.join(' '));
      if (await _talk(wordTime, cut, onLevel) || _finish) break;
    }
    // Held: the words are out; wait for the release.
    while (held && !_finish && !cut.isCompleted) {
      await _wait(frame, cut);
    }
    onLevel(0);
    if (cut.isCompleted && !_finish) return null;
    _cut = null;
    return heard.join(' ');
  }

  @override
  void finishListening() {
    _finish = true;
  }

  @override
  Future<Speech> prepare(
    String text, {
    required String voice,
    bool keep = false,
  }) async {
    await Future<void>.delayed(wordTime * 2);
    final words = text.split(' ').length;
    return Speech(text: text, duration: wordTime * 0.7 * words);
  }

  @override
  Future<void> play(
    Speech speech, {
    required ValueChanged<double> onLevel,
    required ValueChanged<double> onProgress,
  }) async {
    final words = speech.text.split(' ').length;
    final cut = _cut = Completer<void>();
    for (var i = 1; i <= words; i++) {
      if (await _talk(wordTime * 0.7, cut, onLevel)) break;
      onProgress(i / words);
    }
    onLevel(0);
    _cut = null;
  }

  @override
  void stop() {
    final cut = _cut;
    if (cut != null && !cut.isCompleted) cut.complete();
  }

  /// Moves the level like a voice for [time]. True if cut short.
  Future<bool> _talk(
    Duration time,
    Completer<void> cut,
    ValueChanged<double> onLevel,
  ) async {
    final frames = math.max(1, time.inMilliseconds ~/ frame.inMilliseconds);
    for (var i = 0; i < frames; i++) {
      final syllable = math.sin(i / frames * math.pi);
      onLevel(
        (0.25 + 0.6 * syllable * (0.6 + 0.4 * _random.nextDouble())).clamp(
          0.0,
          1.0,
        ),
      );
      if (await _wait(frame, cut)) return true;
    }
    return false;
  }

  /// Waits [time]; true if [cut] came first.
  static Future<bool> _wait(Duration time, Completer<void> cut) async {
    if (cut.isCompleted) return true;
    await Future.any([Future<void>.delayed(time), cut.future]);
    return cut.isCompleted;
  }
}
