import 'dart:convert';

import 'package:doc_oct/src/application/hein_service.dart';
import 'package:doc_oct/src/domain/hein_analysis.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('HttpHeinService posts instructions and parses Hein JSON', () async {
    final client = MockClient((req) async {
      expect(req.method, 'POST');
      expect(req.url.path, '/hein/analyze');
      expect(jsonDecode(req.body)['instructions'], 'Climate policy');
      return http.Response(
        jsonEncode({
          'analysis': 'Argue a policy position.',
          'essayTopic': 'Climate policy',
          'essayType': 'Argumentative',
          'scope': 'US federal',
          'structure': 'Intro · body · conclusion',
        }),
        200,
      );
    });
    final r = await HttpHeinService('http://backend.test', client: client)
        .analyze(instructions: 'Climate policy');
    expect(r, isA<HeinAnalysis>());
    expect(r.essayTopic, 'Climate policy');
    expect(r.essayType, 'Argumentative');
    expect(r.analysis, contains('policy'));
  });

  test('HttpHeinService surfaces backend error', () async {
    final client = MockClient((req) async {
      return http.Response(jsonEncode({'error': 'Missing instructions'}), 400);
    });
    expect(
      () => HttpHeinService('http://backend.test', client: client)
          .analyze(instructions: ''),
      throwsA(isA<Exception>()),
    );
  });
}
