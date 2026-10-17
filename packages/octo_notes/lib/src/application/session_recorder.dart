import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:record/record.dart';

import '../data/api/octo_notes_api.dart';

enum RecorderStatus { idle, starting, recording, paused, stopping, stopped, failed }

/// Records the lecture on this device into a session: 16 kHz mono PCM from
/// the mic, cut into 10-second WAV chunks and uploaded in order
/// (`PUT /v1/recordings/{id}/chunks/{seq}`); the server transcribes each one
/// and pushes the text to the receiver. A chunk that fails to upload stays
/// queued and is retried, so a weak connection only delays the transcript.
///
/// On Android a foreground service (microphone) keeps the mic alive while
/// the screen is locked.
class SessionRecorder extends ChangeNotifier {
  SessionRecorder({
    required this.api,
    required this.sessionId,
    required this.deviceId,
    this.deviceName = 'this device',
    this.onAudio,
    AudioRecorder? mic,
  }) : _mic = mic ?? AudioRecorder();

  final OctoNotesApi api;
  final String sessionId;
  final String deviceId;

  /// Shown in the Android notification ("Recording on …").
  final String deviceName;

  final AudioRecorder _mic;

  /// Every bit of audio as it's captured (live captions read it).
  final ValueChanged<Uint8List>? onAudio;

  static const sampleRate = 16000;
  static const chunkMs = 10000;
  static const _bytesPerMs = sampleRate * 2 ~/ 1000; // 16-bit mono
  static const _chunkBytes = chunkMs * _bytesPerMs;

  RecorderStatus _status = RecorderStatus.idle;
  RecorderStatus get status => _status;

  /// Why it failed (permission, server), in plain words.
  String? error;

  String? recordingId;

  /// Recorded audio so far (pauses excluded).
  int get elapsedMs => _capturedBytes ~/ _bytesPerMs;
  int _capturedBytes = 0;

  /// Input level, 0..1, for the waveform.
  double level = 0;

  /// Chunks recorded but not on the server yet.
  int get pendingChunks => _queue.length + (_uploading ? 1 : 0);

  /// Seconds of audio waiting to upload ("Uploaded · 0s behind").
  int get behindSeconds => (pendingChunks * chunkMs) ~/ 1000;

  bool get isRecording => _status == RecorderStatus.recording;
  bool get isPaused => _status == RecorderStatus.paused;
  bool get isActive => isRecording || isPaused;

  final _buffer = BytesBuilder(copy: false);
  int _bufferStartMs = 0;
  int _seq = 0;
  final _queue = Queue<_Chunk>();
  bool _uploading = false;
  StreamSubscription<Uint8List>? _sub;
  Timer? _tick;
  bool _disposed = false;
  Completer<void>? _drained;

  Future<void> start() async {
    if (_status != RecorderStatus.idle && _status != RecorderStatus.failed) return;
    _set(RecorderStatus.starting);
    error = null;
    try {
      if (!await _mic.hasPermission()) {
        return _fail('Allow the microphone to record the lecture.');
      }
      final rec = await api.startRecording(
        sessionId,
        deviceId,
        id: recordingId ?? OctoNotesApi.newId(),
        container: 'wav',
        sampleRate: sampleRate,
        chunkMs: chunkMs,
      );
      recordingId = rec['id'] as String;
      await _keepAlive();
      final stream = await _mic.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        autoGain: true,
        noiseSuppress: true,
      ));
      _sub = stream.listen(_onPcm, onError: (Object e) => _fail('The microphone stopped: $e'));
      // Repaint the timer even when the mic delivers in large blocks.
      _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _notify());
      _set(RecorderStatus.recording);
    } on Object catch (e) {
      await _release();
      _fail('Could not start recording: $e');
    }
  }

  void _onPcm(Uint8List pcm) {
    if (_status != RecorderStatus.recording) return;
    _buffer.add(pcm);
    _capturedBytes += pcm.length;
    onAudio?.call(pcm);
    level = _rms(pcm);
    while (_buffer.length >= _chunkBytes) {
      final all = _buffer.takeBytes();
      _enqueue(Uint8List.sublistView(all, 0, _chunkBytes));
      if (all.length > _chunkBytes) _buffer.add(Uint8List.sublistView(all, _chunkBytes));
    }
  }

  static double _rms(Uint8List pcm) {
    final samples = pcm.buffer.asByteData(pcm.offsetInBytes, pcm.lengthInBytes);
    final n = pcm.lengthInBytes ~/ 2;
    if (n == 0) return 0;
    var sum = 0.0;
    for (var i = 0; i < n; i += 4) {
      final v = samples.getInt16(i * 2, Endian.little) / 32768.0;
      sum += v * v;
    }
    final rms = math.sqrt(sum / (n / 4).ceil());
    return (rms * 4).clamp(0.0, 1.0);
  }

  void _enqueue(Uint8List pcm) {
    final durationMs = pcm.length ~/ _bytesPerMs;
    if (durationMs < 1) return;
    _queue.add(_Chunk(_seq++, _bufferStartMs, durationMs, pcm));
    _bufferStartMs += durationMs;
    _notify();
    _pump();
  }

  Future<void> _pump() async {
    if (_uploading) return;
    _uploading = true;
    var wait = const Duration(seconds: 1);
    while (_queue.isNotEmpty && !_disposed) {
      final c = _queue.first;
      try {
        await api.uploadChunk(recordingId!, c.seq, wav(c.pcm, sampleRate),
            startMs: c.startMs, durationMs: c.durationMs, contentType: 'audio/wav');
        _queue.removeFirst();
        wait = const Duration(seconds: 1);
        _notify();
      } on Object {
        // Offline or the server is busy: keep the chunk, try again later.
        await Future<void>.delayed(wait);
        wait = Duration(seconds: math.min(wait.inSeconds * 2, 30));
      }
    }
    _uploading = false;
    final drained = _drained;
    if (_queue.isEmpty && drained != null && !drained.isCompleted) drained.complete();
  }

  Future<void> pause() async {
    if (!isRecording) return;
    await _mic.pause();
    _set(RecorderStatus.paused);
    level = 0;
    unawaited(_state('paused'));
  }

  Future<void> resume() async {
    if (!isPaused) return;
    await _mic.resume();
    _set(RecorderStatus.recording);
    unawaited(_state('recording'));
  }

  /// Stops the mic, uploads what's left and closes the recording. Returns
  /// when the server has every chunk (or it gave up after [timeout]).
  Future<void> stop({Duration timeout = const Duration(minutes: 2)}) async {
    if (!isActive) return;
    _set(RecorderStatus.stopping);
    await _sub?.cancel();
    _sub = null;
    await _mic.stop();
    if (_buffer.length > 0) _enqueue(_buffer.takeBytes());
    level = 0;
    if (pendingChunks > 0) {
      _drained = Completer<void>();
      unawaited(_pump());
      await _drained!.future.timeout(timeout, onTimeout: () {});
    }
    try {
      if (_queue.isEmpty) await api.completeRecording(recordingId!, _seq - 1);
      await _state('stopped');
    } on Object {
      // The server assembles what it has; nothing to do here.
    }
    await _release();
    _set(RecorderStatus.stopped);
  }

  /// "Important" at this moment of the recording.
  Future<void> mark() => api.addMarker(sessionId, 'important', elapsedMs);

  Future<void> _state(String state) async {
    final id = recordingId;
    if (id == null) return;
    try {
      await api.setRecordingState(id, state, durationMs: elapsedMs);
    } on Object {
      // Informational only (the receiver's "paused" badge).
    }
  }

  Future<void> _keepAlive() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'octonotes_recording',
        channelName: 'Lecture recording',
        channelDescription: 'Shown while OctoNotes records a lecture.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(eventAction: ForegroundTaskEventAction.nothing()),
    );
    await FlutterForegroundTask.startService(
      serviceTypes: [ForegroundServiceTypes.microphone],
      notificationTitle: 'OctoNotes is recording',
      notificationText: 'Recording on $deviceName. Tap to open.',
    );
  }

  Future<void> _release() async {
    _tick?.cancel();
    _tick = null;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await FlutterForegroundTask.stopService();
      } on Object {
        // Not running.
      }
    }
  }

  void _fail(String message) {
    error = message;
    _set(RecorderStatus.failed);
  }

  void _set(RecorderStatus s) {
    _status = s;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    unawaited(_release());
    unawaited(_mic.dispose());
    super.dispose();
  }

  /// 16-bit mono PCM wrapped in a WAV header.
  static Uint8List wav(Uint8List pcm, int sampleRate) {
    final h = ByteData(44);
    void ascii(int at, String s) {
      for (var i = 0; i < s.length; i++) {
        h.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    h.setUint32(4, 36 + pcm.length, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    h.setUint32(16, 16, Endian.little);
    h.setUint16(20, 1, Endian.little); // PCM
    h.setUint16(22, 1, Endian.little); // mono
    h.setUint32(24, sampleRate, Endian.little);
    h.setUint32(28, sampleRate * 2, Endian.little);
    h.setUint16(32, 2, Endian.little);
    h.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    h.setUint32(40, pcm.length, Endian.little);
    return (BytesBuilder(copy: false)
          ..add(h.buffer.asUint8List())
          ..add(pcm))
        .takeBytes();
  }
}

class _Chunk {
  _Chunk(this.seq, this.startMs, this.durationMs, this.pcm);
  final int seq;
  final int startMs;
  final int durationMs;
  final Uint8List pcm;
}
