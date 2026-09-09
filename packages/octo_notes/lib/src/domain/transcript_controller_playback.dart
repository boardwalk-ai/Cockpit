import 'dart:async';

import 'package:flutter/foundation.dart';

/// Simulated transcript audio player (spec §8). There is no real audio yet —
/// this drives the waveform progress, timestamp, and speed so the playback UI
/// can be built. [uploadPending] models an audio chunk still on the phone.
class TranscriptPlayback {
  TranscriptPlayback(this._onChange);

  final VoidCallback _onChange;
  Timer? _timer;

  static const int totalSeconds = 42 * 60 + 16; // 42:16
  int position = 18 * 60 + 32; // 18:32 (the active segment)
  bool playing = false;
  double speed = 1.0;
  bool uploadPending = false;

  static const List<double> speeds = [0.75, 1, 1.25, 1.5, 2];

  String get positionLabel => _fmt(position);
  String get totalLabel => _fmt(totalSeconds);
  double get progress => position / totalSeconds;

  void toggle() => playing ? pause() : play();

  void play() {
    playing = true;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      position = (position + speed.round()).clamp(0, totalSeconds);
      if (position >= totalSeconds) pause();
      _ping();
    });
    _ping();
  }

  void pause() {
    playing = false;
    _timer?.cancel();
    _ping();
  }

  void seekTo(int seconds) {
    position = seconds.clamp(0, totalSeconds);
    _ping();
  }

  void seekToLabel(String mmss) => seekTo(_parse(mmss));

  void nudge(int deltaSeconds) => seekTo(position + deltaSeconds);

  void cycleSpeed() {
    final i = speeds.indexOf(speed);
    speed = speeds[(i + 1) % speeds.length].toDouble();
    _ping();
  }

  void dispose() => _timer?.cancel();

  void _ping() => _onChange();

  static String _fmt(int total) {
    final m = (total ~/ 60).toString();
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  static int _parse(String mmss) {
    final parts = mmss.split(':');
    if (parts.length != 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }
}
