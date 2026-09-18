// Verifies HttpToolsService against canned backend responses (MockClient), so
// the JSON contract with backend-rs is checked without a live server.
import 'dart:convert';

import 'package:doc_oct/src/application/http_tools_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  HttpToolsService svc(MockClient client) =>
      HttpToolsService('http://backend.test', client: client);

  test('dictionary parses DictResult', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/v1/dictionary');
      expect(req.url.queryParameters['word'], 'sample');
      return http.Response(
        jsonEncode({
          'word': 'sample',
          'phonetic': '/ˈsɑːmpəl/',
          'meanings': [
            {
              'partOfSpeech': 'noun',
              'definitions': [
                {'definition': 'a specimen', 'example': 'a free sample'}
              ]
            }
          ],
          'synonyms': ['specimen', 'example'],
          'antonyms': ['whole'],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final r = await svc(client).dictionary('sample');
    expect(r.word, 'sample');
    expect(r.meanings.single.partOfSpeech, 'noun');
    expect(r.meanings.single.definitions.single.example, 'a free sample');
    expect(r.synonyms, contains('specimen'));
  });

  test('thesaurus parses ThesResult with scores', () async {
    final client = MockClient((req) async {
      return http.Response(
        jsonEncode({
          'word': 'quick',
          'synonyms': [
            {'word': 'fast', 'score': 92},
            {'word': 'rapid', 'score': 80}
          ],
          'antonyms': [
            {'word': 'slow', 'score': 40}
          ],
        }),
        200,
      );
    });
    final r = await svc(client).thesaurus('quick');
    expect(r.synonyms.first.word, 'fast');
    expect(r.synonyms.first.score, 92);
    expect(r.antonyms.single.word, 'slow');
  });

  test('searchSources parses a Source list', () async {
    final client = MockClient((req) async {
      expect(req.method, 'POST');
      expect(jsonDecode(req.body)['topic'], 'photosynthesis');
      return http.Response(
        jsonEncode([
          {
            'url': 'https://example.com/a',
            'title': 'A',
            'author': 'Smith, J.',
            'publishedYear': '2020',
            'publisher': 'Example',
            'fullContent': 'body text',
          }
        ]),
        200,
      );
    });
    final r = await svc(client).searchSources('photosynthesis');
    expect(r.single.title, 'A');
    expect(r.single.publishedYear, '2020');
    expect(r.single.fullContent, 'body text');
  });

  test('surfaces backend {error} on failure', () async {
    final client = MockClient((req) async {
      return http.Response(
        jsonEncode({'error': 'source search needs OPENROUTER_API_KEY'}),
        503,
      );
    });
    expect(
      () => svc(client).searchSources('x'),
      throwsA(isA<ToolsException>().having(
          (e) => e.message, 'message', contains('OPENROUTER_API_KEY'))),
    );
  });
}
