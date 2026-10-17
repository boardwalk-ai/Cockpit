import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/domain/entities/quiz_question.dart';
import 'package:study_studio/src/presentation/quiz_me/quiz_me_page.dart';

List<QuizQuestion> qs(String topic, int n) => [
  for (var i = 0; i < n; i++)
    QuizQuestion(
      id: '$topic-$i',
      topicId: topic,
      type: QuizType.trueFalse,
      question: 'q$i',
      answer: 'True',
      explanation: '',
    ),
];

void main() {
  test('a round is at most ten questions, weakest topic first', () {
    final round = pickQuizRound([
      (0.9, qs('strong', 8)),
      (0.2, qs('weak', 8)),
      (0.5, qs('mid', 8)),
    ], seed: 1);
    expect(round, hasLength(10));
    expect(round.take(3).map((q) => q.topicId), ['weak', 'mid', 'strong']);
    expect(round.where((q) => q.topicId == 'weak'), hasLength(4));
    expect(round.map((q) => q.id).toSet(), hasLength(10));
  });

  test('fewer than ten: all of them', () {
    expect(pickQuizRound([(0.5, qs('a', 3)), (0.1, qs('b', 2))]), hasLength(5));
  });
}
