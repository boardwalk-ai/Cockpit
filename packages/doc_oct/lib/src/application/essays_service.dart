import 'dart:convert';

import 'package:http/http.dart' as http;

/// The signed-in user + credits, from `/v1/me`.
class Me {
  const Me({
    required this.uid,
    this.email,
    this.name,
    this.photoUrl,
    this.plan,
    this.octoCredits = 0,
    this.wordCredits = 0,
    this.sourceCredits = 0,
    this.humanizerCredits = 0,
    this.hasAccount = false,
  });

  final String uid;
  final String? email;
  final String? name;
  final String? photoUrl;
  final String? plan;
  final int octoCredits;
  final int wordCredits;
  final int sourceCredits;
  final int humanizerCredits;

  /// False when the token is valid but the user has no row in the shared DB yet.
  final bool hasAccount;

  factory Me.fromJson(Map<String, dynamic> j) {
    final u = j['user'] as Map<String, dynamic>?;
    int n(dynamic v) => (v as num?)?.toInt() ?? 0;
    return Me(
      uid: (j['uid'] ?? '') as String,
      email: (u?['email'] ?? j['email']) as String?,
      name: u?['name'] as String?,
      photoUrl: u?['photoUrl'] as String?,
      plan: u?['plan'] as String?,
      octoCredits: n(u?['octoCredits']),
      wordCredits: n(u?['wordCredits']),
      sourceCredits: n(u?['sourceCredits']),
      humanizerCredits: n(u?['humanizerCredits']),
      hasAccount: u != null,
    );
  }
}

/// A saved document (full content).
class SavedEssay {
  const SavedEssay({
    required this.id,
    required this.title,
    required this.content,
    this.wordCount = 0,
    this.citationStyle,
    this.updatedAt,
  });
  final String id;
  final String title;
  final String content;
  final int wordCount;
  final String? citationStyle;
  final String? updatedAt;

  factory SavedEssay.fromJson(Map<String, dynamic> j) => SavedEssay(
        id: (j['id'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        content: (j['content'] ?? '') as String,
        wordCount: (j['wordCount'] as num?)?.toInt() ?? 0,
        citationStyle: j['citationStyle'] as String?,
        updatedAt: j['updatedAt'] as String?,
      );
}

/// A saved-document list item (with a snippet, no full content).
class EssayListItem {
  const EssayListItem({
    required this.id,
    required this.title,
    this.wordCount = 0,
    this.citationStyle,
    this.updatedAt,
    this.snippet = '',
  });
  final String id;
  final String title;
  final int wordCount;
  final String? citationStyle;
  final String? updatedAt;
  final String snippet;

  factory EssayListItem.fromJson(Map<String, dynamic> j) => EssayListItem(
        id: (j['id'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        wordCount: (j['wordCount'] as num?)?.toInt() ?? 0,
        citationStyle: j['citationStyle'] as String?,
        updatedAt: j['updatedAt'] as String?,
        snippet: (j['snippet'] ?? '') as String,
      );
}

/// Talks to the backend's authed endpoints — `/v1/me` and `/v1/essays`.
class EssaysService {
  EssaysService(this.baseUrl, {http.Client? client, this.token})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  final Future<String?> Function()? token;

  Uri _u(String p) => Uri.parse('$baseUrl$p');

  Future<Map<String, String>> _headers([Map<String, String>? extra]) async {
    final h = <String, String>{if (extra != null) ...extra};
    final t = await token?.call();
    if (t != null && t.isNotEmpty) h['Authorization'] = 'Bearer $t';
    return h;
  }

  String _err(http.Response r) {
    try {
      final b = jsonDecode(r.body);
      if (b is Map && b['error'] is String) return b['error'] as String;
    } catch (_) {}
    return 'Request failed (${r.statusCode})';
  }

  /// Whoami + credits. Returns null when signed out (401).
  Future<Me?> me() async {
    final r = await _client.get(_u('/v1/me'), headers: await _headers());
    if (r.statusCode == 401 || r.statusCode == 403) return null;
    if (r.statusCode >= 400) throw Exception(_err(r));
    return Me.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<List<EssayListItem>> list() async {
    final r = await _client.get(_u('/v1/essays'), headers: await _headers());
    if (r.statusCode >= 400) throw Exception(_err(r));
    return (jsonDecode(r.body) as List)
        .map((e) => EssayListItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<SavedEssay> get(String id) async {
    final r = await _client.get(_u('/v1/essays/$id'), headers: await _headers());
    if (r.statusCode >= 400) throw Exception(_err(r));
    return SavedEssay.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// Creates ([id] null) or updates a document; returns the saved row.
  Future<SavedEssay> save({
    String? id,
    required String title,
    required String content,
    int wordCount = 0,
    String? citationStyle,
  }) async {
    final r = await _client.post(
      _u('/v1/essays'),
      headers: await _headers({'Content-Type': 'application/json'}),
      body: jsonEncode({
        if (id != null) 'id': id,
        'title': title,
        'content': content,
        'wordCount': wordCount,
        'citationStyle': citationStyle,
      }),
    );
    if (r.statusCode >= 400) throw Exception(_err(r));
    return SavedEssay.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<void> delete(String id) async {
    final r =
        await _client.delete(_u('/v1/essays/$id'), headers: await _headers());
    if (r.statusCode >= 400) throw Exception(_err(r));
  }
}
