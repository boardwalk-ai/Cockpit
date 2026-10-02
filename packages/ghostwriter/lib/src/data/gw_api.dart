import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'sse.dart';

/// Supplies the signed-in user's Firebase ID token, or null when signed out.
typedef IdTokenProvider = Future<String?> Function();

/// A request the API refused. [code] is the machine-readable reason
/// (`run_active`, `stale_rev`, ...) when the server sent one.
class GwApiException implements Exception {
  const GwApiException(this.status, this.message, {this.code, this.details});

  final int status;
  final String message;
  final String? code;
  final Map<String, dynamic>? details;

  @override
  String toString() =>
      'GwApiException($status${code == null ? '' : ' $code'}): $message';
}

/// Client for `ghostwriter-api` (the Rust service). See
/// `docs/ghostwriter/CONTRACT.md` for every endpoint and event.
class GwApi {
  GwApi({String? baseUrl, http.Client? client, this.idToken, String? devUserId})
    : baseUrl = baseUrl ?? defaultBaseUrl,
      devUserId = devUserId ?? defaultDevUserId,
      _client = client ?? http.Client();

  /// `--dart-define=GHOSTWRITER_API_URL=https://...`; otherwise the local
  /// dev server (10.0.2.2 from the Android emulator).
  static String get defaultBaseUrl {
    const configured = String.fromEnvironment('GHOSTWRITER_API_URL');
    if (configured.isNotEmpty) return configured;
    final emulator = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    return emulator ? 'http://10.0.2.2:8791' : 'http://127.0.0.1:8791';
  }

  /// Who to be against a dev server with auth off (`--dart-define=GW_DEV_USER`).
  static const String defaultDevUserId = String.fromEnvironment(
    'GW_DEV_USER',
    defaultValue: 'dev-user',
  );

  final String baseUrl;
  final String devUserId;
  final IdTokenProvider? idToken;
  final http.Client _client;

  // ── Account ──────────────────────────────────────────────────────────────

  /// `{ id, name, email, photoUrl, octoCredits }`
  Future<Map<String, dynamic>> me() => _json('GET', '/v1/me');

  // ── Projects and folders ─────────────────────────────────────────────────

  /// `{ projects: [...], folders: [...] }`, newest project first.
  Future<Map<String, dynamic>> projects() => _json('GET', '/v1/projects');

  /// One project, with `activeRunId` and `lastRunId`.
  Future<Map<String, dynamic>> project(String id) =>
      _json('GET', '/v1/projects/$id');

  /// Creates the project, or updates the fields given. Pass [unfile] to take
  /// it out of its folder.
  Future<Map<String, dynamic>> putProject(
    String id, {
    String? title,
    String? instruction,
    String? folderId,
    bool unfile = false,
  }) => _json('PUT', '/v1/projects/$id', {
    'title': ?title,
    'instruction': ?instruction,
    if (folderId != null)
      'folderId': folderId
    else if (unfile)
      'folderId': null,
  });

  Future<void> deleteProject(String id) => _json('DELETE', '/v1/projects/$id');

  Future<Map<String, dynamic>> putFolder(String id, String name) =>
      _json('PUT', '/v1/folders/$id', {'name': name});

  Future<void> deleteFolder(String id) => _json('DELETE', '/v1/folders/$id');

  // ── Runs ─────────────────────────────────────────────────────────────────

  /// Starts a run. Sending the same [runId] again is a no-op.
  Future<void> startRun(String projectId, String runId, String instruction) =>
      _json('POST', '/v1/projects/$projectId/runs', {
        'runId': runId,
        'instruction': instruction,
      });

  /// `{ status, pendingQuestion, lastSeq, error }`
  Future<Map<String, dynamic>> run(String runId) =>
      _json('GET', '/v1/runs/$runId');

  /// The run's events after [sinceSeq], then live ones until the run ends.
  /// The stream closes when the run is over or the connection drops; the
  /// caller reconnects with the last `seq` it saw.
  Stream<Map<String, dynamic>> runEvents(String runId, {int sinceSeq = 0}) =>
      _events('/v1/runs/$runId/events?sinceSeq=$sinceSeq');

  Future<void> answer(String runId, String field, Object value) =>
      _json('POST', '/v1/runs/$runId/answer', {'field': field, 'value': value});

  Future<void> message(String runId, String text) =>
      _json('POST', '/v1/runs/$runId/message', {'text': text});

  Future<void> cancel(String runId) =>
      _json('POST', '/v1/runs/$runId/cancel', {});

  // ── Document ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> document(String projectId) =>
      _json('GET', '/v1/projects/$projectId/document');

  /// The document for an open editor: `snapshot`, `delta`, `committed`,
  /// `unlocked` (CONTRACT.md 7.1). Stays open until cancelled.
  Stream<Map<String, dynamic>> documentEvents(String projectId) =>
      _events('/v1/projects/$projectId/document/stream');

  // ── Plumbing ─────────────────────────────────────────────────────────────

  Future<Map<String, String>> _headers({bool json = false}) async {
    final token = await idToken?.call();
    return {
      if (json) 'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty)
        'Authorization': 'Bearer $token'
      else
        'X-User-Id': devUserId,
    };
  }

  Future<Map<String, dynamic>> _json(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers.addAll(await _headers(json: body != null));
    if (body != null) request.body = jsonEncode(body);

    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    if (response.statusCode >= 400) {
      throw _error(response.statusCode, response.body);
    }
    if (response.body.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  /// An SSE endpoint as a stream of JSON events. Cancelling the
  /// subscription closes the connection at once, even mid-connect.
  Stream<Map<String, dynamic>> _events(String path) {
    final abort = Completer<void>();
    StreamSubscription<SseFrame>? frames;
    late final StreamController<Map<String, dynamic>> out;

    void fail(Object error, [StackTrace? stack]) {
      if (abort.isCompleted || out.isClosed) return;
      out.addError(error, stack);
      out.close();
    }

    out = StreamController(
      onListen: () async {
        try {
          final request =
              http.AbortableRequest(
                  'GET',
                  Uri.parse('$baseUrl$path'),
                  abortTrigger: abort.future,
                )
                ..headers.addAll({
                  ...await _headers(),
                  'Accept': 'text/event-stream',
                });
          final response = await _client.send(request);
          if (abort.isCompleted) {
            unawaited(response.stream.listen(null).cancel());
            return;
          }
          if (response.statusCode >= 400) {
            final body = await response.stream.bytesToString();
            return fail(_error(response.statusCode, body));
          }
          frames = parseSse(response.stream).listen(
            (frame) {
              try {
                final decoded = jsonDecode(frame.data);
                if (decoded is Map<String, dynamic>) out.add(decoded);
              } on FormatException {
                // Not an event we understand; skip it.
              }
            },
            onError: fail,
            onDone: () {
              if (!out.isClosed) out.close();
            },
          );
        } catch (error, stack) {
          fail(error, stack);
        }
      },
      onCancel: () async {
        if (!abort.isCompleted) abort.complete();
        await frames?.cancel();
      },
    );
    return out.stream;
  }

  static GwApiException _error(int status, String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return GwApiException(
          status,
          decoded['error']?.toString() ?? 'Request failed ($status)',
          code: decoded['code']?.toString(),
          details: decoded['details'] is Map<String, dynamic>
              ? decoded['details'] as Map<String, dynamic>
              : null,
        );
      }
    } on FormatException {
      // Not JSON: fall through.
    }
    return GwApiException(
      status,
      body.isEmpty ? 'Request failed ($status)' : body,
    );
  }

  void close() => _client.close();
}
