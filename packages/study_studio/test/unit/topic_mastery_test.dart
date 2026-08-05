import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/domain/entities/topic.dart';

void main() {
  Topic topicWithMastery(double mastery) {
    return Topic(
      id: 'topic-1',
      studioId: 'studio-1',
      title: 'Test Topic',
      subject: 'Testing',
      definition: 'Definition',
      simpleExplanation: 'Simple explanation',
      detailedExplanation: 'Detailed explanation',
      whyItMatters: 'Why it matters',
      mastery: mastery,
    );
  }

  test('topic is weak when mastery is below 0.6', () {
    final topic = topicWithMastery(0.59);

    expect(topic.isWeak, isTrue);
  });

  test('topic is not weak when mastery is exactly 0.6', () {
    final topic = topicWithMastery(0.6);

    expect(topic.isWeak, isFalse);
  });

  test('copyWith updates mastery without changing topic identity', () {
    final original = topicWithMastery(0.2);
    final updated = original.copyWith(mastery: 0.85);

    expect(updated.mastery, 0.85);
    expect(updated.id, original.id);
    expect(updated.studioId, original.studioId);
    expect(updated.title, original.title);
    expect(updated.isWeak, isFalse);
  });
}