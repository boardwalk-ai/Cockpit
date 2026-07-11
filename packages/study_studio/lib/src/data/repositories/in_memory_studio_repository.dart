import '../../domain/entities/studio.dart';
import '../../domain/entities/topic.dart';
import '../../domain/repositories/studio_repository.dart';
import '../mock/mock_data.dart';

/// In-memory [StudioRepository] seeded from mock data. Mutates topic mastery so
/// progress visibly responds to quizzes and flashcard reviews during the MVP.
class InMemoryStudioRepository implements StudioRepository {
  InMemoryStudioRepository() {
    for (final s in buildMockStudios()) {
      _studios[s.id] = s;
    }
  }

  final Map<String, Studio> _studios = {};

  @override
  Future<List<Studio>> listStudios() async => _studios.values.toList();

  @override
  Future<Studio> getStudio(String studioId) async {
    final s = _studios[studioId];
    if (s == null) throw StateError('Studio $studioId not found');
    return s;
  }

  @override
  Future<Topic> getTopic(String studioId, String topicId) async {
    final studio = await getStudio(studioId);
    return studio.topics.firstWhere(
      (t) => t.id == topicId,
      orElse: () => throw StateError('Topic $topicId not found'),
    );
  }

  @override
  Future<void> recordQuizResult({
    required String studioId,
    required String topicId,
    required bool correct,
  }) async {
    _adjustMastery(studioId, topicId, correct ? 0.08 : -0.05);
  }

  @override
  Future<void> recordFlashcardReview({
    required String studioId,
    required String topicId,
    required double quality,
  }) async {
    // Map quality 0..1 to a mastery delta of -0.04..+0.06.
    _adjustMastery(studioId, topicId, (quality * 0.10) - 0.04);
  }

  @override
  Future<void> markReviewed(String studioId, String topicId) async {
    _adjustMastery(studioId, topicId, 0.03);
  }

  void _adjustMastery(String studioId, String topicId, double delta) {
    final studio = _studios[studioId];
    if (studio == null) return;
    final updatedTopics = [
      for (final t in studio.topics)
        if (t.id == topicId)
          t.copyWith(mastery: (t.mastery + delta).clamp(0.0, 1.0))
        else
          t,
    ];
    _studios[studioId] = studio.copyWith(
      topics: updatedTopics,
      lastStudied: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}
