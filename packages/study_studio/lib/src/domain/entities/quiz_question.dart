enum QuizType { multipleChoice, trueFalse, shortAnswer, fillBlank }

/// One assessment item attached to a Study Object.
class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.topicId,
    required this.type,
    required this.question,
    required this.answer,
    required this.explanation,
    this.choices = const [],
    this.difficulty = 2,
    this.relatedConcept,
  });

  final String id;
  final String topicId;
  final QuizType type;
  final String question;

  /// Options for multiple-choice / true-false. Empty for open answers.
  final List<String> choices;

  /// Canonical correct answer (text). For MC this matches one of [choices].
  final String answer;
  final String explanation;
  final int difficulty;
  final String? relatedConcept;

  /// Lenient correctness check used by the stub grader.
  bool isCorrect(String response) =>
      response.trim().toLowerCase() == answer.trim().toLowerCase();
}
