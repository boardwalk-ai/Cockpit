import 'dart:math';

import 'package:http/http.dart' as http;

/// A random (v4) UUID — for `Idempotency-Key`s and client-chosen document ids.
String newUuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // RFC 4122 variant
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

/// POSTs with an `Idempotency-Key` — one key per logical request, reused on the
/// single automatic retry (dropped connection / 502 / 503). The backend runs a
/// keyed request at most once and replays its response to the retry, so a retry
/// never re-runs a paid AI call or creates a second document.
Future<http.Response> postIdempotent(
  http.Client client,
  Uri url, {
  required Map<String, String> headers,
  Object? body,
}) async {
  final h = {...headers, 'Idempotency-Key': newUuid()};
  try {
    final r = await client.post(url, headers: h, body: body);
    if (r.statusCode != 502 && r.statusCode != 503) return r;
  } on http.ClientException {
    // Connection dropped — retry once below with the same key.
  }
  return client.post(url, headers: h, body: body);
}

/// The message shown when the backend refuses a signed-out request.
const signInRequired = 'Sign in to use this feature.';
