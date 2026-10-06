import '../entities/studio.dart';
import '../entities/topic.dart';

/// Data access for studios and their Study Objects. Implemented in-memory for
/// the MVP; later backed by the custom API via `ApiClient`.
abstract interface class StudioRepository {
  Future<List<Studio>> listStudios();

  /// Create a new (empty) studio owned by the current user. Topics/flashcards
  /// are generated later from uploaded materials.
  Future<Studio> createStudio({required String title, String? subject});

  Future<Studio> getStudio(String studioId);

  /// Permanently delete an owned studio and all of its Study Objects. Seed demo
  /// studios are read-only on the backend and will be rejected.
  Future<void> deleteStudio(String studioId);

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

  /// Works out how the topics connect, for a studio built before that was
  /// recorded. True when topics were given links (reload the studio).
  Future<bool> linkTopics(String studioId);

  /// Grades a flashcard 0 (Again) to 3 (Easy): schedules when it comes back
  /// and moves its topic's mastery.
  Future<void> reviewFlashcard({
    required String studioId,
    required String topicId,
    required String cardId,
    required int grade,
  });
}
