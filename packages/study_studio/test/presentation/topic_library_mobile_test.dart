import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/domain/entities/topic.dart';
import 'package:study_studio/src/presentation/mobile/topic_library_mobile.dart';

import 'home_page_test.dart' show phone, viewport;

Topic topic(String title, double mastery, {int importance = 3}) => Topic(
  id: title,
  studioId: 's1',
  title: title,
  subject: '',
  definition: '',
  simpleExplanation: '',
  detailedExplanation: '',
  whyItMatters: '',
  mastery: mastery,
  importance: importance,
);

final topics = [
  topic('Network layers', 0.92),
  topic('Subnetting', 0.8, importance: 5),
  topic('TCP basics', 0.55),
  topic('Congestion', 0.3),
  topic('DNS', 0),
];

void main() {
  late List<String> opened;

  Future<void> show(WidgetTester tester) async {
    viewport(tester, phone);
    opened = [];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: TopicLibraryMobile(
          topics: topics,
          onBack: () {},
          onOpen: (t) => opened.add(t.id),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double y(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  testWidgets('your path, filters with counts, rows', (tester) async {
    await show(tester);
    expect(find.text('Your path'), findsOne);
    expect(find.text('2 of 5 learned'), findsOne);
    expect(find.text('To review  2'), findsOne);
    expect(find.text('Learned  2'), findsOne);
    expect(find.text('New  1'), findsOne);
    expect(find.text('30% mastered · Medium'), findsOne);
    expect(find.text('Not started · Medium'), findsOne);
    expect(find.byIcon(Icons.star_rounded), findsOne);

    await tester.tap(find.text('To review  2'));
    await tester.pumpAndSettle();
    expect(find.text('TCP basics'), findsOne);
    expect(find.text('Congestion'), findsOne);
    expect(find.text('DNS'), findsNothing);

    await tester.tap(find.text('Congestion'));
    expect(opened, ['Congestion']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search narrows and says when nothing matches', (tester) async {
    await show(tester);
    await tester.enterText(find.byType(TextField), 'tcp');
    await tester.pumpAndSettle();
    expect(find.text('TCP basics'), findsOne);
    expect(find.text('DNS'), findsNothing);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No topic matches “zzz”'), findsOne);
  });

  testWidgets('sort: weakest first, then by name', (tester) async {
    await show(tester);
    expect(y(tester, 'Network layers'), lessThan(y(tester, 'DNS')));

    await tester.tap(find.bySemanticsLabel('Sort'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weakest first'));
    await tester.pumpAndSettle();
    expect(y(tester, 'DNS'), lessThan(y(tester, 'Congestion')));
    expect(y(tester, 'Congestion'), lessThan(y(tester, 'Network layers')));

    await tester.tap(find.bySemanticsLabel('Sort'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();
    expect(y(tester, 'Congestion'), lessThan(y(tester, 'DNS')));
  });
}
