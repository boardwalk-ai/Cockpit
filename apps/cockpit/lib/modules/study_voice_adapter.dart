import 'package:flutter/foundation.dart';
import 'package:octopilot_shell/octopilot_shell.dart';
import 'package:study_studio/study_studio.dart';

/// Study Studio's microphone and speaker: the app's voice engine (the same
/// on-device speech in and out as voice mode), in the voice picked there.
class EngineStudyVoice implements StudyVoice {
  EngineStudyVoice(this._engine, this._voice);

  final VoiceEngine _engine;
  final ValueListenable<String> _voice;

  /// Speech already being made (the next question), by text.
  final _made = <String, Future<Speech>>{};

  Future<Speech> _make(String text) =>
      _engine.prepare(text, voice: _voice.value);

  @override
  Future<String?> listen({required ValueChanged<String> onPartial}) =>
      _engine.listen(onPartial: onPartial, onLevel: (_) {}, held: true);

  @override
  void finishListening() => _engine.finishListening();

  @override
  Future<void> say(String text) async {
    final speech = await (_made.remove(text) ?? _make(text));
    await _engine.play(speech, onLevel: (_) {}, onProgress: (_) {});
  }

  @override
  void warm(String text) {
    if (_made.length >= 3) _made.remove(_made.keys.first);
    // A failure here only means it is made again when asked.
    _made[text] ??= _make(text)..ignore();
  }

  @override
  void stop() => _engine.stop();
}
