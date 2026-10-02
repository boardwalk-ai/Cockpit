import 'dart:async';
import 'dart:convert';

import 'package:ghostwriter/src/data/gw_api.dart';
import 'package:ghostwriter/src/session/gw_session.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// `ghostwriter-api`, faked: JSON calls get [responses] (or `{}`), and one
/// run's events come through a stream the test drives with [send].
class FakeServer {
  FakeServer({Map<String, Object?>? responses})
    : responses = {
        'GET /v1/me': {'name': 'Ada', 'octoCredits': 1200},
        'GET /v1/projects': {'projects': [], 'folders': []},
        ...?responses,
      };

  /// Replies by `METHOD /path`.
  final Map<String, Object?> responses;
  final calls = <String>[];
  final bodies = <Object?>[];
  int connections = 0;
  int cancelled = 0;
  int? lastSince;
  StreamController<List<int>>? _events;
  Completer<void> _connected = Completer();
  Completer<void> _closed = Completer();

  bool get listening =>
      _events != null && _events!.hasListener && !_events!.isClosed;

  /// A session wired to this server, with no waiting between reconnects.
  GwSession session() => GwSession(
    GwApi(baseUrl: 'http://api', client: client),
    retryDelays: const [Duration.zero],
  );

  late final http.Client client = MockClient.streaming((request, body) async {
    final key = '${request.method} ${request.url.path}';
    calls.add(key);
    final text = await body.bytesToString();
    if (text.isNotEmpty) bodies.add(jsonDecode(text));

    if (request.url.path.endsWith('/events')) {
      connections++;
      lastSince = int.tryParse(request.url.queryParameters['sinceSeq'] ?? '');
      final events = _events = StreamController<List<int>>(
        onCancel: () {
          cancelled++;
          if (!_closed.isCompleted) _closed.complete();
        },
      );
      if (!_connected.isCompleted) _connected.complete();
      return http.StreamedResponse(events.stream, 200);
    }
    final reply = responses[key] ?? <String, dynamic>{};
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(reply))),
      200,
    );
  });

  Future<void> connected() async {
    await _connected.future;
    _connected = Completer();
  }

  Future<void> closed() async {
    await _closed.future;
    _closed = Completer();
  }

  void send(Map<String, dynamic> event) {
    final seq = event['seq'];
    final frame =
        '${seq == null ? '' : 'id: $seq\n'}data: ${jsonEncode(event)}\n\n';
    _events!.add(utf8.encode(frame));
    if (const {'done', 'fatal', 'cancelled'}.contains(event['type'])) {
      _events!.close();
    }
  }

  void drop() => _events!.close();
}

/// A run event, as the server sends it.
Map<String, dynamic> ev(
  int? seq,
  String type, [
  Map<String, dynamic>? payload,
]) => {'type': type, 'seq': ?seq, ...?payload};
