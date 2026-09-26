import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:octo_notes/src/data/api/notes_api_client.dart';
import 'package:octo_notes/src/data/api/octo_notes_api.dart';
import 'package:octo_notes/src/data/sync/block_sync.dart';
import 'package:octo_notes/src/domain/notes_session.dart';

NotesApiClient client(Future<http.Response> Function(http.Request) handler) => NotesApiClient(
      baseUrl: 'http://api.test',
      tokenProvider: () async => 'tok',
      httpClient: MockClient(handler),
    );

void main() {
  test('SSE frames parse across chunk boundaries', () async {
    final chunks = Stream.fromIterable([
      'event: delta\ndata: {"text":"Gly',
      'colysis"}\n\nevent: done\r\ndata: {"runId":"r1","creditsCharged":2}\r\n\r\n',
    ]);
    final events = await parseSse(chunks).toList();
    expect(events.map((e) => e.event), ['delta', 'done']);
    expect(events[0].data['text'], 'Glycolysis');
    expect(events[1].data['creditsCharged'], 2);
  });

  test('errors carry code and details (402)', () async {
    final api = OctoNotesApi(client((_) async => http.Response(
        jsonEncode({'error': 'costs 500', 'code': 'insufficient_credits', 'details': {'needed': 500, 'balance': 40}}), 402)));
    await expectLater(
      api.organizePreview('s1'),
      throwsA(isA<NotesApiException>()
          .having((e) => e.isInsufficientCredits, 'insufficient', true)
          .having((e) => e.details?['needed'], 'needed', 500)),
    );
  });

  test('home parses the API contract', () async {
    final api = OctoNotesApi(client((r) async {
      expect(r.url.path, '/v1/home');
      expect(r.headers['authorization'], 'Bearer tok');
      return http.Response(jsonEncode({
        'live': [],
        'continue': [
          {'id': 'a', 'title': 'Glycolysis', 'status': 'ended', 'workspaceMode': 'both', 'updatedAt': '2026-09-26T10:00:00Z'}
        ],
        'recent': [],
        'processing': [],
        'recommended': [{'finalNotesId': 'f1', 'readyTopics': 2}],
      }), 200);
    }));
    final HomeData home = await api.home();
    expect(home.continueSessions.single.title, 'Glycolysis');
    expect(home.recommended.single['readyTopics'], 2);
  });

  group('BlockSyncEngine', () {
    test('coalesces typing, applies, and reports conflicts to keep both', () async {
      final sent = <List<dynamic>>[];
      final api = OctoNotesApi(client((r) async {
        final ops = (jsonDecode(r.body) as Map)['ops'] as List;
        sent.add(ops);
        return http.Response(jsonEncode({
          'rev': 7,
          'results': [
            for (final o in ops)
              o['blockId'] == 'b2'
                  ? {'clientOpId': o['clientOpId'], 'status': 'conflict', 'block': {'id': 'b2', 'text': 'server', 'revision': 3}}
                  : {'clientOpId': o['clientOpId'], 'status': 'applied', 'block': {'id': o['blockId'], 'revision': 1}},
          ],
        }), 200);
      }));
      final sync = BlockSyncEngine(api: api, sessionId: 's1', flushDelay: const Duration(hours: 1));
      final conflicts = <BlockConflict>[];
      sync.conflicts.listen(conflicts.add);
      await sync.upsert('b1', {'type': 'paragraph', 'text': 'Gly', 'position': 'a'});
      await sync.upsert('b1', {'text': 'Glycolysis'});
      await sync.upsert('b2', {'text': 'mine'}, baseRevision: 2);
      expect(sync.pending, 2, reason: 'two edits of b1 became one op');
      await sync.flush();
      await Future<void>.delayed(Duration.zero);
      expect((sent.single.first as Map)['block'], {'type': 'paragraph', 'text': 'Glycolysis', 'position': 'a'});
      expect(sync.rev, 7);
      expect(sync.pending, 0);
      expect(sync.status, SyncStatus.conflict);
      expect(conflicts.single.serverBlock['text'], 'server');
      expect(conflicts.single.localOp['block'], {'text': 'mine'});
      sync.dispose();
    });

    test('keeps ops while offline and replays them later', () async {
      var online = false;
      final store = MemoryOpStore();
      final api = OctoNotesApi(client((r) async {
        if (!online) throw const SocketLikeException();
        final ops = (jsonDecode(r.body) as Map)['ops'] as List;
        return http.Response(jsonEncode({
          'rev': 1,
          'results': [for (final o in ops) {'clientOpId': o['clientOpId'], 'status': 'applied', 'block': {'id': o['blockId'], 'revision': 1}}],
        }), 200);
      }));
      final sync = BlockSyncEngine(api: api, sessionId: 's1', store: store, flushDelay: const Duration(hours: 1));
      await sync.upsert('b1', {'type': 'paragraph', 'text': 'offline note', 'position': 'a'});
      await sync.flush();
      expect(sync.status, SyncStatus.offline);
      expect((await store.load('s1')).length, 1, reason: 'survives a restart');
      sync.dispose();

      // App restarts, network is back.
      online = true;
      final again = BlockSyncEngine(api: api, sessionId: 's1', store: store, flushDelay: const Duration(hours: 1));
      await again.restore();
      await again.flush();
      expect(again.pending, 0);
      expect(again.status, SyncStatus.synced);
      expect(await store.load('s1'), isEmpty);
      again.dispose();
    });
  });

  test('new ids are UUID v4', () {
    expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(OctoNotesApi.newId()), isTrue);
  });
}

class SocketLikeException implements Exception {
  const SocketLikeException();
}
