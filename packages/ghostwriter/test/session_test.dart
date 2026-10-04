import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwriter/src/data/sse.dart';
import 'package:ghostwriter/src/session/gw_session.dart';
import 'package:ghostwriter/src/session/timeline.dart';

import 'fake_server.dart';

void main() {
  group('parseSse', () {
    test('splits frames, joins data lines, and skips keep-alives', () async {
      final body = Stream.fromIterable(
        [
          'id: 1\ndata: {"a":',
          '1}\n\n: keep-alive\n\n',
          'data: one\ndata: two\n\n',
          'id: 3\ndata:{"b":2}\n\n',
        ].map(utf8.encode),
      );
      final frames = await parseSse(body).toList();
      expect(frames.map((f) => f.data), ['{"a":1}', 'one\ntwo', '{"b":2}']);
      expect(frames.map((f) => f.id), ['1', null, '3']);
    });
  });

  group('RunTimeline', () {
    test('builds the chat from a run, start to finish', () {
      final t = RunTimeline();
      for (final e in [
        ev(1, 'user_message', {'text': 'An essay on tides'}),
        ev(2, 'step_start', {
          'stepId': 's1',
          'tool': 'plan_essay',
          'title': 'Planning',
        }),
        ev(3, 'step_done', {'stepId': 's1', 'summary': 'Planned.'}),
        ev(4, 'question', {
          'field': 'essayFocus',
          'question': 'Focus?',
          'inputType': 'multiselect',
          'options': [
            {'label': 'Economy', 'value': 'Economy'},
            'Policy',
          ],
          'allowCustom': true,
        }),
      ]) {
        t.apply(e);
      }
      expect(t.phase, RunPhase.waiting);
      final question = t.pending!;
      expect(question.options.map((o) => o.label), ['Economy', 'Policy']);
      expect((t.items[1] as StepItem).status, StepStatus.done);

      t.apply(
        ev(5, 'question_answered', {
          'field': 'essayFocus',
          'value': ['Policy'],
        }),
      );
      expect(t.pending, isNull);
      expect(t.phase, RunPhase.running);
      expect(question.answered, isTrue);
      expect(question.answer, ['Policy']);

      // GhostWriter types a reply live, then the stored message lands.
      t.apply(ev(null, 'assistant_delta', {'chunk': 'Writing '}));
      t.apply(ev(null, 'assistant_delta', {'chunk': 'now'}));
      expect((t.items.last as AssistantItem).streaming, isTrue);
      t.apply(ev(6, 'assistant_message', {'text': 'Writing now.'}));
      final said = t.items.last as AssistantItem;
      expect(said.text, 'Writing now.');
      expect(said.streaming, isFalse);

      t.apply(
        ev(7, 'sources_ready', {
          'count': 2,
          'sources': [
            {'url': 'u'},
          ],
        }),
      );
      expect(t.sourceCount, 2);
      t.apply(ev(8, 'writing_started', {'targetWords': 800}));
      t.apply(ev(9, 'write_progress', {'words': 320, 'targetWords': 800}));
      expect(t.writing!.words, 320);
      t.apply(ev(10, 'credits', {'charged': 100, 'balance': 900}));
      expect(t.credits, 900);
      t.apply(ev(11, 'done'));

      expect(t.ended, isTrue);
      expect(t.writing!.done, isTrue);
      final end = t.items.last as EndItem;
      expect(end.phase, RunPhase.finished);
      expect(end.wroteEssay, isTrue);
      expect(t.lastSeq, 11);
    });

    test('a replayed event is applied once', () {
      final t = RunTimeline();
      expect(t.apply(ev(1, 'user_message', {'text': 'hi'})), isTrue);
      expect(t.apply(ev(1, 'user_message', {'text': 'hi'})), isFalse);
      expect(t.items, hasLength(1));
    });

    test('a failed run stops its running steps', () {
      final t = RunTimeline()
        ..apply(
          ev(1, 'step_start', {
            'stepId': 's',
            'tool': 'write_essay',
            'title': 'Writing',
          }),
        )
        ..apply(ev(2, 'fatal', {'error': 'Out of OctoCredits.'}));
      expect((t.items.first as StepItem).status, StepStatus.stopped);
      expect((t.items.last as EndItem).error, 'Out of OctoCredits.');
      expect(t.phase, RunPhase.failed);
    });
  });

  group('mid-run messages', () {
    test('a quick reply is its own bubble, not part of a streaming one', () {
      final t = RunTimeline()
        ..apply(ev(null, 'assistant_delta', {'chunk': 'Planning '}))
        ..apply(
          ev(1, 'assistant_message', {
            'text': 'About a minute more.',
            'aside': true,
          }),
        )
        ..apply(ev(2, 'assistant_message', {'text': 'Planning the essay.'}));
      final texts = t.items.whereType<AssistantItem>().map((a) => a.text);
      expect(texts, ['Planning the essay.', 'About a minute more.']);
    });

    test('a question set aside by a message shows no answer', () {
      final t = RunTimeline()
        ..apply(
          ev(1, 'question', {
            'field': 'wordCount',
            'question': 'How long?',
            'inputType': 'number',
          }),
        )
        ..apply(
          ev(2, 'question_answered', {
            'field': 'wordCount',
            'value': {'userMessage': 'Keep it short'},
            'skipped': true,
          }),
        );
      final question = t.items.whereType<QuestionItem>().single;
      expect(question.answered, isTrue);
      expect(question.skipped, isTrue);
      expect(question.answer, isNull);
      expect(t.pending, isNull);
    });

    test('writing that starts again starts its count again', () {
      final t = RunTimeline()
        ..apply(ev(1, 'writing_started', {'targetWords': 800}))
        ..apply(ev(2, 'write_progress', {'words': 300, 'targetWords': 800}))
        ..apply(ev(3, 'writing_started', {'targetWords': 800}));
      expect(t.writing!.words, 0);
      expect(t.items.whereType<WritingItem>(), hasLength(1));
    });
  });

  group('GwSession', () {
    late FakeServer server;
    late GwSession session;

    setUp(() {
      server = FakeServer();
      session = server.session();
    });

    tearDown(() => session.dispose());

    test('Start creates the project and run, then follows it', () async {
      await session.start('An essay on tides');
      expect(server.calls.first, startsWith('PUT /v1/projects/'));
      expect(server.calls[1], matches(RegExp(r'POST /v1/projects/.+/runs')));
      // The brief shows at once, before the server echoes it.
      expect(session.timeline.items.single, isA<UserItem>());

      await server.connected();
      server.send(ev(1, 'user_message', {'text': 'An essay on tides'}));
      server.send(ev(2, 'context_update', {'essayTopic': 'Tides'}));
      await pumpEventQueue();
      expect(
        session.timeline.items,
        hasLength(1),
        reason: 'no duplicate brief',
      );
      expect(session.title, 'Tides');
    });

    test('a file can be sent with no words, into the project it was read '
        'into', () async {
      await session.attach('tides.pdf', [1, 2, 3]);
      // Read into a draft project; the landing stays (no open project yet).
      expect(server.calls[0], startsWith('PUT /v1/projects/'));
      expect(
        server.calls[1],
        matches(RegExp(r'POST /v1/projects/.+/attachments')),
      );
      expect(session.hasProject, isFalse);
      expect(session.attachmentsReady, isTrue);
      final draft = server.calls[0].split('/').last;
      final upload = server.bodies[1] as Map<String, dynamic>;
      expect(upload['name'], 'tides.pdf');
      expect(upload['data'], 'AQID');

      await session.start('');
      expect(session.projectId, draft);
      final start = server.bodies.last as Map<String, dynamic>;
      expect(start['instruction'], '');
      expect(start['attachments'], [upload['id']]);
      expect(server.calls.where((c) => c.startsWith('PUT')), hasLength(1));
      final shown = session.timeline.items.single as UserItem;
      expect(shown.attachments, hasLength(1));
      expect(session.attachments, isEmpty);
    });

    test('a file never sent is dropped with its draft project', () async {
      await session.attach('tides.pdf', [1, 2, 3]);
      session.newChat();
      await pumpEventQueue();
      expect(
        server.calls,
        contains(matches(RegExp(r'DELETE /v1/attachments/'))),
      );
      expect(server.calls, contains(matches(RegExp(r'DELETE /v1/projects/'))));
      expect(session.attachments, isEmpty);
    });

    test('a dropped connection picks up after the last seq', () async {
      await session.start('Tides');
      await server.connected();
      server.send(ev(1, 'user_message', {'text': 'Tides'}));
      server.send(
        ev(2, 'step_start', {
          'stepId': 's',
          'tool': 'plan_essay',
          'title': 'Planning',
        }),
      );
      await pumpEventQueue();
      server.drop();

      await server.connected();
      expect(server.lastSince, 2);
      server.send(ev(3, 'step_done', {'stepId': 's'}));
      server.send(ev(4, 'done'));
      await server.closed();
      await pumpEventQueue();

      expect(session.timeline.ended, isTrue);
      expect(session.reconnecting, isFalse);
      expect(server.connections, 2);
    });

    test(
      'a chat message during the focus question asks for new options',
      () async {
        await session.start('Tides');
        await server.connected();
        server.send(
          ev(1, 'question', {
            'field': 'essayFocus',
            'inputType': 'multiselect',
          }),
        );
        await pumpEventQueue();

        await session.send('more about cities');
        expect(server.bodies.last, {
          'field': 'essayFocus',
          'value': '__chat_refinement__:more about cities',
        });
      },
    );

    test('New chat while still connecting closes that connection', () async {
      await session.start('Tides');
      session.newChat(); // the events request is still in flight
      await server.connected();
      await pumpEventQueue();
      expect(server.listening, isFalse);
      expect(server.cancelled, 1);
    });

    test('after the essay, a message asks for a revision run', () async {
      await session.start('Tides');
      final project = session.projectId;
      await server.connected();
      server.send(ev(1, 'user_message', {'text': 'Tides'}));
      server.send(ev(2, 'writing_started', {'targetWords': 500}));
      server.send(ev(3, 'done'));
      await server.closed();
      await pumpEventQueue();
      expect(session.canRevise, isTrue);

      await session.send('Shorten paragraph 2');
      // A new run on the same project; the project itself is not touched.
      expect(server.calls.last, 'POST /v1/projects/$project/runs');
      expect(server.calls.where((c) => c.startsWith('PUT')), hasLength(1));
      expect(session.earlier, hasLength(1));
      expect(session.canRevise, isFalse);

      await server.connected();
      server.send(ev(1, 'user_message', {'text': 'Shorten paragraph 2'}));
      server.send(
        ev(2, 'step_start', {
          'stepId': 's',
          'tool': 'revise_essay',
          'title': 'Revising',
        }),
      );
      server.send(ev(3, 'writing_started', {'targetWords': 520}));
      await pumpEventQueue();

      // The whole conversation, oldest first; the brief shows once per run.
      expect(session.items.whereType<UserItem>().map((u) => u.text), [
        'Tides',
        'Shorten paragraph 2',
      ]);
      expect(session.timeline.writing!.revising, isTrue);
      expect(session.hasEssay, isTrue);
    });

    test('opening a project replays every run, oldest first', () async {
      server.responses['GET /v1/projects/p1'] = {
        'id': 'p1',
        'title': 'Tides',
        'runIds': ['r1', 'r2'],
        'lastRunId': 'r2',
      };
      final opened = session.openProject('p1');

      await server.connected();
      expect(server.calls.last, 'GET /v1/runs/r1/events');
      server.send(ev(1, 'user_message', {'text': 'Tides'}));
      server.send(ev(2, 'done'));
      await opened;

      await server.connected();
      expect(server.calls.last, 'GET /v1/runs/r2/events');
      server.send(ev(1, 'user_message', {'text': 'Make it shorter'}));
      await pumpEventQueue();

      expect(session.earlier, hasLength(1));
      expect(session.runId, 'r2');
      expect(session.items.whereType<UserItem>().map((u) => u.text), [
        'Tides',
        'Make it shorter',
      ]);
    });

    test('New chat stops following the old run', () async {
      await session.start('Tides');
      await server.connected();
      await pumpEventQueue();
      expect(server.listening, isTrue);
      session.newChat();
      await pumpEventQueue();
      expect(server.listening, isFalse);
      expect(server.cancelled, 1);
      expect(session.hasProject, isFalse);
    });
  });
}
