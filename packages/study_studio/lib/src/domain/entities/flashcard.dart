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
    this.reps = 0,
    this.intervalDays = 0,
    this.ease = 2.5,
    this.lapses = 0,
  });

  final String id;
  final String topicId;
  final String front;
  final String back;
  final FlashcardType type;
  final int difficulty;
  final FlashcardStatus status;
  final DateTime? dueDate;

  /// Spaced repetition (domain/card_schedule.dart): reviews in a row,
  /// days between them, how easy it is, times forgotten.
  final int reps;
  final double intervalDays;
  final double ease;
  final int lapses;

  Flashcard copyWith({
    FlashcardStatus? status,
    DateTime? dueDate,
    int? difficulty,
    int? reps,
    double? intervalDays,
    double? ease,
    int? lapses,
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
      reps: reps ?? this.reps,
      intervalDays: intervalDays ?? this.intervalDays,
      ease: ease ?? this.ease,
      lapses: lapses ?? this.lapses,
    );
  }
}
