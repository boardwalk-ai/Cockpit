import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/hein_analysis.dart';
import 'backend_config.dart';
import 'http_tools_service.dart';

/// Assignment analyzer — OctopilotWeb's Hein agent (`POST /api/hein/analyze`).
abstract interface class HeinService {
  Future<HeinAnalysis> analyze({
    required String instructions,
    String essayType = '',
  });
}

HeinService createHeinService({http.Client? client}) {
  final base = kDocOctApiBase.isNotEmpty
      ? kDocOctApiBase.replaceAll(RegExp(r'/$'), '')
      : '/api';
  return HttpHeinService(base, client: client, token: authTokenSource);
}

class HttpHeinService implements HeinService {
  HttpHeinService(this.baseUrl, {http.Client? client, this.token})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  final Future<String?> Function()? token;

  @override
  Future<HeinAnalysis> analyze({
    required String instructions,
    String essayType = '',
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final t = await token?.call();
    if (t != null && t.isNotEmpty) headers['Authorization'] = 'Bearer $t';

    final r = await _client.post(
      Uri.parse('$baseUrl/hein/analyze'),
      headers: headers,
      body: jsonEncode({
        'instructions': instructions,
        'essayType': essayType,
      }),
    );
    if (r.statusCode >= 400) {
      throw ToolsException(_errorMessage(r));
    }
    return HeinAnalysis.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  String _errorMessage(http.Response r) {
    try {
      final body = jsonDecode(r.body);
      if (body is Map && body['error'] is String) return body['error'] as String;
    } catch (_) {}
    return 'Hein analysis failed (${r.statusCode})';
  }
}
