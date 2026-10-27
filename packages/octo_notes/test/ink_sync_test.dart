import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:octo_notes/src/application/ink_sync.dart';
import 'package:octo_notes/src/data/api/notes_api_client.dart';
import 'package:octo_notes/src/data/api/octo_notes_api.dart';
import 'package:octo_notes/src/domain/ink_controller.dart';
import 'package:octo_notes/src/domain/ink_models.dart';

Stroke _stroke(InkController ink, double y) => Stroke(
      id: ink.newStrokeId(),
      tool: InkTool.pen,
      points: [Offset(10, y), Offset(40, y + 5), Offset(70, y)],
      pressures: const [1, 0.8, 1],
      color: const Color(0xFF16213E),
      width: 2,
      pageId: ink.page.id,
    );

void main() {
  test('points survive the v1 encoding', () {
    final pts = [const Offset(1.5, 2), const Offset(300, 400.25)];
    final back = decodePoints(encodePoints(pts, const [0.5, 1]))!;
    expect(back.$1, pts);
    expect(back.$2, [0.5, 1]);
    expect(decodePoints(base64Encode([2, 0, 0, 0, 0])), isNull, reason: 'only format v1');
  });

  test('sends adds, moves and erases; undo of an erase comes back under a new id; lines are read and kept', () async {
    final calls = <String, List<dynamic>>{};
    final api = OctoNotesApi(NotesApiClient(
      baseUrl: 'http://api.test',
      tokenProvider: () async => 'tok',
      httpClient: MockClient((r) async {
        final path = r.url.path;
        final body = r.body.isEmpty ? null : jsonDecode(r.body);
        (calls[path] ??= []).add(body);
        if (path.endsWith('/ink/pages') && r.method == 'GET') return http.Response(jsonEncode({'pages': []}), 200);
        if (path.endsWith('/ink/pages')) return http.Response(jsonEncode({'id': body['id']}), 201);
        if (path.endsWith('/ops')) {
          return http.Response(jsonEncode({
            'rev': 1,
            'results': [
              for (final o in body['ops'] as List)
                {'clientOpId': o['clientOpId'], 'status': 'applied', 'stroke': {'id': o['strokeId'], 'revision': 1}},
            ],
          }), 200);
        }
        if (path.endsWith('/recognitions')) return http.Response(jsonEncode({'id': 'r1'}), 201);
        return http.Response('{}', 404);
      }),
    ));
    final ink = InkController(newId: OctoNotesApi.newId);
    final read = <int>[];
    final sync = InkSync(
      api: api,
      sessionId: 's1',
      ink: ink,
      pause: const Duration(milliseconds: 20),
      read: (strokes) async {
        read.add(strokes.length);
        return (text: 'ATP synthase', confidence: 0.9);
      },
    );
    await sync.load();
    final page = ink.page.id;

    final a = _stroke(ink, 20), b = _stroke(ink, 80);
    ink
      ..addStroke(a)
      ..addStroke(b);
    await sync.flush();
    final ops = calls['/v1/ink/pages/$page/ops']!.last['ops'] as List;
    expect([for (final o in ops) o['op']], ['add', 'add']);
    expect(calls['/v1/sessions/s1/ink/pages']!.whereType<Map>().single['id'], page, reason: 'the first page is created');

    // The pen stopped: both strokes are read as one line, then saved.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(read, [2]);
    expect(sync.linesOf(ink.page).single.text, 'ATP synthase');
    expect((calls['/v1/ink/pages/$page/recognitions']!.single as Map)['strokeIds'], [a.id, b.id]);

    // Erase one, then undo: an erase goes out, then the stroke again as new.
    ink.beginEdit();
    ink.eraseAt(const Offset(10, 20));
    await sync.flush();
    expect((calls['/v1/ink/pages/$page/ops']!.last['ops'] as List).single['op'], 'erase');
    ink.undo();
    await sync.flush();
    final back = (calls['/v1/ink/pages/$page/ops']!.last['ops'] as List).single as Map;
    expect(back['op'], 'add');
    expect(back['strokeId'], isNot(a.id));
    expect(read, [2], reason: 'ink already read is not read again');
    sync.dispose();
  });

  test('a formula replaces the text read from the same ink', () async {
    final api = OctoNotesApi(NotesApiClient(
      baseUrl: 'http://api.test',
      tokenProvider: () async => 'tok',
      httpClient: MockClient((r) async {
        final path = r.url.path;
        if (path.endsWith('/ink/pages') && r.method == 'GET') return http.Response(jsonEncode({'pages': []}), 200);
        if (path.endsWith('/ink/pages')) return http.Response('{}', 201);
        if (path.endsWith('/ops')) return http.Response(jsonEncode({'rev': 1, 'results': []}), 200);
        if (path.endsWith('/recognitions')) return http.Response(jsonEncode({'id': 'r1'}), 201);
        if (path.endsWith('/formula')) {
          return http.Response(jsonEncode({'id': 'f1', 'text': r'$$E=mc^2$$', 'latex': 'E=mc^2'}), 201);
        }
        return http.Response('{}', 404);
      }),
    ));
    final ink = InkController(newId: OctoNotesApi.newId);
    final sync = InkSync(api: api, sessionId: 's1', ink: ink, pause: const Duration(milliseconds: 10), read: (_) async => (text: 'E=mc', confidence: 0.4));
    await sync.load();
    final a = _stroke(ink, 20);
    ink.addStroke(a);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(sync.linesOf(ink.page).single.text, 'E=mc');
    expect(await sync.readFormula([a]), 'E=mc^2');
    expect([for (final l in sync.linesOf(ink.page)) l.text], [r'$$E=mc^2$$']);
    sync.dispose();
  });
}
