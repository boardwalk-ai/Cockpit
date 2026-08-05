import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/domain/entities/studio.dart';
import 'package:study_studio/src/domain/entities/topic.dart';

void main() {
  Topic topic(String id, double mastery) {
    return Topic(
      id: id,
      studioId: 'studio-1',
      title: 'Topic $id',
      subject: 'Testing',
      definition: 'Definition',
      simpleExplanation: 'Simple explanation',
      detailedExplanation: 'Detailed explanation',
      whyItMatters: 'Why it matters',
      mastery: mastery,
    );
  }

  Studio studioWithTopics(List<Topic> topics) {
    final now = DateTime(2026, 1, 1);

    return Studio(
      id: 'studio-1',
      title: 'Test Studio',
      subject: 'Testing',
      createdAt: now,
      updatedAt: now,
      topics: topics,
    );
  }

  test('overall mastery is the average of topic mastery values', () {
    final studio = studioWithTopics([
      topic('1', 0.2),
      topic('2', 0.6),
      topic('3', 1.0),
    ]);

    expect(studio.overallMastery, closeTo(0.6, 0.0001));
  });

  test('overall mastery is zero when studio has no topics', () {
    final studio = studioWithTopics(const []);

    expect(studio.overallMastery, 0);
  });

  test('weakTopics returns only topics below 0.6 mastery', () {
    final weakOne = topic('weak-1', 0.2);
    final weakTwo = topic('weak-2', 0.59);
    final boundary = topic('boundary', 0.6);
    final strong = topic('strong', 0.9);

    final studio = studioWithTopics([
      weakOne,
      weakTwo,
      boundary,
      strong,
    ]);

    expect(
      studio.weakTopics.map((topic) => topic.id),
      ['weak-1', 'weak-2'],
    );
  });
}