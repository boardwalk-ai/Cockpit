import 'dart:convert';

import 'package:http/http.dart' as http;

class GhostWriterApi {
  GhostWriterApi({this.baseUrl = 'http://127.0.0.1:8080'});

  final String baseUrl;

  Future<String> start(String instruction) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/ghostwriter/start'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'draft': {'instruction': instruction},
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Start failed: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['runId'] as String;
  }

  Stream<Map<String, dynamic>> events(String runId) async* {
    final client = http.Client();

    try {
      final request = http.Request(
        'GET',
        Uri.parse('$baseUrl/api/ghostwriter/run?runId=$runId'),
      );

      request.headers['Accept'] = 'text/event-stream';

      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Event stream failed: ${response.statusCode}');
      }

      await for (final line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (!line.startsWith('data: ')) continue;

        final raw = line.substring(6).trim();
        if (raw.isEmpty) continue;

        final decoded = jsonDecode(raw);

        if (decoded is Map<String, dynamic>) {
          yield decoded;
        }
      }
    } finally {
      client.close();
    }
  }

  Future<void> answer({
    required String runId,
    required String field,
    required dynamic value,
  }) async {
    await _post('/api/ghostwriter/answer', {
      'runId': runId,
      'field': field,
      'value': value,
    });
  }

  Future<void> message({required String runId, required String text}) async {
    await _post('/api/ghostwriter/runs/$runId/message', {'text': text});
  }

  Future<void> pause(String runId) async {
    await _post('/api/ghostwriter/pause', {'runId': runId});
  }

  Future<void> cancel(String runId) async {
    await _post('/api/ghostwriter/cancel', {'runId': runId});
  }

  Future<Map<String, dynamic>> workspace() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/ghostwriter/workspace'),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Workspace failed: ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> saveThread({
    required String title,
    required String prompt,
    required String status,
    required String essay,
    required String bibliography,
    required String citationStyle,
    required int wordCount,
    String? runId,
    String? folderId,
    List<Map<String, dynamic>> sources = const [],
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/ghostwriter/threads'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'runId': runId,
        'folderId': folderId,
        'title': title,
        'prompt': prompt,
        'status': status,
        'essay': essay,
        'bibliography': bibliography,
        'citationStyle': citationStyle,
        'wordCount': wordCount,
        'sources': sources,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Save failed: ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createFolder(String name) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/ghostwriter/folders'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Create folder failed: ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> _post(String path, Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('${response.statusCode}: ${response.body}');
    }
  }
}
