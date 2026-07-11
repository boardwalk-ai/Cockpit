import '../entities/studio.dart';
import '../entities/topic.dart';

/// Data access for studios and their Study Objects. Implemented in-memory for
/// the MVP; later backed by the custom API via `ApiClient`.
abstract interface class StudioRepository {
  Future<List<Studio>> listStudios();

  Future<Studio> getStudio(String studioId);

  Future<Topic> getTopic(String studioId, String topicId);

  /// Update mastery after a quiz answer.
  Future<void> recordQuizResult({
    required String studioId,
    required String topicId,
    required bool correct,
  });

  /// Update mastery after a flashcard review (Again/Hard/Good/Easy).
  Future<void> recordFlashcardReview({
    required String studioId,
    required String topicId,
    required double quality, // 0.0 (Again) – 1.0 (Easy)
  });

  Future<void> markReviewed(String studioId, String topicId);
}
