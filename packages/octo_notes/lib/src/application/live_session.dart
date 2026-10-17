import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/api/live_socket.dart';
import '../data/api/octo_notes_api.dart';

/// One line of the live transcript.
class TranscriptLine {
  const TranscriptLine({required this.id, required this.startMs, required this.text, this.endMs, this.live = false});
  final String id;
  final int startMs;
  final int? endMs;
  final String text;

  /// From the phone's own speech model, ahead of the server's transcript
  /// (still being heard when it's the last one).
  final bool live;
}

/// What a session's screen shows live: the transcript as the server writes
/// it, and whether (and on which device) the lecture is being recorded.
/// Follows `WS /v1/sessions/{id}/live` and refetches on each event.
///
/// Without a backend (or a session id) it plays sample lines, so the page
/// still demos offline.
class LiveSession extends ChangeNotifier {
  LiveSession({this.api, this.sessionId, this.socket, this.thisDeviceId});

  /// Set once known; captions this device sent itself aren't taken back.

  final OctoNotesApi? api;
  final String? sessionId;
  final LiveSocket? socket;

  /// This device, so it isn't reported as "the other device recording".
  String? thisDeviceId;

  bool get isDemo => api == null || sessionId == null;

  /// The server's transcript, then the phone's captions past its end.
  List<TranscriptLine> get lines {
    final end = _server.isEmpty ? -1 : (_server.last.endMs ?? _server.last.startMs);
    final ahead = _captions.values.where((c) => c.startMs >= end).toList()..sort((a, b) => a.startMs.compareTo(b.startMs));
    return ahead.isEmpty ? _server : [..._server, ...ahead];
  }

  final List<TranscriptLine> _server = [];
  final Map<String, TranscriptLine> _captions = {};
  int? _rev;

  /// A caption from the recording phone (this one, or over the socket).
  void addCaption(Map<String, dynamic> c) {
    final id = '${c['deviceId'] ?? 'me'}:${c['segId']}';
    final text = (c['text'] as String? ?? '').trim();
    if (text.isEmpty) return;
    _captions[id] = TranscriptLine(
      id: id,
      startMs: (c['startMs'] as num?)?.toInt() ?? 0,
      endMs: (c['endMs'] as num?)?.toInt(),
      text: text,
      live: true,
    );
    _notify();
  }

  /// Captions the server's transcript has caught up with go.
  void _pruneCaptions() {
    if (_server.isEmpty) return;
    final end = _server.last.endMs ?? _server.last.startMs;
    _captions.removeWhere((_, c) => (c.endMs ?? c.startMs) <= end);
  }

  /// The session's title, once loaded.
  String? title;

  /// The other device in the session (the receiver, seen from the recorder).
  String? otherDeviceName;

  /// The recording device when it's another one ("Pixel 8").
  String? recorderName;
  bool recorderOnline = false;

  /// `recording` | `paused` | `stopped` | `assembled`, or null before any.
  String? recordingState;
  DateTime? _recordingStartedAt;
  int _recordedMs = 0;
  DateTime? _recordedAt;

  bool get isRecording => recordingState == 'recording';

  /// Recording time, counted on from the last server report.
  int get elapsedMs {
    if (isRecording && _recordedAt != null) {
      return _recordedMs + DateTime.now().difference(_recordedAt!).inMilliseconds;
    }
    if (isRecording && _recordingStartedAt != null) {
      return DateTime.now().difference(_recordingStartedAt!).inMilliseconds;
    }
    return _recordedMs;
  }

  StreamSubscription<Map<String, dynamic>>? _events;
  Timer? _demo;
  Timer? _tick;
  bool _disposed = false;

  Future<void> start() async {
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isRecording) _notify();
    });
    if (isDemo) {
      _startDemo();
      return;
    }
    _events = socket?.events.listen(_onEvent);
    unawaited(socket?.connect());
    await Future.wait([_snapshot(), _transcript(), _devices(), _recording()]);
  }

  Future<void> _snapshot() async {
    try {
      final snap = await api!.sessionSnapshot(sessionId!);
      title = (snap['session'] as Map?)?['title'] as String?;
      _notify();
    } on Object {
      // The header falls back to "Live session".
    }
  }

  @visibleForTesting
  void debugEvent(Map<String, dynamic> e) => _onEvent(e);

  void _onEvent(Map<String, dynamic> e) {
    switch (e['type']) {
      case 'ready':
        unawaited(_transcript());
        unawaited(_devices());
        unawaited(_recording());
      case 'transcript.stable' || 'transcript.faithful' || 'transcript.corrected':
        unawaited(_transcript());
      case 'transcript.live':
        final data = e['data'];
        if (data is Map<String, dynamic> && data['deviceId'] != thisDeviceId) addCaption(data);
      case 'device.presence':
        unawaited(_devices());
      case 'recording.state':
        final data = e['data'];
        if (data is Map && data['durationMs'] is int) {
          _recordedMs = data['durationMs'] as int;
          _recordedAt = DateTime.now();
        }
        if (data is Map && data['state'] is String) recordingState = data['state'] as String;
        _notify();
        unawaited(_devices());
    }
  }

  Future<void> _transcript() async {
    try {
      final page = await api!.transcript(sessionId!, sinceRev: _rev);
      for (final s in (page['segments'] as List? ?? const [])) {
        final m = s as Map<String, dynamic>;
        final line = TranscriptLine(
          id: m['id'] as String,
          startMs: (m['startMs'] as num?)?.toInt() ?? 0,
          endMs: (m['endMs'] as num?)?.toInt(),
          text: (m['displayText'] ?? m['rawText'] ?? '') as String,
        );
        final i = _server.indexWhere((l) => l.id == line.id);
        if (i >= 0) {
          _server[i] = line;
        } else {
          _server.add(line);
        }
      }
      _server.sort((a, b) => a.startMs.compareTo(b.startMs));
      _pruneCaptions();
      _rev = (page['rev'] as num?)?.toInt() ?? _rev;
      _notify();
    } on Object {
      // The next event or reconnect fetches again.
    }
  }

  Future<void> _devices() async {
    try {
      final devices = await api!.sessionDevices(sessionId!);
      final recorder = devices
          .cast<Map<String, dynamic>>()
          .where((d) => d['role'] == 'recorder' && d['deviceId'] != thisDeviceId)
          .firstOrNull;
      recorderName = recorder?['name'] as String?;
      recorderOnline = recorder?['online'] == true;
      otherDeviceName = devices
          .cast<Map<String, dynamic>>()
          .where((d) => d['deviceId'] != thisDeviceId)
          .map((d) => d['name'] as String?)
          .firstOrNull;
      _notify();
    } on Object {
      // Kept as it was.
    }
  }

  Future<void> _recording() async {
    try {
      final list = (await api!.recordings(sessionId!)).cast<Map<String, dynamic>>();
      if (list.isEmpty) return;
      list.sort((a, b) => '${a['startedAt']}'.compareTo('${b['startedAt']}'));
      final r = list.last;
      recordingState = r['state'] as String?;
      _recordingStartedAt = DateTime.tryParse('${r['startedAt']}');
      final d = (r['durationMs'] as num?)?.toInt();
      if (d != null) {
        _recordedMs = d;
        _recordedAt = recordingState == 'recording' ? DateTime.now() : null;
      }
      _notify();
    } on Object {
      // Kept as it was.
    }
  }

  /// "Important" now, from the receiver.
  Future<void> mark() async {
    if (isDemo) return;
    await api!.addMarker(sessionId!, 'important', elapsedMs);
  }

  void _startDemo() {
    var i = 0;
    var t = 0;
    void add() {
      _server.add(TranscriptLine(id: 'demo-$t', startMs: t, text: _sample[i % _sample.length]));
      i++;
      t += 7000;
      _notify();
    }

    recordingState = 'recording';
    _recordingStartedAt = DateTime.now();
    add();
    _demo = Timer.periodic(const Duration(milliseconds: 2600), (_) => add());
  }

  static const _sample = [
    'Glycolysis occurs in the cytoplasm and does not require oxygen.',
    'The net result is two ATP and two NADH.',
    'Pyruvate then enters the mitochondria for the next stage.',
    'The electron transport chain builds a proton gradient.',
    'Oxygen accepts electrons at the end of the transport chain.',
  ];

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _demo?.cancel();
    _tick?.cancel();
    _events?.cancel();
    unawaited(socket?.close());
    super.dispose();
  }
}
