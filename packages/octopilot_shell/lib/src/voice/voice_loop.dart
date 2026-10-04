import 'dart:async';

import 'package:flutter/foundation.dart';

import '../chat/chat_controller.dart';
import '../motion.dart';
import 'voice_engine.dart';
import 'voice_orb.dart';

/// A voice conversation: listen, send what was heard through the main chat,
/// speak the reply, listen again, until it is ended.
class VoiceLoop extends ChangeNotifier {
  VoiceLoop({
    required this.engine,
    required this.conversation,
    required this.voice,
  });

  final VoiceEngine engine;
  final ChatController conversation;

  /// The voice to answer in, read for every reply (it can change midway).
  final String Function() voice;

  VoicePhase phase = VoicePhase.connecting;
  double level = 0;

  /// What the user is saying, as it is heard.
  String heard = '';

  /// The reply, and how much of it has been spoken (0–1).
  String reply = '';
  double spoken = 0;

  bool muted = false;
  String? error;

  var _running = false;
  var _disposed = false;

  void start() {
    if (_running) return;
    _running = true;
    unawaited(_run());
  }

  Future<void> _run() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    while (_running && !_disposed) {
      if (muted) {
        _set(VoicePhase.idle);
        await _until(() => !muted || !_running);
        continue;
      }
      heard = '';
      reply = '';
      spoken = 0;
      _set(VoicePhase.listening);
      final String? said;
      try {
        said = await engine.listen(
          onPartial: (text) {
            heard = text;
            _notify();
          },
          onLevel: _level,
        );
      } on Object catch (e) {
        error = e is VoiceUnavailable
            ? e.message
            : "Couldn't hear you. Check the microphone and try again.";
        _running = false;
        _set(VoicePhase.idle);
        break;
      }
      if (!_running) break;
      if (said == null || said.trim().isEmpty) continue;

      _set(VoicePhase.thinking);
      conversation.send(said);
      await _until(() => !conversation.replying);
      if (!_running) break;
      final failure = conversation.failure;
      if (failure != null) {
        error = failure.message;
        _running = false;
        _set(VoicePhase.idle);
        break;
      }
      final text = conversation.messages.isEmpty
          ? ''
          : conversation.messages.last.text;
      // Still thinking until the voice is ready too; then the reply and its
      // voice start together.
      final Speech speech;
      try {
        speech = await engine.prepare(text, voice: voice());
      } on Object {
        error = "Couldn't get the voice ready. Try again.";
        _running = false;
        _set(VoicePhase.idle);
        break;
      }
      if (!_running) break;
      reply = text;
      _set(VoicePhase.speaking);
      await engine.play(
        speech,
        onLevel: _level,
        onProgress: (p) {
          spoken = p;
          _notify();
        },
      );
    }
  }

  /// Ends the turn now: what was heard is sent; a reply stops being spoken.
  void tapOrb() {
    switch (phase) {
      case VoicePhase.listening:
        engine.finishListening();
      case VoicePhase.speaking:
        engine.stop();
      case VoicePhase.thinking:
        conversation.stop();
      case VoicePhase.idle || VoicePhase.connecting:
        break;
    }
  }

  void toggleMute() {
    muted = !muted;
    if (muted) engine.stop();
    _notify();
  }

  void end() {
    _running = false;
    engine.stop();
    conversation.stop();
    _notify();
  }

  void _level(double value) {
    level = value;
    _notify();
  }

  void _set(VoicePhase next) {
    if (next != phase) {
      switch (next) {
        case VoicePhase.listening:
          Haptics.tap();
        case VoicePhase.speaking:
          Haptics.thud();
        case _:
          break;
      }
    }
    phase = next;
    if (next != VoicePhase.listening && next != VoicePhase.speaking) level = 0;
    _notify();
  }

  /// Waits until [done], checking whenever the loop or chat changes.
  Future<void> _until(bool Function() done) async {
    if (done()) return;
    final waiting = Completer<void>();
    void check() {
      if (done() && !waiting.isCompleted) waiting.complete();
    }

    addListener(check);
    conversation.addListener(check);
    try {
      await waiting.future;
    } finally {
      removeListener(check);
      conversation.removeListener(check);
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    end();
    _disposed = true;
    super.dispose();
  }
}
