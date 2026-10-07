import '../../domain/activity.dart';
import '../../domain/card_schedule.dart';
import '../../domain/entities/studio.dart';
import '../../domain/entities/topic.dart';
import '../../domain/repositories/studio_repository.dart';
import '../mock/mock_data.dart';

/// In-memory [StudioRepository] seeded from mock data. Mutates topic mastery so
/// progress visibly responds to quizzes and flashcard reviews during the MVP.
class InMemoryStudioRepository implements StudioRepository {
  final _events = <(String studio, DateTime at, bool card, bool correct)>[];

  void _log(String studioId, {required bool card, required bool correct}) =>
      _events.add((studioId, DateTime.now(), card, correct));

  @override
  Future<bool> renameStudio(String studioId, String title) async {
    final studio = _studios[studioId];
    if (studio == null || title.trim().isEmpty) return false;
    _studios[studioId] = studio.copyWith(title: title.trim());
    return true;
  }

  @override
  Future<void> registerDevice({
    required String id,
    required String token,
    required String platform,
    required int tzMinutes,
  }) async {}

  @override
  Future<void> removeDevice(String id) async {}

  @override
  Future<void> savePlan(String studioId, Map<String, dynamic> plan) async {}

  @override
  Future<List<DayActivity>> activity(String studioId, {int days = 14}) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return [
      for (var i = days - 1; i >= 0; i--)
        () {
          final d = today.subtract(Duration(days: i));
          final on = [
            for (final e in _events)
              if (e.$1 == studioId &&
                  DateTime(e.$2.year, e.$2.month, e.$2.day) == d)
                e,
          ];
          return DayActivity(
            date: d,
            cards: on.where((e) => e.$3).length,
            quiz: on.where((e) => !e.$3).length,
            quizRight: on.where((e) => !e.$3 && e.$4).length,
          );
        }(),
    ];
  }

  InMemoryStudioRepository() {
    for (final s in buildMockStudios()) {
      _studios[s.id] = s;
    }
  }

  final Map<String, Studio> _studios = {};

  @override
  Future<List<Studio>> listStudios() async => _studios.values.toList();

  @override
  Future<Studio> createStudio({required String title, String? subject}) async {
    final now = DateTime.now();
    final studio = Studio(
      id: 'local_${now.microsecondsSinceEpoch}',
      title: title,
      subject: subject ?? '',
      createdAt: now,
      updatedAt: now,
    );
    _studios[studio.id] = studio;
    return studio;
  }

  @override
  Future<Studio> getStudio(String studioId) async {
    final s = _studios[studioId];
    if (s == null) throw StateError('Studio $studioId not found');
    return s;
  }

  @override
  Future<void> deleteStudio(String studioId) async {
    _studios.remove(studioId);
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
    _log(studioId, card: false, correct: correct);
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
  Future<bool> linkTopics(String studioId) async => false;

  @override
  Future<bool> mapConcepts(String studioId, String topicId) async => false;

  @override
  Future<void> reviewFlashcard({
    required String studioId,
    required String topicId,
    required String cardId,
    required int grade,
  }) async {
    _log(studioId, card: true, correct: grade >= 2);
    final studio = _studios[studioId];
    if (studio == null) return;
    final now = DateTime.now();
    _studios[studioId] = studio.copyWith(
      topics: [
        for (final t in studio.topics)
          if (t.id == topicId)
            t.copyWith(
              mastery: (t.mastery + grade / 3 * 0.10 - 0.04).clamp(0.0, 1.0),
              flashcards: [
                for (final c in t.flashcards)
                  c.id == cardId ? CardSchedule.review(c, grade, now) : c,
              ],
            )
          else
            t,
      ],
    );
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
