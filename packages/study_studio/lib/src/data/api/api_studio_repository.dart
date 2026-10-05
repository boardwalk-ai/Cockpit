import '../../domain/entities/studio.dart';
import '../../domain/entities/topic.dart';
import '../../domain/repositories/studio_repository.dart';
import 'dto_mappers.dart';
import 'sse_client.dart';

/// [StudioRepository] backed by the server API over SSE. Drop-in replacement for
/// the in-memory repo — the pages/providers are unchanged.
class ApiStudioRepository implements StudioRepository {
  ApiStudioRepository({SseClient? client}) : _sse = client ?? SseClient();

  final SseClient _sse;

  @override
  Future<List<Studio>> listStudios() async {
    final events = await _sse.get('/studios');
    return events
        .where((e) => e.event == 'item')
        .map((e) => studioFromJson(e.data))
        .toList();
  }

  @override
  Future<Studio> createStudio({required String title, String? subject}) async {
    final events = await _sse.post(
      '/studios',
      body: {'title': title, if (subject != null) 'subject': subject},
    );
    final data = events.firstWhere(
      (e) => e.event == 'data',
      orElse: () => throw SseException('Studio was not created'),
    );
    return studioFromJson(data.data);
  }

  @override
  Future<Studio> getStudio(String studioId) async {
    final events = await _sse.get('/studios/$studioId');
    final data = events.firstWhere(
      (e) => e.event == 'data',
      orElse: () => throw SseException('Studio $studioId not found'),
    );
    return studioFromJson(data.data);
  }

  @override
  Future<void> deleteStudio(String studioId) async {
    await _sse.delete('/studios/$studioId');
  }

  @override
  Future<Topic> getTopic(String studioId, String topicId) async {
    final events = await _sse.get('/studios/$studioId/topics/$topicId');
    final data = events.firstWhere(
      (e) => e.event == 'data',
      orElse: () => throw SseException('Topic $topicId not found'),
    );
    return topicFromJson(data.data);
  }

  @override
  Future<void> recordQuizResult({
    required String studioId,
    required String topicId,
    required bool correct,
  }) async {
    await _sse.post(
      '/studios/$studioId/topics/$topicId/quiz-result',
      query: {'correct': correct},
    );
  }

  @override
  Future<void> recordFlashcardReview({
    required String studioId,
    required String topicId,
    required double quality,
  }) async {
    await _sse.post(
      '/studios/$studioId/topics/$topicId/flashcard-review',
      query: {'quality': quality},
    );
  }

  @override
  Future<void> reviewFlashcard({
    required String studioId,
    required String topicId,
    required String cardId,
    required int grade,
  }) async {
    await _sse.post(
      '/studios/$studioId/flashcards/${Uri.encodeComponent(cardId)}/review',
      query: {'topic_id': topicId, 'grade': grade},
    );
  }

  @override
  Future<void> markReviewed(String studioId, String topicId) async {
    await _sse.post('/studios/$studioId/topics/$topicId/mark-reviewed');
  }
}
