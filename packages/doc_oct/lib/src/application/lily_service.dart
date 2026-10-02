import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/hein_analysis.dart';
import '../domain/outline.dart';
import 'backend_config.dart';
import 'http_tools_service.dart';

/// Lily — guided outline generation (`POST /api/lily/generate`).
///
/// Modes match the web wizard:
/// * `auto` — full intro / body / conclusion set
/// * `build` — one section from a user prompt + type
/// * `single` — one Introduction, Body Paragraph, or Conclusion
abstract interface class LilyService {
  Future<List<OutlineData>> generate({
    required LilyMode mode,
    HeinAnalysis? analysis,
    String essayTopic = '',
    String? requestedType,
    String? customTitle,
    int? count,
    bool bullets = true,
  });
}

enum LilyMode {
  auto,
  build,
  single;

  String get apiValue => name;
}

LilyService createLilyService({http.Client? client}) {
  final base = kDocOctApiBase.isNotEmpty
      ? kDocOctApiBase.replaceAll(RegExp(r'/$'), '')
      : '/api';
  return HttpLilyService(base, client: client, token: authTokenSource);
}

class HttpLilyService implements LilyService {
  HttpLilyService(this.baseUrl, {http.Client? client, this.token})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  final Future<String?> Function()? token;

  @override
  Future<List<OutlineData>> generate({
    required LilyMode mode,
    HeinAnalysis? analysis,
    String essayTopic = '',
    String? requestedType,
    String? customTitle,
    int? count,
    bool bullets = true,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final t = await token?.call();
    if (t != null && t.isNotEmpty) headers['Authorization'] = 'Bearer $t';

    final topic = (analysis?.essayTopic.trim().isNotEmpty == true)
        ? analysis!.essayTopic
        : essayTopic;
    final r = await _client.post(
      Uri.parse('$baseUrl/lily/generate'),
      headers: headers,
      body: jsonEncode({
        'analysis': analysis?.analysis ?? '',
        'essayTopic': topic,
        'essayType': analysis?.essayType ?? '',
        'scope': analysis?.scope ?? '',
        'structure': analysis?.structure ?? '',
        'mode': mode.apiValue,
        if (requestedType != null) 'requestedType': requestedType,
        if (customTitle != null) 'customTitle': customTitle,
        if (mode == LilyMode.auto) 'count': count ?? 5,
        'bullets': bullets,
      }),
    );
    if (r.statusCode >= 400) {
      throw ToolsException(_errorMessage(r));
    }
    final body = jsonDecode(r.body);
    final list = body is Map
        ? (body['outlines'] as List? ?? const [])
        : (body is List ? body : const []);
    return list
        .map((o) => OutlineData.fromJson(o as Map<String, dynamic>))
        .toList();
  }

  String _errorMessage(http.Response r) {
    try {
      final body = jsonDecode(r.body);
      if (body is Map && body['error'] is String) return body['error'] as String;
    } catch (_) {}
    return 'Lily generation failed (${r.statusCode})';
  }
}
