import 'dart:convert';
import 'dart:io';

import 'package:cockpit_core/cockpit_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guided_generation/src/data/guided_generation_repository.dart';
import 'package:guided_generation/src/formatters/citation_formatter.dart';

void main() {
  late HttpServer server;
  late ApiGuidedGenerationRepository repository;
  Map<String, dynamic>? patchBody;

  setUp(() async {
    patchBody = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    repository = ApiGuidedGenerationRepository(
      ApiClient(
        AppConfig(
          flavor: AppFlavor.dev,
          apiBaseUrl: 'http://${server.address.host}:${server.port}',
        ),
      ),
    );

    server.listen((request) async {
      final path = request.uri.path;
      request.response.headers.contentType = ContentType.json;

      if (request.method == 'GET' && path.endsWith('/threads')) {
        request.response.write(
          jsonEncode([
            {'id': 'thread-1'},
          ]),
        );
      } else if (request.method == 'GET' && path.endsWith('/thread-1')) {
        request.response.write(jsonEncode(_threadJson));
      } else if (request.method == 'POST' && path.endsWith('/threads')) {
        await utf8.decoder.bind(request).join();
        request.response.statusCode = HttpStatus.created;
        request.response.write(jsonEncode(_threadJson));
      } else if (request.method == 'PATCH' && path.endsWith('/thread-1')) {
        patchBody =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        request.response.write(
          jsonEncode({..._threadJson, ...patchBody!, 'id': 'thread-1'}),
        );
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(jsonEncode({'error': 'not found'}));
      }
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  test('loads the latest thread through the Go API contract', () async {
    final thread = await repository.loadEditor();

    expect(thread, isNotNull);
    expect(thread!.id, 'thread-1');
    expect(thread.plainText, contains('Persisted body'));
    expect(thread.citationStyle, CitationStyle.mla);
  });

  test(
    'creates and patches a new editor thread with rich-text state',
    () async {
      final thread = await repository.saveEditor(
        title: 'New draft',
        plainText: 'New draft\nBody',
        wordCount: 3,
        citationStyle: CitationStyle.chicago,
        delta: const [
          {'insert': 'New draft\nBody\n'},
        ],
        sources: const [
          CitationSource(id: 's1', title: 'Source one', year: '2026'),
        ],
        runState: const {
          'generation': {'complete': true},
        },
      );

      expect(thread.id, 'thread-1');
      expect(patchBody!['essay'], 'New draft\nBody');
      expect(patchBody!['citationStyle'], 'Chicago');
      expect(patchBody!['runState']['generation'], {'complete': true});
      expect(patchBody!['runState']['editor']['sources'], hasLength(1));
      expect(patchBody!['runState']['editor']['delta'], isNotEmpty);
    },
  );
}

const _threadJson = <String, dynamic>{
  'id': 'thread-1',
  'title': 'Persisted draft',
  'essay': 'Persisted draft\nPersisted body',
  'citationStyle': 'MLA',
  'runState': <String, dynamic>{},
};
