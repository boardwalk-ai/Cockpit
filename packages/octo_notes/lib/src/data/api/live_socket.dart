import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// `WS /v1/sessions/{id}/live`: live events for one session (transcript,
/// blocks, ink, devices, recording, jobs, credits). Reconnects with backoff;
/// after every (re)connect it emits a `ready` event carrying the server's
/// layer revisions, so listeners catch up with `?sinceRev=`.
class LiveSocket {
  LiveSocket({
    required this.baseUrl,
    required this.sessionId,
    required this.tokenProvider,
    this.deviceId,
    this.devUserId,
  });

  final String baseUrl;
  final String sessionId;
  final Future<String?> Function() tokenProvider;
  final String? deviceId;

  /// Local dev only (backend auth disabled).
  final String? devUserId;

  final _events = StreamController<Map<String, dynamic>>.broadcast();
  WebSocketChannel? _channel;
  Timer? _ping;
  bool _closed = false;
  int _attempt = 0;

  Stream<Map<String, dynamic>> get events => _events.stream;

  /// Events of one type, e.g. `transcript.stable`, `block.changed`.
  Stream<Map<String, dynamic>> on(String type) => events.where((e) => e['type'] == type);

  Uri get _uri {
    final http = Uri.parse(baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl);
    return http.replace(scheme: http.scheme == 'https' ? 'wss' : 'ws', path: '${http.path}/v1/sessions/$sessionId/live');
  }

  Future<void> connect() async {
    if (_closed) return;
    try {
      final channel = WebSocketChannel.connect(_uri);
      await channel.ready;
      _channel = channel;
      channel.sink.add(jsonEncode({
        'type': 'auth',
        'token': await tokenProvider(),
        'userId': ?devUserId,
        'deviceId': ?deviceId,
      }));
      _ping?.cancel();
      _ping = Timer.periodic(const Duration(seconds: 15), (_) => send('presence'));
      channel.stream.listen(
        (raw) {
          final v = jsonDecode(raw as String);
          if (v is Map<String, dynamic>) {
            if (v['type'] == 'ready') _attempt = 0;
            _events.add(v);
          }
        },
        onDone: _reconnect,
        onError: (_) => _reconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _reconnect();
    }
  }

  void send(String type, [Map<String, dynamic>? data]) {
    _channel?.sink.add(jsonEncode({'type': type, 'data': ?data}));
  }

  void _reconnect() {
    _ping?.cancel();
    if (_closed) return;
    _events.add({'type': 'disconnected'});
    final delay = Duration(milliseconds: (500 * (1 << _attempt.clamp(0, 6))).clamp(500, 30000));
    _attempt++;
    Timer(delay, connect);
  }

  Future<void> close() async {
    _closed = true;
    _ping?.cancel();
    await _channel?.sink.close();
    await _events.close();
  }
}
