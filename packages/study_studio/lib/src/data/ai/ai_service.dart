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
}
