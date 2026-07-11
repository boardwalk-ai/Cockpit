enum FlashcardType { definition, example, process, compare, mistake, formula, causeEffect }

enum FlashcardStatus { fresh, learning, review }

/// A front/back study card derived from a Study Object.
class Flashcard {
  const Flashcard({
    required this.id,
    required this.topicId,
    required this.front,
    required this.back,
    this.type = FlashcardType.definition,
    this.difficulty = 2,
    this.status = FlashcardStatus.fresh,
    this.dueDate,
  });

  final String id;
  final String topicId;
  final String front;
  final String back;
  final FlashcardType type;
  final int difficulty;
  final FlashcardStatus status;
  final DateTime? dueDate;

  Flashcard copyWith({
    FlashcardStatus? status,
    DateTime? dueDate,
    int? difficulty,
  }) {
    return Flashcard(
      id: id,
      topicId: topicId,
      front: front,
      back: back,
      type: type,
      difficulty: difficulty ?? this.difficulty,
      status: status ?? this.status,
      dueDate: dueDate ?? this.dueDate,
    );
  }
}
