import 'dart:convert';

import 'package:doc_oct/src/application/lily_service.dart';
import 'package:doc_oct/src/domain/hein_analysis.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const analysis = HeinAnalysis(
    analysis: 'Argue a claim.',
    essayTopic: 'Social media',
    essayType: 'Argumentative',
    scope: 'teens',
    structure: '5-paragraph',
  );

  test('HttpLilyService posts auto mode with Hein analysis', () async {
    final client = MockClient((req) async {
      expect(req.method, 'POST');
      expect(req.url.path, '/lily/generate');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body['mode'], 'auto');
      expect(body['count'], 5);
      expect(body['bullets'], true);
      expect(body['essayTopic'], 'Social media');
      expect(body['analysis'], 'Argue a claim.');
      return http.Response(
        jsonEncode({
          'outlines': [
            {
              'type': 'Introduction',
              'title': 'Hook',
              'description': '',
              'bullets': ['context', 'thesis'],
            },
            {
              'type': 'Conclusion',
              'title': 'Close',
              'bullets': ['restate'],
            },
          ],
        }),
        200,
      );
    });
    final r = await HttpLilyService('http://backend.test', client: client)
        .generate(mode: LilyMode.auto, analysis: analysis);
    expect(r, hasLength(2));
    expect(r.first.type, 'Introduction');
    expect(r.first.bullets, ['context', 'thesis']);
  });

  test('HttpLilyService sends build prompt and type', () async {
    final client = MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body['mode'], 'build');
      expect(body['requestedType'], 'Body Paragraph');
      expect(body['customTitle'], 'algorithmic feeds');
      expect(body.containsKey('count'), isFalse);
      return http.Response(
        jsonEncode({
          'outlines': [
            {
              'type': 'Body Paragraph',
              'title': 'Feeds',
              'bullets': ['echo chambers'],
            },
          ],
        }),
        200,
      );
    });
    final r = await HttpLilyService('http://backend.test', client: client)
        .generate(
      mode: LilyMode.build,
      analysis: analysis,
      requestedType: 'Body Paragraph',
      customTitle: 'algorithmic feeds',
    );
    expect(r.single.title, 'Feeds');
  });

  test('HttpLilyService surfaces backend error', () async {
    final client = MockClient((req) async {
      return http.Response(jsonEncode({'error': 'Missing topic'}), 400);
    });
    expect(
      () => HttpLilyService('http://backend.test', client: client)
          .generate(mode: LilyMode.single, requestedType: 'Introduction'),
      throwsA(isA<Exception>()),
    );
  });
}
