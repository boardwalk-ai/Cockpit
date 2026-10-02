import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwriter/src/data/gw_api.dart';
import 'package:ghostwriter/src/session/doc_session.dart';

import 'fake_server.dart';

Map<String, dynamic> snapshot({
  int rev = 3,
  bool locked = false,
  String body = 'First paragraph.\n\nSecond one.',
  Object? delta,
}) => {
  'type': 'snapshot',
  'rev': rev,
  'locked': locked,
  'style': 'apa',
  'title': 'Rising Tides',
  'fields': {'studentName': 'Ada Lovelace'},
  'body': body,
  'delta': delta,
  'bibliography': 'Sweet, W. (2022).',
  'wordCount': 4,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeServer server;
  GwDocumentSession? opened;
  var saves = 0;

  GwDocumentSession open({Map<String, Object?>? responses}) {
    server = FakeServer(responses: responses);
    return GwDocumentSession(
      GwApi(baseUrl: 'http://api', client: server.client),
      'p1',
      autosaveDelay: const Duration(milliseconds: 5),
      retryDelay: const Duration(milliseconds: 5),
    );
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 30));

  setUp(() => saves = 0);
  tearDown(() {
    opened?.dispose();
    opened = null;
  });

  group('body text', () {
    test('a plain body becomes one paragraph per line, and back', () {
      final d = documentFrom('One.\n\nTwo\nlines.\n\n', null);
      expect(d.toPlainText(), 'One.\nTwo lines.\n');
      expect(bodyText(d), 'One.\n\nTwo lines.');
    });

    test('a saved delta wins over the plain text', () {
      final d = documentFrom('ignored', [
        {
          'insert': 'Bold',
          'attributes': {'bold': true},
        },
        {'insert': '\n'},
      ]);
      expect(d.toPlainText(), 'Bold\n');
    });
  });

  test('loads the document and makes it editable', () async {
    final doc = opened = open();
    await server.connected();
    server.send(snapshot());
    await settle();

    expect(doc.loaded, isTrue);
    expect(doc.editable, isTrue);
    expect(doc.title.text, 'Rising Tides');
    expect(doc.fields['studentName']!.text, 'Ada Lovelace');
    expect(doc.body.document.toPlainText(), 'First paragraph.\nSecond one.\n');
    expect(doc.bibliography.text, 'Sweet, W. (2022).');
    expect(doc.saveState, SaveState.saved);
  });

  test('shows the agent writing, then hands the document over', () async {
    final doc = opened = open();
    await server.connected();
    server.send(snapshot(rev: 1, locked: true, body: ''));
    await settle();
    expect(doc.locked, isTrue);
    expect(doc.body.readOnly, isTrue);

    // A blank line split across two pieces is still one paragraph break.
    for (final piece in ['Tides rise.\n', '\nCities ', 'adapt.']) {
      server.send({'type': 'delta', 'text': piece});
    }
    server.send({'type': 'committed', 'rev': 2});
    await settle();
    expect(doc.body.document.toPlainText(), 'Tides rise.\nCities adapt.\n');
    expect(doc.wordCount, 4);
    expect(doc.saveState, SaveState.saved, reason: 'the agent text is no edit');

    server.send(snapshot(rev: 3, body: 'Tides rise.\n\nCities adapt.'));
    server.send({'type': 'unlocked', 'rev': 3});
    await settle();
    expect(doc.locked, isFalse);
    expect(doc.editable, isTrue);
    expect(doc.rev, 3);
  });

  test(
    'edits are saved on their own, against the rev they came from',
    () async {
      final doc = opened = open(
        responses: {
          'PUT /v1/projects/p1/document': (Object? body) {
            saves++;
            return {'rev': 4, 'wordCount': 5};
          },
        },
      );
      await server.connected();
      server.send(snapshot());
      await settle();

      doc.body.document.insert(0, 'New ');
      doc.title.text = 'Rising Tides, Revised';
      expect(doc.saveState, SaveState.dirty);
      await settle();

      expect(saves, 1, reason: 'both edits go in one save');
      final sent = server.bodies.last as Map;
      expect(sent['baseRev'], 3);
      expect(sent['title'], 'Rising Tides, Revised');
      expect(sent['body'], 'New First paragraph.\n\nSecond one.');
      expect(sent['fields'], {'studentName': 'Ada Lovelace'});
      expect(sent['delta'], isA<List>());
      expect(doc.rev, 4);
      expect(doc.saveState, SaveState.saved);

      // Our own save echoed back by the stream changes nothing.
      server.send(snapshot(rev: 4, body: 'stale echo'));
      await settle();
      expect(doc.body.document.toPlainText(), startsWith('New First'));
    },
  );

  test(
    'a save that lost to another device stops and offers a reload',
    () async {
      final doc = opened = open(
        responses: {
          'PUT /v1/projects/p1/document': const FakeReply(409, {
            'error': 'the document changed since it was loaded',
            'code': 'stale_rev',
            'details': {'rev': 7},
          }),
          'GET /v1/projects/p1/document': snapshot(rev: 7, body: 'Theirs.'),
        },
      );
      await server.connected();
      server.send(snapshot());
      await settle();

      doc.body.document.insert(0, 'Mine. ');
      await settle();
      expect(doc.saveState, SaveState.conflict);

      // No more saves while in conflict.
      doc.title.text = 'Another edit';
      await settle();
      expect(server.calls.where((c) => c.startsWith('PUT')), hasLength(1));

      await doc.reload();
      expect(doc.saveState, SaveState.saved);
      expect(doc.rev, 7);
      expect(doc.body.document.toPlainText(), 'Theirs.\n');
    },
  );

  test(
    'a newer snapshot while editing is a conflict, not an overwrite',
    () async {
      final doc = opened = open(
        responses: {
          'PUT /v1/projects/p1/document': const FakeReply(500, {'error': 'x'}),
        },
      );
      await server.connected();
      server.send(snapshot());
      await settle();
      doc.body.document.insert(0, 'Mine. ');
      await settle(); // the save fails; the edit is still pending

      server.send(snapshot(rev: 9, body: 'From the web.'));
      await settle();
      expect(doc.saveState, SaveState.conflict);
      expect(doc.body.document.toPlainText(), startsWith('Mine.'));
    },
  );

  test('restoring a version replaces the copy', () async {
    final doc = opened = open(
      responses: {
        'POST /v1/projects/p1/versions/v1/restore': snapshot(
          rev: 5,
          body: 'Back as it was.',
        ),
      },
    );
    await server.connected();
    server.send(snapshot());
    await settle();

    await doc.restore('v1');
    expect(doc.rev, 5);
    expect(doc.body.document.toPlainText(), 'Back as it was.\n');
    expect(doc.saveState, SaveState.saved);
  });

  test('typing is ignored while the agent holds the document', () async {
    final doc = opened = open();
    await server.connected();
    server.send(snapshot(locked: true));
    await settle();

    doc.title.text = 'Sneaky';
    await settle();
    expect(doc.saveState, SaveState.saved);
    expect(server.calls.where((c) => c.startsWith('PUT')), isEmpty);
  });
}
