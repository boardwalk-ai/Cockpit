import 'dart:async';
import 'dart:convert';

import 'package:ghostwriter/src/data/gw_api.dart';
import 'package:ghostwriter/src/session/gw_session.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A reply with a status other than 200.
class FakeReply {
  const FakeReply(this.status, this.body);
  final int status;
  final Object? body;
}

/// `ghostwriter-api`, faked: JSON calls get [responses] (or `{}`), and one
/// SSE stream at a time (a run's events or a document's) comes through a
/// stream the test drives with [send].
///
/// A response may be a value, a [FakeReply], or a function of the request
/// body returning either.
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

    if (request.url.path.endsWith('/events') ||
        request.url.path.endsWith('/stream')) {
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
    var reply = responses[key] ?? <String, dynamic>{};
    if (reply is Function) {
      reply = reply(text.isEmpty ? null : jsonDecode(text));
    }
    final (status, payload) = reply is FakeReply
        ? (reply.status, reply.body)
        : (200, reply);
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(payload))),
      status,
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
    if (const {'done', 'fatal', 'cancelled'}.contains(event['type']) &&
        seq != null) {
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
