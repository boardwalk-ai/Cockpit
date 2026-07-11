import '../../domain/entities/topic.dart';
import 'ai_service.dart';

/// Offline stand-in for a real AI provider. Produces grounded-sounding tutor
/// replies from the topic's own fields so the Teach Me UI is fully usable
/// before any provider is connected.
class StubAiService implements AiService {
  const StubAiService();

  @override
  Future<String> teach({required Topic topic, required String message}) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final m = message.toLowerCase();

    if (m.contains('simpl') || m.contains('eli5')) {
      return '${topic.simpleExplanation}\n\n_(Based on your uploaded material for "${topic.title}".)_';
    }
    if (m.contains('example')) {
      final ex = topic.examples.isNotEmpty
          ? topic.examples.map((e) => '• $e').join('\n')
          : 'The material doesn\'t list explicit examples for this topic.';
      return 'Here are examples for ${topic.title}:\n\n$ex';
    }
    if (m.contains('mistake')) {
      final cm = topic.commonMistakes.isNotEmpty
          ? topic.commonMistakes.map((e) => '• $e').join('\n')
          : 'No common mistakes were captured for this topic.';
      return 'Watch out for these:\n\n$cm';
    }
    if (m.contains('why') || m.contains('matter')) {
      return topic.whyItMatters;
    }
    if (m.contains('analogy')) {
      final hook = topic.memoryHooks.isNotEmpty
          ? topic.memoryHooks.first
          : 'Think of it as a familiar everyday process that mirrors "${topic.title}".';
      return 'A way to remember it: $hook';
    }
    if (m.contains('step')) {
      return '${topic.detailedExplanation}\n\nWalk through it one step at a time and ask me about any step.';
    }
    if (m.contains('compare')) {
      final related = topic.relatedTopicIds.isNotEmpty
          ? topic.relatedTopicIds.join(', ')
          : 'related concepts';
      return 'Compared with $related, "${topic.title}" is defined as: ${topic.definition}';
    }

    // Default: grounded definition + offer.
    return '${topic.definition}\n\n${topic.simpleExplanation}\n\n'
        'Ask me to explain it simply, give an example, compare it, or make an analogy. '
        'I\'ll only use what\'s in your uploaded material for "${topic.title}".';
  }
}
