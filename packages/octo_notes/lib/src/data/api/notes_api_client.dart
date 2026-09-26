import 'dart:convert';

import 'package:http/http.dart' as http;

/// Error from `octonotes-api`: `{ "error": "...", "code": "..." }`.
class NotesApiException implements Exception {
  const NotesApiException(this.statusCode, this.message, {this.code});

  final int statusCode;
  final String message;

  /// Machine-readable reason, e.g. `insufficient_credits`.
  final String? code;

  @override
  String toString() => 'NotesApiException($statusCode, $message${code == null ? '' : ', $code'})';
}

/// Thin JSON client for `octonotes-api`. Attaches the Firebase ID token as
/// `Authorization: Bearer` when signed in.
class NotesApiClient {
  NotesApiClient({
    required this.baseUrl,
    required this.tokenProvider,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final Future<String?> Function() tokenProvider;
  final http.Client _http;

  Future<Map<String, dynamic>> getJson(String path) async {
    final res = await _http.get(_uri(path), headers: await _headers());
    return _decode(res);
  }

  void close() => _http.close();

  Uri _uri(String path) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$base$path');
  }

  Future<Map<String, String>> _headers() async {
    final token = await tokenProvider();
    return {
      'accept': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
    };
  }

  Map<String, dynamic> _decode(http.Response res) {
    final body = res.body.isEmpty ? const <String, dynamic>{} : jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body as Map<String, dynamic>;
    }
    final map = body is Map<String, dynamic> ? body : const <String, dynamic>{};
    throw NotesApiException(
      res.statusCode,
      (map['error'] as String?) ?? 'Request failed (${res.statusCode})',
      code: map['code'] as String?,
    );
  }
}
