import 'package:doc_oct/src/application/idempotent_post.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('newUuid is a v4 UUID and unique', () {
    final a = newUuid(), b = newUuid();
    expect(
      a,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(a, isNot(b));
  });

  test('a 502 is retried once with the SAME Idempotency-Key', () async {
    final keys = <String?>[];
    final client = MockClient((req) async {
      keys.add(req.headers['Idempotency-Key']);
      return http.Response('{}', keys.length == 1 ? 502 : 200);
    });
    final r = await postIdempotent(
      client,
      Uri.parse('https://api.test/v1/x'),
      headers: const {},
      body: '{}',
    );
    expect(r.statusCode, 200);
    expect(keys, hasLength(2));
    expect(keys[0], isNotNull);
    expect(keys[1], keys[0]);
  });

  test('success and client errors are not retried', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      return http.Response('{"error":"nope"}', 401);
    });
    final r = await postIdempotent(
      client,
      Uri.parse('https://api.test/v1/x'),
      headers: const {},
    );
    expect(r.statusCode, 401);
    expect(calls, 1);
  });
}
