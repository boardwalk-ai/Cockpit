import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_studio/src/domain/entities/topic.dart';
import 'package:study_studio/src/domain/knowledge_map.dart';
import 'package:study_studio/src/presentation/mobile/knowledge_map_mobile.dart';

import 'home_page_test.dart' show phone, viewport;

Topic topic(
  String id,
  String title,
  double mastery, {
  List<String> buildsOn = const [],
  List<String> related = const [],
  int importance = 3,
}) => Topic(
  id: id,
  studioId: 's1',
  title: title,
  subject: '',
  definition: '',
  simpleExplanation: '',
  detailedExplanation: '',
  whyItMatters: '',
  mastery: mastery,
  prerequisites: buildsOn,
  relatedTopicIds: related,
  importance: importance,
);

final topics = [
  topic('net', 'Network layers', 0.92),
  topic('ip', 'IP addressing', 0.25, buildsOn: ['Network layers']),
  topic('tcp', 'TCP basics', 0.8, buildsOn: ['Network layers']),
  topic('sub', 'Subnetting', 0, buildsOn: ['IP addressing']),
  topic('rt', 'Routing', 0.55, buildsOn: ['ip addressing'], related: ['sub']),
  topic('dns', 'DNS', 0, buildsOn: ['IP addressing'], related: ['tcp']),
];

void main() {
  group('the map', () {
    final map = KnowledgeMap.of(topics);

    test('builds-on arrows from titles, related lines both ways once', () {
      expect(map.buildsOn('rt'), ['ip']); // titles match ignoring case
      expect(map.leadsTo('ip'), unorderedEquals(['sub', 'rt', 'dns']));
      expect(map.related('sub'), ['rt']);
      expect(map.related('tcp'), ['dns']);
      expect(map.edges.where((e) => !e.buildsOn), hasLength(2));
    });

    test('needed-first above, later below', () {
      final y = {for (final t in topics) t.id: map.home[t.id]!.dy};
      expect(y['net'], lessThan(y['ip']!));
      expect(y['ip'], lessThan(y['sub']!));
      expect(y['ip'], y['tcp']);
    });

    test('the weak foundation: weakest topic others depend on', () {
      final (t, n) = map.weakFoundation!;
      expect(t.id, 'ip');
      expect(n, 3);
    });

    test('no links: rows of three in study order', () {
      final bare = KnowledgeMap.of([
        for (final (i, t) in topics.indexed) topic('$i', t.title, t.mastery),
      ]);
      expect(bare.bare, isTrue);
      expect(bare.home['0']!.dy, bare.home['2']!.dy);
      expect(bare.home['3']!.dy, greaterThan(bare.home['0']!.dy));
    });
  });

  testWidgets('tap a topic: its sheet with links; insight; zoom', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    viewport(tester, phone);
    final handle = tester.ensureSemantics();
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: KnowledgeMapMobile(
          studioId: 's1',
          topics: topics,
          onBack: () {},
          onLesson: (t) => opened.add('lesson ${t.id}'),
          onQuiz: (t) => opened.add('quiz ${t.id}'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('⚠ WEAK FOUNDATION'), findsOne);
    expect(
      find.textContaining('3 topics build on it', findRichText: true),
      findsOne,
    );

    expect(find.text('100%'), findsNothing); // fitted, not 1:1
    final before = tester
        .widget<Text>(find.textContaining(RegExp(r'^\d+%$')))
        .data;
    await tester.tap(find.bySemanticsLabel('Zoom in'));
    await tester.pump();
    final after = tester
        .widget<Text>(find.textContaining(RegExp(r'^\d+%$')))
        .data;
    expect(after, isNot(before));

    tester.semantics.tap(find.semantics.byLabel(RegExp(r'^IP addressing')));
    await tester.pumpAndSettle();
    expect(find.text('BUILDS ON'), findsOne);
    expect(find.text('LEADS TO'), findsOne);
    expect(find.text('Subnetting'), findsOne);
    await tester.tap(find.text('Start lesson'));
    await tester.pumpAndSettle();
    expect(opened, ['lesson ip']);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });
}
