import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/lookup_result.dart';
import '../domain/source.dart';
import 'idempotent_post.dart';
import 'tools_service.dart';

/// The real [ToolsService] — talks to our Rust backend (`backend-rs`), which is
/// the ONLY thing that reaches the external dictionary / thesaurus / humanizer /
/// scraper + AI APIs. The frontend never calls those directly.
///
/// Base URL comes from `--dart-define=DOC_OCT_API=...`; when it is empty the app
/// falls back to [MockToolsService] (see [toolsService]).
class HttpToolsService implements ToolsService {
  HttpToolsService(this.baseUrl, {http.Client? client, this.token})
      : _client = client ?? http.Client();

  /// e.g. `http://localhost:8787` in dev or `https://octopilotai.app/api` live.
  final String baseUrl;
  final http.Client _client;

  /// Supplies the Firebase ID token for authed requests (may be null).
  final Future<String?> Function()? token;

  @override
  bool get isMock => false;

  Uri _u(String path, [Map<String, String>? q]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: q);

  /// Request headers, adding `Authorization: Bearer …` when a token is available.
  Future<Map<String, String>> _headers([Map<String, String>? extra]) async {
    final h = <String, String>{if (extra != null) ...extra};
    final t = await token?.call();
    if (t != null && t.isNotEmpty) h['Authorization'] = 'Bearer $t';
    return h;
  }

  Map<String, dynamic> _decodeObject(http.Response r) {
    if (r.statusCode >= 400) {
      throw ToolsException(_errorMessage(r));
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  String _errorMessage(http.Response r) {
    if (r.statusCode == 401) return signInRequired;
    try {
      final body = jsonDecode(r.body);
      if (body is Map && body['error'] is String) return body['error'] as String;
    } catch (_) {}
    return 'Request failed (${r.statusCode})';
  }

  @override
  Future<DictResult> dictionary(String word) async {
    final r = await _client.get(_u('/v1/dictionary', {'word': word.trim()}),
        headers: await _headers());
    return DictResult.fromJson(_decodeObject(r));
  }

  @override
  Future<ThesResult> thesaurus(String word) async {
    final r = await _client.get(_u('/v1/thesaurus', {'word': word.trim()}),
        headers: await _headers());
    return ThesResult.fromJson(_decodeObject(r));
  }

  @override
  Future<String> paraphrase(String text) async {
    final r = await postIdempotent(
      _client,
      _u('/v1/paraphrase'),
      headers: await _headers({'Content-Type': 'application/json'}),
      body: jsonEncode({'text': text}),
    );
    return (_decodeObject(r)['text'] ?? '') as String;
  }

  @override
  Future<List<Source>> searchSources(String query) async {
    final r = await postIdempotent(
      _client,
      _u('/v1/sources/search'),
      headers: await _headers({'Content-Type': 'application/json'}),
      body: jsonEncode({'topic': query.trim()}),
    );
    if (r.statusCode >= 400) throw ToolsException(_errorMessage(r));
    final list = jsonDecode(r.body) as List;
    return list
        .map((s) => Source.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  /// Scrapes a single page into a [Source] (backend `/v1/scrape`). Used by the
  /// Auto mode and the source modal.
  Future<Source> scrape(String url) async {
    final r = await _client.get(_u('/v1/scrape', {'url': url.trim()}),
        headers: await _headers());
    return Source.fromJson(_decodeObject(r));
  }
}

/// Thrown when the backend returns an error status; carries the message the
/// backend put in `{"error": ...}` so the UI can surface it.
class ToolsException implements Exception {
  ToolsException(this.message);
  final String message;
  @override
  String toString() => message;
}
