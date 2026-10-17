import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../../application/config.dart';

/// One parsed Server-Sent Event.
class SseEvent {
  const SseEvent(this.event, this.data);

  final String event;
  final Map<String, dynamic> data;
}

/// Minimal SSE client for the Study Studio backend.
///
/// The backend speaks `text/event-stream` for everything. Since the module's
/// repository/AI interfaces are `Future`-based (not streams), we read the whole
/// response body and parse the events — simple and cross-platform (web + io)
/// with just `package:http`. Switch to an incremental reader if the UI later
/// wants token-by-token rendering.
class SseClient {
  SseClient({
    http.Client? client,
    String? baseUrl,
    String? userId,
    Future<String?> Function()? tokenProvider,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? StudioConfig.apiBaseUrl,
       _userId = userId ?? StudioConfig.devUserId,
       // ignore: prefer_initializing_formals — public name differs from field
       _tokenProvider = tokenProvider;

  final http.Client _client;
  final String _baseUrl;
  final String _userId;

  /// Supplies the Firebase ID token when signed in; null falls back to the dev
  /// X-User-Id header.
  final Future<String?> Function()? _tokenProvider;

  Future<Map<String, String>> _headers() async {
    final token = await _tokenProvider?.call();
    return {
      'Accept': 'text/event-stream',
      if (token != null && token.isNotEmpty)
        'Authorization': 'Bearer $token'
      else
        'X-User-Id': _userId,
    };
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse('$_baseUrl$path');
    if (query == null || query.isEmpty) return base;
    return base.replace(
      queryParameters: {
        ...base.queryParameters,
        for (final e in query.entries) e.key: '${e.value}',
      },
    );
  }

  Future<List<SseEvent>> get(String path, {Map<String, dynamic>? query}) async {
    final resp = await _client.get(
      _uri(path, query),
      headers: await _headers(),
    );
    return _parse(resp);
  }

  /// A POST. With [retry], a dropped connection is tried once more — only
  /// for requests the server dedupes (an `event_id` or `Idempotency-Key`).
  Future<List<SseEvent>> post(
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? body,
    Map<String, String>? extraHeaders,
    bool retry = false,
  }) async {
    final headers = await _headers();
    if (body != null) headers['Content-Type'] = 'application/json';
    if (extraHeaders != null) headers.addAll(extraHeaders);
    Future<http.Response> send() => _client.post(
      _uri(path, query),
      headers: headers,
      body: body == null ? null : jsonEncode(body),
    );
    http.Response resp;
    try {
      resp = await send();
    } on http.ClientException {
      if (!retry) rethrow;
      resp = await send();
    }
    return _parse(resp);
  }

  Future<List<SseEvent>> delete(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final resp = await _client.delete(
      _uri(path, query),
      headers: await _headers(),
    );
    return _parse(resp);
  }

  /// The events of a GET as they arrive (token-by-token answers). Throws
  /// [SseException] on an HTTP error or an `error` event.
  Stream<SseEvent> stream(String path, {Map<String, dynamic>? query}) async* {
    final request = http.Request('GET', _uri(path, query))
      ..headers.addAll(await _headers());
    final resp = await _client.send(request);
    if (resp.statusCode >= 400) {
      throw SseException('HTTP ${resp.statusCode} for ${request.url}');
    }
    final reader = SseReader();
    await for (final line
        in resp.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      final e = reader.add(line);
      if (e == null) continue;
      if (e.event == 'error') throw SseException.from(e.data);
      yield e;
    }
    final last = reader.add('');
    if (last != null && last.event != 'error') yield last;
  }

  /// Base URL + dev user id, exposed for the multipart upload client.
  String get baseUrl => _baseUrl;
  Future<Map<String, String>> authHeaders() => _headers();

  List<SseEvent> _parse(http.Response resp) {
    if (resp.statusCode >= 400) {
      throw SseException('HTTP ${resp.statusCode} for ${resp.request?.url}');
    }
    final events = <SseEvent>[];
    final reader = SseReader();
    for (final line in const LineSplitter().convert(resp.body)) {
      final e = reader.add(line);
      if (e != null) events.add(e);
    }
    final last = reader.add('');
    if (last != null) events.add(last);

    final err = events.where((e) => e.event == 'error');
    if (err.isNotEmpty) throw SseException.from(err.first.data);
    return events;
  }

  void close() => _client.close();
}

/// Builds events from SSE lines, one line at a time.
class SseReader {
  String? _name;
  final _data = <String>[];

  /// The event a blank line completes, else null.
  SseEvent? add(String line) {
    if (line.isEmpty) return _flush();
    if (line.startsWith('event:')) {
      _name = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      _data.add(line.substring(5).trim());
    }
    // ':' comment / keep-alive lines are ignored.
    return null;
  }

  SseEvent? _flush() {
    if (_data.isEmpty) return null;
    final raw = _data.join('\n');
    _data.clear();
    final ev = _name ?? 'message';
    _name = null;
    Map<String, dynamic> parsed;
    try {
      final decoded = jsonDecode(raw);
      parsed = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{'value': decoded};
    } catch (_) {
      parsed = <String, dynamic>{'raw': raw};
    }
    return SseEvent(ev, parsed);
  }
}

/// A random id (uuid v4) for `event_id` / `Idempotency-Key`.
String newRequestId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

class SseException implements Exception {
  SseException(this.message, {this.code});

  /// From an `error` event's data (`message`, maybe `code`).
  factory SseException.from(Map<String, dynamic> data) => SseException(
    '${data['message'] ?? 'stream error'}',
    code: data['code'] as String?,
  );

  final String message;

  /// Machine-readable reason, e.g. `insufficient_credits`.
  final String? code;

  bool get outOfCredits => code == 'insufficient_credits';
  @override
  String toString() => 'SseException: $message';
}
