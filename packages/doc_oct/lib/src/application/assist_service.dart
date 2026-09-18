import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/outline.dart';

/// One chat turn in the OctoBot conversation.
class ChatTurn {
  const ChatTurn(this.role, this.text); // role: 'user' | 'assistant'
  final String role;
  final String text;

  Map<String, dynamic> toJson() => {'role': role, 'content': text};
}

/// OctoBot (essay critique chat) + outline generation. Both are OpenRouter-backed
/// on our Rust backend; the frontend never calls the model directly.
abstract interface class AssistService {
  Future<String> chat({
    required String message,
    required List<ChatTurn> history,
    required String tone, // 'mentor' | 'honest' | 'roast' | ...
    required String mode, // 'chat' | 'criticism'
    required String essay,
  });

  Future<List<OutlineData>> outline({
    required String topic,
    String assignment,
  });

  bool get isMock;
}

/// Offline stand-in — clearly-marked sample replies so the panel works without a
/// backend.
class MockAssistService implements AssistService {
  const MockAssistService();

  @override
  bool get isMock => true;

  Future<T> _delay<T>(T v) =>
      Future.delayed(const Duration(milliseconds: 500), () => v);

  @override
  Future<String> chat({
    required String message,
    required List<ChatTurn> history,
    required String tone,
    required String mode,
    required String essay,
  }) {
    if (mode == 'criticism' || message.toLowerCase().contains('critic')) {
      return _delay(
        'Here\'s a quick read (sample — Octo runs on the backend):\n\n'
        '• Thesis: clear, but could be sharper in the first paragraph.\n'
        '• Structure: the body flows well; the conclusion restates rather than '
        'extends.\n'
        '• Evidence: add one concrete source to the second body paragraph.\n\n'
        'Overall: a solid draft. Tighten the intro and you\'re in good shape.',
      );
    }
    return _delay(
      'Octo here 🐙 (sample reply — the real critique comes from the backend). '
      'Ask me to criticize your essay and I\'ll dig in.',
    );
  }

  @override
  Future<List<OutlineData>> outline({
    required String topic,
    String assignment = '',
  }) {
    final t = topic.trim().isEmpty ? 'your topic' : topic.trim();
    return _delay([
      OutlineData(
        type: 'Introduction',
        title: 'Introduction',
        description: 'Set up $t and state the thesis.',
        bullets: [
          'Hook the reader with a striking fact or question',
          'Give brief background on $t',
          'End with a clear, arguable thesis statement',
        ],
      ),
      OutlineData(
        type: 'Body Paragraph',
        title: 'First main point',
        description: 'Develop the strongest supporting argument.',
        bullets: [
          'Topic sentence stating the point',
          'Evidence and a cited example',
          'Explain how it supports the thesis',
        ],
      ),
      OutlineData(
        type: 'Body Paragraph',
        title: 'Counterargument & response',
        description: 'Acknowledge an opposing view and rebut it.',
        bullets: [
          'State the strongest objection fairly',
          'Respond with evidence',
          'Show why the thesis still holds',
        ],
      ),
      OutlineData(
        type: 'Conclusion',
        title: 'Conclusion',
        description: 'Synthesize and leave a final thought.',
        bullets: [
          'Restate the thesis in fresh words',
          'Draw the points together',
          'End with an implication or call to action',
        ],
      ),
    ]);
  }
}

/// Real backend-backed assistant (backend-rs `/v1/octobot/chat`, `/v1/outline`).
class HttpAssistService implements AssistService {
  HttpAssistService(this.baseUrl, {http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  @override
  bool get isMock => false;

  Uri _u(String p) => Uri.parse('$baseUrl$p');

  @override
  Future<String> chat({
    required String message,
    required List<ChatTurn> history,
    required String tone,
    required String mode,
    required String essay,
  }) async {
    final r = await _client.post(
      _u('/v1/octobot/chat'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'message': message,
        'history': history.map((t) => t.toJson()).toList(),
        'tone': tone,
        'mode': mode,
        'essay': essay,
      }),
    );
    if (r.statusCode >= 400) throw Exception(_err(r));
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    // Backend may return {type:'chat', message} or a structured critique which
    // we render as text for now.
    return (j['message'] ?? j['text'] ?? '') as String;
  }

  @override
  Future<List<OutlineData>> outline({
    required String topic,
    String assignment = '',
  }) async {
    final r = await _client.post(
      _u('/v1/outline'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'topic': topic, 'assignment': assignment}),
    );
    if (r.statusCode >= 400) throw Exception(_err(r));
    final body = jsonDecode(r.body);
    final list = body is List ? body : (body['outlines'] as List? ?? const []);
    return list
        .map((o) => OutlineData.fromJson(o as Map<String, dynamic>))
        .toList();
  }

  String _err(http.Response r) {
    try {
      final b = jsonDecode(r.body);
      if (b is Map && b['error'] is String) return b['error'] as String;
    } catch (_) {}
    return 'Request failed (${r.statusCode})';
  }
}
