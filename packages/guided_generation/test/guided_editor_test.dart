import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guided_generation/src/data/guided_generation_repository.dart';
import 'package:guided_generation/src/formatters/citation_formatter.dart';
import 'package:guided_generation/src/presentation/editor/editor_page.dart';

void main() {
  test('thread parsing restores editor delta, sources, and citation style', () {
    final thread = GuidedEditorThread.fromJson({
      'id': 'thread-1',
      'title': 'Saved draft',
      'essay': 'Saved draft\nBody',
      'citationStyle': 'Harvard',
      'runState': {
        'generation': {'complete': true},
        'editor': {
          'delta': [
            {'insert': 'Saved draft\nBody\n'},
          ],
          'sources': [
            {
              'id': 'source-1',
              'title': 'A source',
              'author': 'Rivera, Alex',
              'year': '2026',
            },
          ],
        },
      },
    });

    expect(thread.id, 'thread-1');
    expect(thread.citationStyle, CitationStyle.harvard);
    expect(thread.delta, isNotEmpty);
    expect(thread.sources.single.title, 'A source');
    expect(thread.runState['generation'], {'complete': true});
  });

  testWidgets('shows loading, restores a saved draft, and saves edits', (
    tester,
  ) async {
    final load = Completer<GuidedEditorThread?>();
    final repository = _FakeRepository(load.future);

    await tester.pumpWidget(_app(repository));
    expect(find.byKey(const Key('guided-editor-loading')), findsOneWidget);

    load.complete(_thread());
    await tester.pumpAndSettle();

    final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
    expect(editor.controller.document.toPlainText(), contains('Saved draft'));
    expect(find.textContaining('example.com/ai-education'), findsNothing);

    await tester.tap(find.byKey(const Key('guided-editor-save')));
    await tester.pumpAndSettle();

    expect(repository.saveCalls, 1);
    expect(repository.savedThreadId, 'thread-1');
    expect(repository.savedText, contains('Saved draft'));
    expect(repository.savedDelta, isNotEmpty);
  });

  testWidgets('shows a retryable error when loading fails', (tester) async {
    final repository = _FakeRepository.failing();

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('guided-editor-error')), findsOneWidget);
    expect(find.byKey(const Key('guided-editor-retry')), findsOneWidget);
    expect(find.textContaining('offline'), findsOneWidget);
  });
}

Widget _app(GuidedGenerationRepository repository) {
  return MaterialApp(
    localizationsDelegates: const [FlutterQuillLocalizations.delegate],
    home: GuidedEditorPage(repository: repository),
  );
}

GuidedEditorThread _thread() {
  return const GuidedEditorThread(
    id: 'thread-1',
    title: 'Saved draft',
    plainText: 'Saved draft\n\nA persisted paragraph.',
    citationStyle: CitationStyle.apa,
    sources: [],
    runState: {},
    delta: [
      {'insert': 'Saved draft\n\nA persisted paragraph.\n'},
    ],
  );
}

class _FakeRepository implements GuidedGenerationRepository {
  _FakeRepository(this.loadResult) : failLoad = false;

  _FakeRepository.failing()
    : loadResult = Future<GuidedEditorThread?>.value(),
      failLoad = true;

  final Future<GuidedEditorThread?> loadResult;
  final bool failLoad;
  int saveCalls = 0;
  String? savedThreadId;
  String? savedText;
  List<dynamic>? savedDelta;

  @override
  Future<GuidedEditorThread?> loadEditor({String? threadId}) async {
    if (failLoad) throw Exception('offline');
    return loadResult;
  }

  @override
  Future<GuidedEditorThread> saveEditor({
    String? threadId,
    required String title,
    required String plainText,
    required int wordCount,
    required CitationStyle citationStyle,
    required List<dynamic> delta,
    required List<CitationSource> sources,
    Map<String, dynamic> runState = const {},
  }) async {
    saveCalls++;
    savedThreadId = threadId;
    savedText = plainText;
    savedDelta = delta;
    return _thread();
  }
}
