import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'sse_client.dart';

/// Uploads study materials and waits for RAG ingestion.
///
/// Upload is a multipart POST (the documents endpoint returns a JSON job);
/// [watchBuild] then reads the build SSE stream, which stays open until the job
/// finishes — so the returned Future completes on `done` and throws on failure.
/// Everything binds to the authenticated user server-side.
class UploadApi {
  // ignore: prefer_initializing_formals — public name differs from field
  UploadApi({required SseClient sse}) : _sse = sse;

  final SseClient _sse;

  /// Uploads [bytes] as a document under [studioId]; returns the ingest job id.
  Future<String> uploadDocument({
    required String studioId,
    required String filename,
    required Uint8List bytes,
  }) async {
    final headers = await _sse.authHeaders()
      ..remove('Accept') // the upload response is JSON, not an event stream
      // One key per picked file: a retry after a lost response gets the
      // first upload's job instead of a second copy.
      ..['Idempotency-Key'] = newRequestId();
    Future<http.Response> send() async {
      final req =
          http.MultipartRequest(
              'POST',
              Uri.parse('${_sse.baseUrl}/studios/$studioId/documents'),
            )
            ..headers.addAll(headers)
            ..files.add(
              http.MultipartFile.fromBytes('file', bytes, filename: filename),
            );
      return http.Response.fromStream(await req.send());
    }

    http.Response resp;
    try {
      resp = await send();
    } on http.ClientException {
      resp = await send();
    }
    if (resp.statusCode >= 400) {
      throw SseException('Upload failed: HTTP ${resp.statusCode}');
    }
    final job = jsonDecode(resp.body) as Map<String, dynamic>;
    return job['id'] as String;
  }

  /// Completes when ingestion finishes; throws [SseException] if it fails.
  Future<void> watchBuild({
    required String studioId,
    required String jobId,
  }) async {
    await _sse.get('/studios/$studioId/build/$jobId');
  }

  /// Kick off the studio-level generation pass over ALL uploaded files; returns
  /// the build id. Runs in the background — poll [buildSnapshot] for progress.
  Future<String> startBuild({required String studioId}) async {
    final events = await _sse.post('/studios/$studioId/build');
    final data = events.firstWhere(
      (e) => e.event == 'data',
      orElse: () => throw SseException('Build did not start'),
    );
    return data.data['buildId'] as String;
  }

  /// One-shot current build state — the dashboard polls this for a live banner.
  Future<BuildSnapshot> buildSnapshot({
    required String studioId,
    required String buildId,
  }) async {
    final events = await _sse.get(
      '/studios/$studioId/build-status/$buildId',
      query: {'snapshot': '1'},
    );
    final p = events.firstWhere(
      (e) => e.event == 'progress',
      orElse: () => throw SseException('No build status'),
    );
    final d = p.data;
    final status = d['status'] as String? ?? 'queued';
    final lessonsDone = (d['lessonsDone'] as num?)?.toInt() ?? 0;
    final lessonsTotal = (d['lessonsTotal'] as num?)?.toInt() ?? 0;
    final pct =
        (d['progressPct'] as num?)?.toDouble() ??
        BuildSnapshot.estimateProgress(
          status: status,
          lessonsDone: lessonsDone,
          lessonsTotal: lessonsTotal,
        );
    return BuildSnapshot(
      status: status,
      stage: d['stage'] as String? ?? '',
      lessonsDone: lessonsDone,
      lessonsTotal: lessonsTotal,
      progressPct: pct,
    );
  }
}

/// A snapshot of a studio build's progress.
class BuildSnapshot {
  const BuildSnapshot({
    required this.status,
    required this.stage,
    required this.lessonsDone,
    required this.lessonsTotal,
    required this.progressPct,
  });

  final String status; // queued|extracting|generating|scenarios|done|failed
  final String stage;
  final int lessonsDone;
  final int lessonsTotal;

  /// 0..1 weighted real progress from the server (or [estimateProgress]).
  final double progressPct;

  bool get isDone => status == 'done';
  bool get isFailed => status == 'failed';
  bool get inProgress => !isDone && !isFailed;

  /// Mirrors backend `_build_progress_pct` when the field is absent.
  static double estimateProgress({
    required String status,
    required int lessonsDone,
    required int lessonsTotal,
  }) {
    switch (status) {
      case 'done':
        return 1;
      case 'failed':
        return 0;
      case 'queued':
        return 0.02;
      case 'extracting':
        if (lessonsTotal > 0) {
          final frac = (lessonsDone / lessonsTotal).clamp(0.0, 1.0);
          return 0.02 + 0.18 * frac;
        }
        return 0.08;
      case 'generating':
        if (lessonsTotal <= 0) return 0.25;
        final frac = (lessonsDone / lessonsTotal).clamp(0.0, 1.0);
        return 0.25 + 0.60 * frac;
      case 'scenarios':
        return 0.92;
      default:
        return 0.05;
    }
  }
}
