import 'dart:async';

import 'package:flutter/foundation.dart';

import '../chat/chat_controller.dart';
import '../motion.dart';
import 'voice_engine.dart';
import 'voice_orb.dart';

/// A voice conversation: a greeting, then hold-to-talk turns. The user
/// holds the orb while talking and lets go to send; what was heard goes
/// through the main chat and the reply is spoken. The microphone is open
/// only while the orb is held, so a noisy room does not end or eat turns.
class VoiceLoop extends ChangeNotifier {
  VoiceLoop({
    required this.engine,
    required this.conversation,
    required this.voice,
    this.greeting,
  });

  final VoiceEngine engine;
  final ChatController conversation;

  /// The voice to answer in, read for every reply (it can change midway).
  final String Function() voice;

  /// What to say on opening; null says nothing.
  final String Function()? greeting;

  VoicePhase phase = VoicePhase.connecting;
  double level = 0;

  /// What the user is saying, as it is heard.
  String heard = '';

  /// The reply (or the greeting), and how much of it has been spoken (0–1).
  String reply = '';
  double spoken = 0;

  /// The last hold heard nothing.
  bool missed = false;
  String? error;

  var _running = false;
  var _holding = false;

  /// Bumped by each new turn; an older one stops where it is.
  var _turn = 0;
  var _disposed = false;

  bool get holding => _holding;

  void start() {
    if (_running) return;
    _running = true;
    unawaited(_greet());
  }

  Future<void> _greet() async {
    final say = greeting?.call();
    final turn = _turn;
    if (say != null && say.isNotEmpty) {
      try {
        final speech = await engine.prepare(say, voice: voice(), keep: true);
        if (turn != _turn || !_running) return;
        reply = say;
        spoken = 0;
        _set(VoicePhase.speaking);
        await engine.play(
          speech,
          onLevel: _level,
          onProgress: (p) {
            spoken = p;
            _notify();
          },
        );
      } on Object {
        // No greeting is better than no voice mode.
      }
    }
    if (turn == _turn && _running) _set(VoicePhase.idle);
  }

  /// The orb is pressed: stop whatever is going on and listen.
  void holdStart() {
    if (!_running || _holding) return;
    final turn = ++_turn;
    _holding = true;
    missed = false;
    error = null;
    engine.stop();
    if (conversation.replying) conversation.stop();
    heard = '';
    reply = '';
    spoken = 0;
    _set(VoicePhase.listening);
    unawaited(_hear(turn));
  }

  /// The orb is let go: what was heard is sent.
  void holdEnd() {
    if (!_holding) return;
    _holding = false;
    engine.finishListening();
    _notify();
  }

  Future<void> _hear(int turn) async {
    // The recognizer can end on its own while the orb is still held (a
    // pause, noise); then it is asked again and the pieces are joined.
    final pieces = <String>[];
    try {
      while (true) {
        final said = await engine.listen(
          held: true,
          onPartial: (text) {
            heard = [...pieces, text].where((p) => p.isNotEmpty).join(' ');
            _notify();
          },
          onLevel: _level,
        );
        if (said != null && said.trim().isNotEmpty) pieces.add(said.trim());
        if (!_holding || turn != _turn || !_running) break;
        // Not straight back in: an ending that repeats should not spin.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (!_holding || turn != _turn || !_running) break;
      }
    } on Object catch (e) {
      _holding = false;
      error = e is VoiceUnavailable
          ? e.message
          : "Couldn't hear you. Check the microphone and try again.";
      _set(VoicePhase.idle);
      return;
    }
    if (turn != _turn || !_running) return;
    final text = pieces.join(' ');
    heard = text;
    if (text.isEmpty) {
      missed = true;
      _set(VoicePhase.idle);
      return;
    }
    await _answer(text, turn);
  }

  Future<void> _answer(String said, int turn) async {
    _set(VoicePhase.thinking);
    conversation.send(said);
    await _until(() => !conversation.replying || turn != _turn || !_running);
    if (turn != _turn || !_running) return;
    final failure = conversation.failure;
    if (failure != null) {
      error = failure.message;
      _set(VoicePhase.idle);
      return;
    }
    final text = conversation.messages.isEmpty
        ? ''
        : conversation.messages.last.text;
    // Still thinking until the first sentence's voice is ready; then the
    // reply and its voice start together, and each next sentence is made
    // while the one before it is spoken.
    final pieces = sentences(text);
    final total = text.length;
    Future<Speech> make(int i) => engine.prepare(pieces[i], voice: voice());
    Future<Speech>? next = pieces.isEmpty ? null : make(0);
    var done = 0;
    for (var i = 0; i < pieces.length && next != null; i++) {
      final Speech speech;
      try {
        speech = await next;
      } on Object {
        if (i == 0 && turn == _turn) {
          error = "Couldn't get the voice ready. Try again.";
        }
        break;
      }
      if (turn != _turn || !_running) return;
      next = i + 1 < pieces.length ? make(i + 1) : null;
      // A later sentence that fails is simply not spoken.
      next?.ignore();
      if (i == 0) {
        reply = text;
        _set(VoicePhase.speaking);
      }
      final before = done;
      final length = pieces[i].length;
      await engine.play(
        speech,
        onLevel: _level,
        onProgress: (p) {
          spoken = total == 0 ? 1 : (before + p * length) / total;
          _notify();
        },
      );
      if (turn != _turn || !_running) return;
      done += length;
    }
    if (turn == _turn && _running) _set(VoicePhase.idle);
  }

  /// [text] in sentences to speak one at a time. Very short ones go with
  /// the next, so the voice does not stop and start too often. A long
  /// first sentence is split at a comma: the voice waits for the whole
  /// first piece to be made, and later ones are made while it plays.
  static List<String> sentences(String text) {
    final out = _sentences(text);
    if (out.isNotEmpty && out.first.length > 70) {
      final first = out.first;
      final comma = first.indexOf(RegExp(r',\s'), 20);
      if (comma > 0 && first.length - comma > 25) {
        out.replaceRange(0, 1, [
          first.substring(0, comma + 1),
          first.substring(comma + 1).trim(),
        ]);
      }
    }
    return out;
  }

  static List<String> _sentences(String text) {
    final parts = text
        .trim()
        .split(RegExp(r'(?<=[.!?])\s+'))
        .where((p) => p.trim().isNotEmpty)
        .toList();
    final out = <String>[];
    var carry = '';
    for (final part in parts) {
      carry = carry.isEmpty ? part : '$carry $part';
      if (carry.length >= 40) {
        out.add(carry);
        carry = '';
      }
    }
    if (carry.isNotEmpty) {
      if (out.isEmpty) {
        out.add(carry);
      } else {
        out[out.length - 1] = '${out.last} $carry';
      }
    }
    return out;
  }

  /// Stops speaking (or waiting for a reply) and waits for the next hold.
  void interrupt() {
    if (!_running) return;
    _turn++;
    _holding = false;
    engine.stop();
    if (conversation.replying) conversation.stop();
    _set(VoicePhase.idle);
  }

  void end() {
    _running = false;
    _holding = false;
    _turn++;
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
