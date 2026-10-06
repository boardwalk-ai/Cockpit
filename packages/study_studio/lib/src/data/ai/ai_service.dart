import '../../domain/ask.dart';
import '../../domain/entities/topic.dart';

/// Provider-agnostic AI boundary for the module.
///
/// The whole UI runs against this interface. Today it's backed by
/// [StubAiService] (canned, offline). When a provider is chosen, drop in a
/// `RemoteAiService` that calls the backend `/teach` (and extraction) endpoints
/// — no page or controller changes required.
abstract interface class AiService {
  /// A grounded tutor reply: explains [message] about [topic] using only the
  /// studio's material. Never quizzes or grades (per the Teach Me rules).
  Future<String> teach({required Topic topic, required String message});

  /// Ask AI: an answer to [question] from the studio's files, streamed (its
  /// sources first, then the text). [history] is the conversation so far;
  /// [topic] narrows it to one topic.
  Stream<AskEvent> ask({
    required String studioId,
    required String question,
    Topic? topic,
    List<AskTurn> history = const [],
  });
}
