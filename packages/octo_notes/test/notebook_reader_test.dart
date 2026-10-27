import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:octo_notes/src/application/notebook_book.dart';
import 'package:octo_notes/src/application/session_providers.dart';
import 'package:octo_notes/src/data/api/notes_api_client.dart';
import 'package:octo_notes/src/data/api/octo_notes_api.dart';
import 'package:octo_notes/src/presentation/notebooks/notebook_reader_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _start = '2026-10-20T09:00:00Z';

/// One notebook, one finalized lecture: typed lines, a line of handwriting
/// read three minutes in, a formula, a recording.
http.Response _server(http.Request r) {
  final p = r.url.path;
  Map<String, dynamic>? body;
  if (p == '/v1/courses') return http.Response(jsonEncode([{'id': 'bio', 'name': 'Biology 101', 'code': 'BIO 101'}]), 200);
  if (p == '/v1/sessions') {
    body = {
      'items': [
        {'id': 's1', 'title': 'Cellular respiration', 'status': 'finalized', 'courseId': 'bio', 'startedAt': _start, 'updatedAt': _start, 'durationMs': 2892000},
      ],
    };
  } else if (p == '/v1/sessions/s1/blocks') {
    body = {
      'rev': 3,
      'blocks': [
        {'id': 'b1', 'type': 'h2', 'text': 'Glycolysis', 'position': 'a', 'audioTsMs': 0},
        {'id': 'b2', 'type': 'bulleted', 'text': 'glucose to two pyruvate', 'position': 'b', 'audioTsMs': 60000},
        {'id': 'b3', 'type': 'paragraph', 'text': 'Krebs cycle next', 'position': 'c', 'audioTsMs': 600000},
        {'id': 'b4', 'type': 'paragraph', 'text': 'gone', 'position': 'd', 'deletedAt': _start},
      ],
    };
  } else if (p == '/v1/sessions/s1/ink/pages') {
    body = {'pages': [{'id': 'p1', 'ordinal': 0}]};
  } else if (p == '/v1/ink/pages/p1/recognitions') {
    body = {
      'items': [
        {'id': 'r1', 'text': 'pyruvate to acetyl CoA', 'createdAt': '2026-10-20T09:03:00Z'},
        {'id': 'r2', 'text': r'$$E=mc^2$$', 'createdAt': '2026-10-20T09:20:00Z'},
      ],
    };
  } else if (p == '/v1/sessions/s1/recordings') {
    return http.Response(jsonEncode([{'id': 'rec1', 'state': 'assembled', 'durationMs': 2892000}]), 200);
  } else if (p == '/v1/sessions/s1/materials') {
    return http.Response('[]', 200);
  } else if (p == '/v1/final-notes') {
    return http.Response(jsonEncode([{'id': 'f1'}]), 200);
  } else if (p == '/v1/final-notes/f1') {
    body = {
      'id': 'f1',
      'content': {
        'blocks': [
          {'id': 'c1', 'type': 'h2', 'text': '1. Glycolysis'},
          {'id': 'c2', 'type': 'paragraph', 'text': 'Glucose splits into two pyruvate without oxygen.'},
        ],
      },
    };
  }
  return body == null ? http.Response('{}', 404) : http.Response(jsonEncode(body), 200);
}

OctoNotesApi _api() => OctoNotesApi(NotesApiClient(
      baseUrl: 'http://api.test',
      tokenProvider: () async => 'tok',
      httpClient: MockClient((r) async => _server(r)),
    ));

void main() {
  setUpAll(() async {
    final font = FontLoader('packages/cockpit_ui/PlusJakartaSans');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('packages/cockpit_ui/assets/fonts/PlusJakartaSans-$w.ttf'));
    }
    await font.load();
  });

  test('extras go in before the first line written after them', () {
    BookItem i(String id, int? at) => BookItem(id: id, kind: 'text', atMs: at);
    final out = merge([i('a', 0), i('b', 100), i('c', null), i('d', 300)], [i('x', 50), i('y', 250), i('z', 900)]);
    expect([for (final o in out) o.id], ['a', 'x', 'b', 'c', 'y', 'd', 'z']);
  });

  test('a lecture becomes a chapter: lines in order, handwriting by time, the clean copy, files', () async {
    final book = await loadNotebook(_api(), courseId: 'bio');
    expect(book.title, 'Biology 101');
    final c = book.chapters.single;
    expect([for (final i in c.mine) i.text], ['Glycolysis', 'glucose to two pyruvate', 'pyruvate to acetyl CoA', 'Krebs cycle next', 'E=mc^2']);
    expect(c.mine[2].kind, 'pen');
    expect(c.mine.last.kind, 'formula');
    expect(c.clean!.length, 2);
    expect(c.recordingId, 'rec1');
    expect({for (final f in book.files) f.kind}, {'text', 'clean', 'recording', 'handwriting', 'formula'});
  });

  testWidgets('contents, a chapter as written, the clean copy and files', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [octoNotesApiProvider.overrideWithValue(_api())],
      child: MaterialApp.router(
        routerConfig: GoRouter(initialLocation: '/notes/notebook', routes: [
          GoRoute(path: '/notes/notebook', builder: (_, _) => const NotebookReaderPage(courseId: 'bio')),
        ]),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Contents'), findsOneWidget);
    expect(find.text('BIO 101 · 1 lectures'), findsOneWidget);

    // A chapter from the contents: the page turns to it.
    await tester.tap(find.text('Cellular respiration'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('glucose to two pyruvate'), findsOneWidget);
    expect(find.text('pyruvate to acetyl CoA'), findsOneWidget);
    expect(find.text('gone'), findsNothing);
    expect(find.text('page 1 of 1'), findsOneWidget);

    // Turning back by dragging: past a third, the page goes over.
    await tester.drag(find.text('Glycolysis'), const Offset(300, 0));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Contents'), findsOneWidget);

    await tester.tap(find.text('Clean copy'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Cellular respiration'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Glucose splits into two pyruvate without oxygen.'), findsOneWidget);

    await tester.tap(find.text('Files'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Recordings'), findsOneWidget);
    expect(find.text('Handwriting'), findsOneWidget);
    expect(find.text('Cellular respiration — notes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the book follows the app: dark paper when the app is dark', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<Color?> deskIn(Brightness b) async {
      await tester.pumpWidget(ProviderScope(
        key: ValueKey(b),
        overrides: [octoNotesApiProvider.overrideWithValue(_api())],
        child: MaterialApp(theme: ThemeData(brightness: b), home: const NotebookReaderPage(courseId: 'bio')),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      return tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor;
    }

    final light = await deskIn(Brightness.light);
    final dark = await deskIn(Brightness.dark);
    expect(light!.computeLuminance(), greaterThan(.5));
    expect(dark!.computeLuminance(), lessThan(.1));
    expect(tester.takeException(), isNull);
  });
}
