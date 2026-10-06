import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_studio/src/data/api/dto_mappers.dart';
import 'package:study_studio/src/domain/concept_map.dart';
import 'package:study_studio/src/domain/entities/concept.dart';
import 'package:study_studio/src/domain/entities/topic.dart';
import 'package:study_studio/src/presentation/mobile/knowledge_map_mobile.dart';

import 'home_page_test.dart' show phone, viewport;

const cc = Topic(
  id: 'cc',
  studioId: 's1',
  title: 'Congestion control',
  subject: '',
  definition: '',
  simpleExplanation: '',
  detailedExplanation: '',
  whyItMatters: '',
  mastery: 0.3,
  concepts: [
    Concept(id: 'loss', name: 'Packet loss', meaning: 'A dropped packet.'),
    Concept(
      id: 'dup',
      name: 'Duplicate ACK',
      meaning: 'A repeated ack.',
      example: 'ACK 5, ACK 5',
    ),
    Concept(id: 'cwnd', name: 'Congestion window'),
  ],
  conceptLinks: [
    ConceptLink(from: 'loss', label: 'triggers', to: 'dup'),
    ConceptLink(from: 'dup', label: 'halves', to: 'cwnd'),
    ConceptLink(from: 'loss', label: 'starts at', toTopic: 'Routing'),
    ConceptLink(from: 'ghost', label: 'x', to: 'cwnd'),
  ],
);

const routing = Topic(
  id: 'rt',
  studioId: 's1',
  title: 'Routing',
  subject: '',
  definition: '',
  simpleExplanation: '',
  detailedExplanation: '',
  whyItMatters: '',
);

void main() {
  group('a concept map', () {
    final map = ConceptMap.of(cc);

    test('ideas, a stub into another lesson, links that exist', () {
      expect(map.nodes.map((n) => n.name), [
        'Packet loss',
        'Duplicate ACK',
        'Congestion window',
        'Routing',
      ]);
      expect(map.node('topic:Routing')!.isStub, isTrue);
      expect(map.edges.map((e) => e.label), [
        'triggers',
        'halves',
        'starts at',
      ]);
    });

    test('rows follow the arrows', () {
      final y = map.home;
      expect(y['loss']!.dy, lessThan(y['dup']!.dy));
      expect(y['dup']!.dy, lessThan(y['cwnd']!.dy));
    });

    test('practice hides every other inner link; four choices', () {
      expect(map.practice.map((e) => e.label), ['triggers']);
      final choices = ConceptMap.choices(map.practice.first, ['halves']);
      expect(choices, hasLength(4));
      expect(choices, contains('triggers'));
      expect(choices, contains('halves'));
    });

    test('read from the API', () {
      final t = topicFromJson({
        'id': 'cc',
        'concepts': [
          {'id': 'a', 'name': 'A', 'meaning': 'm'},
          {'name': 'no id'},
        ],
        'conceptLinks': [
          {'from': 'a', 'label': 'is', 'to': null, 'toTopic': 'B'},
        ],
      });
      expect(t.concepts.single.name, 'A');
      expect(t.conceptLinks.single.toTopic, 'B');
    });
  });

  testWidgets('open a topic, read an idea, complete the map', (tester) async {
    SharedPreferences.setMockInitialValues({});
    viewport(tester, phone);
    final handle = tester.ensureSemantics();
    final answers = <bool>[];
    final asked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: KnowledgeMapMobile(
          studioId: 's1',
          topics: const [cc, routing],
          onBack: () {},
          onLesson: (_) {},
          onQuiz: (_) {},
          onNeedConcepts: (t) async => asked.add(t.id),
          onAnswer: (_, right) => answers.add(right),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.semantics.tap(find.semantics.byLabel(RegExp('^Congestion control')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Explore concepts'));
    await tester.pumpAndSettle();
    expect(find.text('Explore'), findsOne);
    expect(find.text('Complete the map'), findsOne);
    expect(asked, isEmpty); // it has a map already

    tester.semantics.tap(find.semantics.byLabel('Duplicate ACK'));
    await tester.pumpAndSettle();
    expect(find.text('A repeated ack.'), findsOne);
    expect(find.text('ACK 5, ACK 5'), findsOne);
    await tester.tapAt(const Offset(20, 300)); // close the sheet
    await tester.pumpAndSettle();

    await tester.tap(find.text('Complete the map'));
    await tester.pumpAndSettle();
    expect(find.text('0 of 1 filled · tap a ?'), findsOne);
    tester.semantics.tap(find.semantics.byLabel(RegExp('^Blank between')));
    await tester.pumpAndSettle();
    expect(find.text('How does it connect?'), findsOne);
    await tester.tap(find.text('triggers'));
    await tester.pumpAndSettle();
    expect(answers, [true]);
    expect(find.text('1 of 1 right · mastery updated'), findsOne);

    // A stub opens the other lesson, which has no map yet: one is asked for.
    await tester.tap(find.text('Explore'));
    await tester.pumpAndSettle();
    tester.semantics.tap(find.semantics.byLabel('Go to Routing'));
    await tester.pumpAndSettle();
    expect(asked, ['rt']);
    expect(find.text('Routing'), findsWidgets);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });
}
