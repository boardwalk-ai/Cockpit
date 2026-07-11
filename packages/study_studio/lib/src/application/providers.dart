import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ai/ai_service.dart';
import '../data/ai/stub_ai_service.dart';
import '../data/repositories/in_memory_studio_repository.dart';
import '../domain/entities/studio.dart';
import '../domain/entities/topic.dart';
import '../domain/repositories/studio_repository.dart';

/// AI boundary. Swap to a `RemoteAiService` here when a provider is chosen.
final aiServiceProvider = Provider<AiService>((ref) => const StubAiService());

/// Data access. Swap to an API-backed repository here when the backend exists.
final studioRepositoryProvider = Provider<StudioRepository>(
  (ref) => InMemoryStudioRepository(),
);

/// All studios (Study Studio Home).
final studioListProvider = FutureProvider<List<Studio>>((ref) {
  return ref.watch(studioRepositoryProvider).listStudios();
});

/// One studio by id (Dashboard, Topic Library, Progress).
final studioProvider = FutureProvider.family<Studio, String>((ref, studioId) {
  return ref.watch(studioRepositoryProvider).getStudio(studioId);
});

typedef TopicKey = ({String studioId, String topicId});

/// One Study Object by id (Topic Detail, Teach Me, etc.).
final topicProvider = FutureProvider.family<Topic, TopicKey>((ref, key) {
  return ref.watch(studioRepositoryProvider).getTopic(key.studioId, key.topicId);
});
