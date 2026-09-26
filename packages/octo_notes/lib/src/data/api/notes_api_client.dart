import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Error from `octonotes-api`: `{ "error": "...", "code": "...", "details": {...} }`.
class NotesApiException implements Exception {
  const NotesApiException(this.statusCode, this.message, {this.code, this.details});

  final int statusCode;
  final String message;

  /// Machine-readable reason, e.g. `insufficient_credits`, `other_device_recording`.
  final String? code;

  /// Extra context, e.g. `{needed, balance}` for 402.
  final Map<String, dynamic>? details;

  bool get isInsufficientCredits => code == 'insufficient_credits';

  @override
  String toString() => 'NotesApiException($statusCode, $message${code == null ? '' : ', $code'})';
}

/// One Server-Sent Event from an AI/progress stream.
class SseEvent {
  const SseEvent(this.event, this.data);
  final String event;
  final Map<String, dynamic> data;
}

/// Thin JSON client for `octonotes-api`. Attaches the Firebase ID token as
/// `Authorization: Bearer` when signed in, plus `X-Client-Version`.
class NotesApiClient {
  NotesApiClient({
    required this.baseUrl,
    required this.tokenProvider,
    http.Client? httpClient,
    this.clientVersion = 'octonotes-flutter/1',
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final Future<String?> Function() tokenProvider;
  final String clientVersion;
  final http.Client _http;

  Future<Map<String, dynamic>> getJson(String path) async =>
      _asMap(await _send('GET', path));

  Future<List<dynamic>> getList(String path) async => (await _send('GET', path)) as List<dynamic>;

  Future<Map<String, dynamic>> postJson(String path, [Object? body, Map<String, String>? headers]) async =>
      _asMap(await _send('POST', path, body: body ?? const {}, headers: headers));

  Future<dynamic> post(String path, [Object? body, Map<String, String>? headers]) =>
      _send('POST', path, body: body ?? const {}, headers: headers);

  Future<Map<String, dynamic>> patchJson(String path, Object body) async =>
      _asMap(await _send('PATCH', path, body: body));

  Future<dynamic> put(String path, Object body) => _send('PUT', path, body: body);

  Future<void> delete(String path) async => _send('DELETE', path);

  /// Raw upload (audio chunks).
  Future<Map<String, dynamic>> putBytes(String path, List<int> bytes, String contentType,
      {Map<String, String>? headers}) async {
    final res = await _http.put(_uri(path),
        headers: {...await _headers(), 'content-type': contentType, ...?headers}, body: bytes);
    return _asMap(_decode(res));
  }

  /// POSTs and yields SSE events until the stream ends. An `error` event is
  /// yielded like any other (the caller decides); HTTP errors throw.
  Stream<SseEvent> sse(String path, [Object? body]) async* {
    final req = http.Request('POST', _uri(path))
      ..headers.addAll({...await _headers(), 'content-type': 'application/json', 'accept': 'text/event-stream'})
      ..body = jsonEncode(body ?? const {});
    final res = await _http.send(req);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final text = await res.stream.bytesToString();
      _decode(http.Response(text, res.statusCode));
    }
    yield* parseSse(res.stream.transform(utf8.decoder));
  }

  /// GET variant (progress streams).
  Stream<SseEvent> sseGet(String path) async* {
    final req = http.Request('GET', _uri(path))..headers.addAll({...await _headers(), 'accept': 'text/event-stream'});
    final res = await _http.send(req);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final text = await res.stream.bytesToString();
      _decode(http.Response(text, res.statusCode));
    }
    yield* parseSse(res.stream.transform(utf8.decoder));
  }

  void close() => _http.close();

  Uri uri(String path) => _uri(path);

  Uri _uri(String path) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$base$path');
  }

  Future<Map<String, String>> _headers() async {
    final token = await tokenProvider();
    return {
      'accept': 'application/json',
      'x-client-version': clientVersion,
      if (token != null) 'authorization': 'Bearer $token',
    };
  }

  Future<dynamic> _send(String method, String path, {Object? body, Map<String, String>? headers}) async {
    final req = http.Request(method, _uri(path))..headers.addAll({...await _headers(), ...?headers});
    if (body != null) {
      req.headers['content-type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    return _decode(await http.Response.fromStream(await _http.send(req)));
  }

  static Map<String, dynamic> _asMap(dynamic v) => v is Map<String, dynamic> ? v : const <String, dynamic>{};

  dynamic _decode(http.Response res) {
    final body = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    final map = body is Map<String, dynamic> ? body : const <String, dynamic>{};
    throw NotesApiException(
      res.statusCode,
      (map['error'] as String?) ?? 'Request failed (${res.statusCode})',
      code: map['code'] as String?,
      details: map['details'] as Map<String, dynamic>?,
    );
  }
}

/// Parses a `text/event-stream` into events (`event:` + `data:` lines).
Stream<SseEvent> parseSse(Stream<String> chunks) async* {
  var buffer = '';
  await for (final chunk in chunks) {
    buffer += chunk.replaceAll('\r\n', '\n');
    while (true) {
      final i = buffer.indexOf('\n\n');
      if (i < 0) break;
      final frame = buffer.substring(0, i);
      buffer = buffer.substring(i + 2);
      String? event;
      final data = StringBuffer();
      for (final line in frame.split('\n')) {
        if (line.startsWith('event:')) event = line.substring(6).trim();
        if (line.startsWith('data:')) data.write(line.substring(5).trimLeft());
      }
      if (event == null) continue;
      final decoded = data.isEmpty ? null : jsonDecode(data.toString());
      yield SseEvent(event, decoded is Map<String, dynamic> ? decoded : {'value': decoded});
    }
  }
}
