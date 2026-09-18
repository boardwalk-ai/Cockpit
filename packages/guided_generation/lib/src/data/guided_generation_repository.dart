import 'package:cockpit_core/cockpit_core.dart';

import '../formatters/citation_formatter.dart';

const _defaultApiBaseUrl = String.fromEnvironment(
  'GUIDED_GENERATION_API_URL',
  defaultValue: 'http://localhost:8200',
);

class GuidedEditorThread {
  const GuidedEditorThread({
    required this.id,
    required this.title,
    required this.plainText,
    required this.citationStyle,
    required this.sources,
    required this.runState,
    this.delta,
  });

  final String id;
  final String title;
  final String plainText;
  final CitationStyle citationStyle;
  final List<CitationSource> sources;
  final Map<String, dynamic> runState;
  final List<dynamic>? delta;

  factory GuidedEditorThread.fromJson(Map<String, dynamic> json) {
    final runState = _asStringMap(json['runState']);
    final editor = _asStringMap(runState['editor']);
    final rawSources = editor['sources'];

    return GuidedEditorThread(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled essay',
      plainText: json['essay']?.toString() ?? '',
      citationStyle: CitationStyleX.fromLabel(
        json['citationStyle']?.toString(),
      ),
      sources: rawSources is List
          ? rawSources
                .whereType<Map>()
                .map((source) => CitationSource.fromJson(source.cast()))
                .toList(growable: false)
          : const [],
      runState: runState,
      delta: editor['delta'] is List ? editor['delta'] as List<dynamic> : null,
    );
  }
}

abstract interface class GuidedGenerationRepository {
  Future<GuidedEditorThread?> loadEditor({String? threadId});

  Future<GuidedEditorThread> saveEditor({
    String? threadId,
    required String title,
    required String plainText,
    required int wordCount,
    required CitationStyle citationStyle,
    required List<dynamic> delta,
    required List<CitationSource> sources,
    Map<String, dynamic> runState = const {},
  });
}

class ApiGuidedGenerationRepository implements GuidedGenerationRepository {
  ApiGuidedGenerationRepository(this._client);

  factory ApiGuidedGenerationRepository.defaultClient() {
    return ApiGuidedGenerationRepository(
      ApiClient(
        const AppConfig(flavor: AppFlavor.dev, apiBaseUrl: _defaultApiBaseUrl),
      ),
    );
  }

  final ApiClient _client;

  @override
  Future<GuidedEditorThread?> loadEditor({String? threadId}) async {
    var resolvedId = threadId;
    if (resolvedId == null || resolvedId.trim().isEmpty) {
      final response = await _client.get<dynamic>(
        '/api/v1/ghostwriter/threads',
      );
      final rows = response.data;
      if (rows is! List || rows.isEmpty) return null;
      final first = rows.first;
      if (first is! Map || first['id'] == null) return null;
      resolvedId = first['id'].toString();
    }

    final response = await _client.get<dynamic>(
      '/api/v1/ghostwriter/threads/$resolvedId',
    );
    return GuidedEditorThread.fromJson(_asStringMap(response.data));
  }

  @override
  Future<GuidedEditorThread> saveEditor({
    String? threadId,
    required String title,
    required String plainText,
    required int wordCount,
    required CitationStyle citationStyle,
    required List<dynamic> delta,
    required List<CitationSource> sources,
    Map<String, dynamic> runState = const {},
  }) async {
    var resolvedId = threadId;
    if (resolvedId == null || resolvedId.trim().isEmpty) {
      final now = DateTime.now().microsecondsSinceEpoch;
      final created = await _client.post<dynamic>(
        '/api/v1/ghostwriter/threads',
        data: {
          'runId': 'guided-editor-$now',
          'prompt': title,
          'title': title,
          'wordCount': wordCount,
          'citationStyle': citationStyle.label,
        },
      );
      resolvedId = _asStringMap(created.data)['id']?.toString();
      if (resolvedId == null || resolvedId.isEmpty) {
        throw StateError('The backend created a thread without an id.');
      }
    }

    final nextRunState = Map<String, dynamic>.from(runState)
      ..['editor'] = {
        'delta': delta,
        'sources': sources.map((source) => source.toJson()).toList(),
      };

    final response = await _client.raw.patch<dynamic>(
      '/api/v1/ghostwriter/threads/$resolvedId',
      data: {
        'title': title,
        'status': 'finished',
        'essay': plainText,
        'wordCount': wordCount,
        'citationStyle': citationStyle.label,
        'runState': nextRunState,
      },
    );

    return GuidedEditorThread.fromJson(_asStringMap(response.data));
  }
}

Map<String, dynamic> _asStringMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return <String, dynamic>{};
}
