import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/data/api/dto_mappers.dart';
import 'package:study_studio/src/domain/entities/source.dart';
import 'package:study_studio/src/domain/entities/topic.dart';
import 'package:study_studio/src/presentation/mobile/topic_overview_mobile.dart';

import 'home_page_test.dart' show phone, viewport;

const basics = Topic(
  id: 't0',
  studioId: 's1',
  title: 'TCP basics',
  subject: '',
  definition: '',
  simpleExplanation: '',
  detailedExplanation: '',
  whyItMatters: '',
);

const congestion = Topic(
  id: 't3',
  studioId: 's1',
  title: 'TCP congestion control',
  subject: 'Networks',
  definition: 'TCP slows down when the network is crowded.',
  simpleExplanation: '',
  detailedExplanation: '',
  whyItMatters: '',
  summary: [
    'TCP slows down when it sees lost packets.',
    'It starts slow and doubles, then grows by one.',
    'On a loss, it halves the window and climbs again.',
  ],
  prerequisites: ['TCP basics', 'Sliding window'],
  sources: [SourceReference(fileName: 'ch4.pdf', snippet: '', page: 12)],
  importance: 4,
  difficulty: 3,
  estimatedStudyTimeMinutes: 6,
  mastery: 0.3,
);

void main() {
  Future<Map<String, Object>> show(WidgetTester tester, Topic topic) async {
    viewport(tester, phone);
    final calls = <String, Object>{};
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: TopicOverviewMobile(
          topic: topic,
          number: 3,
          total: 8,
          earlier: const {'TCP basics': basics},
          onBack: () => calls['back'] = true,
          onStart: () => calls['start'] = true,
          onQuiz: () => calls['quiz'] = true,
          onFlashcards: () => calls['cards'] = true,
          onOpenTopic: (t) => calls['open'] = t.id,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return calls;
  }

  testWidgets('ring, stats, summary, before this, notes', (tester) async {
    final calls = await show(tester, congestion);
    expect(find.text('Topic 3 of 8'), findsOne);
    expect(find.text('30%'), findsOne);
    expect(find.text('Medium'), findsOne);
    expect(find.text('6 min'), findsOne);
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(4));
    expect(find.text('SUMMARY'), findsOne);
    expect(
      find.text('It starts slow and doubles, then grows by one.'),
      findsOne,
    );
    expect(find.text('BEFORE THIS'), findsOne);
    expect(find.text('ch4.pdf · p.12'), findsOne);
    // An earlier topic opens; one that isn't a topic is just a name.
    await tester.tap(find.text('TCP basics'));
    expect(calls['open'], 't0');
    await tester.tap(find.text('Start lesson'));
    await tester.tap(find.text('Quiz me on this'));
    expect(calls['start'], true);
    expect(calls['quiz'], true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an older studio: the definition stands in', (tester) async {
    await show(
      tester,
      const Topic(
        id: 't1',
        studioId: 's1',
        title: 'DNS',
        subject: '',
        definition: 'Names to numbers.',
        simpleExplanation: '',
        detailedExplanation: '',
        whyItMatters: '',
      ),
    );
    expect(find.text('Names to numbers.'), findsOne);
    expect(find.text('BEFORE THIS'), findsNothing);
    expect(find.text('FROM YOUR NOTES'), findsNothing);
  });

  test('summary comes from the API, empty when missing', () {
    final j = {
      'id': 't',
      'summary': ['a', 'b'],
    };
    expect(topicFromJson(j).summary, ['a', 'b']);
    expect(topicFromJson({'id': 't'}).summary, isEmpty);
  });
}
