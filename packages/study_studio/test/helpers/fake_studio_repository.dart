import 'package:study_studio/src/domain/entities/studio.dart';
import 'package:study_studio/src/domain/entities/topic.dart';
import 'package:study_studio/src/domain/repositories/studio_repository.dart';

class FakeStudioRepository implements StudioRepository {
  FakeStudioRepository({
    this.studios = const [],
    this.error,
    this.delay = Duration.zero,
  });

  final List<Studio> studios;
  final Object? error;
  final Duration delay;

  Future<void> _wait() async {
    if (delay != Duration.zero) {
      await Future<void>.delayed(delay);
    }

    if (error != null) {
      throw error!;
    }
  }

  @override
  Future<List<Studio>> listStudios() async {
    await _wait();
    return studios;
  }

  @override
  Future<Studio> getStudio(String studioId) async {
    await _wait();

    return studios.firstWhere(
      (studio) => studio.id == studioId,
      orElse: () => throw StateError('Studio $studioId not found'),
    );
  }

  @override
  Future<Topic> getTopic(String studioId, String topicId) async {
    final studio = await getStudio(studioId);

    return studio.topics.firstWhere(
      (topic) => topic.id == topicId,
      orElse: () => throw StateError('Topic $topicId not found'),
    );
  }

  @override
  Future<Studio> createStudio({
    required String title,
    String? subject,
  }) {
    throw UnimplementedError(
      'createStudio is not required by the current widget tests.',
    );
  }

  @override
  Future<void> recordQuizResult({
    required String studioId,
    required String topicId,
    required bool correct,
  }) async {}

  @override
  Future<void> recordFlashcardReview({
    required String studioId,
    required String topicId,
    required double quality,
  }) async {}

  @override
  Future<void> markReviewed(
    String studioId,
    String topicId,
  ) async {}
}