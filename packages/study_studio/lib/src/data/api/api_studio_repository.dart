import '../../domain/activity.dart';
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
      extraHeaders: {'Idempotency-Key': newRequestId()},
      retry: true,
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
      query: {'correct': correct, 'event_id': newRequestId()},
      retry: true,
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
      query: {'quality': quality, 'event_id': newRequestId()},
      retry: true,
    );
  }

  @override
  Future<bool> mapConcepts(String studioId, String topicId) async {
    final events = await _sse.post(
      '/studios/$studioId/topics/${Uri.encodeComponent(topicId)}/concepts',
    );
    final data = events.where((e) => e.event == 'data').firstOrNull;
    return data?.data['made'] == true;
  }

  @override
  Future<bool> linkTopics(String studioId) async {
    final events = await _sse.post('/studios/$studioId/connections');
    final data = events.where((e) => e.event == 'data').firstOrNull;
    return ((data?.data['updated'] as num?) ?? 0) > 0;
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
      query: {'topic_id': topicId, 'grade': grade, 'event_id': newRequestId()},
      retry: true,
    );
  }

  @override
  Future<bool> renameStudio(String studioId, String title) async {
    final events = await _sse.post(
      '/studios/$studioId/rename',
      query: {'title': title},
    );
    final data = events.where((e) => e.event == 'data').firstOrNull?.data;
    return data?['renamed'] == true;
  }

  @override
  Future<void> registerDevice({
    required String id,
    required String token,
    required String platform,
    required int tzMinutes,
  }) async {
    await _sse.post(
      '/devices',
      body: {
        'id': id,
        'token': token,
        'platform': platform,
        'tzMinutes': tzMinutes,
      },
    );
  }

  @override
  Future<void> removeDevice(String id) async {
    await _sse.delete('/devices/${Uri.encodeComponent(id)}');
  }

  @override
  Future<void> savePlan(String studioId, Map<String, dynamic> plan) async {
    await _sse.post('/studios/$studioId/plan', body: plan);
  }

  @override
  Future<List<DayActivity>> activity(String studioId, {int days = 14}) async {
    final events = await _sse.get(
      '/studios/$studioId/activity',
      query: {'days': days, 'tz': DateTime.now().timeZoneOffset.inMinutes},
    );
    final data = events.where((e) => e.event == 'data').firstOrNull?.data;
    final list = data?['value'];
    if (list is! List) return const [];
    return [for (final j in list) ?DayActivity.fromJson(j)];
  }

  @override
  Future<bool?> gradeRecall({
    required String studioId,
    required String question,
    required String answer,
    required String said,
  }) async {
    final events = await _sse.post(
      '/studios/$studioId/grade',
      body: {'question': question, 'answer': answer, 'said': said},
    );
    final data = events.where((e) => e.event == 'data').firstOrNull?.data;
    final correct = data?['correct'];
    return correct is bool ? correct : null;
  }

  @override
  Future<void> markReviewed(String studioId, String topicId) async {
    await _sse.post('/studios/$studioId/topics/$topicId/mark-reviewed');
  }
}
