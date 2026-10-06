import 'dart:convert';

import '../../domain/ask.dart';
import '../../domain/entities/topic.dart';
import '../ai/ai_service.dart';
import 'sse_client.dart';

/// [AiService] backed by the backend `/ask` SSE stream. Concatenates the streamed
/// `delta` events into the final grounded answer (the interface is Future-based;
/// swap to a Stream when the UI wants token-by-token rendering).
class ApiAiService implements AiService {
  ApiAiService({SseClient? client}) : _sse = client ?? SseClient();

  final SseClient _sse;

  @override
  Stream<AskEvent> ask({
    required String studioId,
    required String question,
    Topic? topic,
    List<AskTurn> history = const [],
  }) async* {
    final turns = history.length > 3
        ? history.sublist(history.length - 3)
        : history;
    await for (final e in _sse.stream(
      '/ask',
      query: {
        'studio_id': studioId,
        'q': question,
        if (topic != null) 'topic': topic.title,
        if (turns.isNotEmpty)
          'history': jsonEncode([for (final t in turns) t.toJson()]),
      },
    )) {
      switch (e.event) {
        case 'delta':
          final text = '${e.data['text'] ?? ''}';
          if (text.isNotEmpty) yield AskText(text);
        case 'citations':
          final list = e.data['value'];
          if (list is! List) continue;
          yield AskSources([
            for (final (i, c) in list.indexed)
              if (c is Map)
                AskSource(
                  number: i + 1,
                  fileName: c['fileName'] as String?,
                  snippet: '${c['snippet'] ?? ''}',
                ),
          ]);
      }
    }
  }

  @override
  Future<String> teach({required Topic topic, required String message}) async {
    final events = await _sse.get(
      '/ask',
      query: {'studio_id': topic.studioId, 'q': message},
    );
    final buffer = StringBuffer();
    for (final e in events.where((e) => e.event == 'delta')) {
      buffer.write(e.data['text'] ?? '');
    }
    return buffer.toString().trim();
  }
}
