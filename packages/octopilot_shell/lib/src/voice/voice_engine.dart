import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// The microphone and the speaker for voice chat. The words in between go
/// through the main chat like typed ones, so a voice conversation lands in
/// the same history.
abstract class VoiceEngine {
  /// Listens until the user stops talking (or [finishListening]). Returns
  /// what they said; null if nothing.
  Future<String?> listen({
    required ValueChanged<String> onPartial,
    required ValueChanged<double> onLevel,
  });

  /// Take what has been heard so far as the whole turn.
  void finishListening();

  /// Says [text]. [onProgress] goes 0→1 as it is spoken.
  Future<void> speak(
    String text, {
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
  }) async {
    final words = _questions[_turn++ % _questions.length].split(' ');
    _finish = false;
    final cut = _cut = Completer<void>();
    // A breath before they start.
    if (await _wait(wordTime * 3, cut)) return null;
    final heard = <String>[];
    for (final word in words) {
      heard.add(word);
      onPartial(heard.join(' '));
      if (await _talk(wordTime, cut, onLevel) || _finish) break;
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
  Future<void> speak(
    String text, {
    required ValueChanged<double> onLevel,
    required ValueChanged<double> onProgress,
  }) async {
    final words = text.split(' ').length;
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
