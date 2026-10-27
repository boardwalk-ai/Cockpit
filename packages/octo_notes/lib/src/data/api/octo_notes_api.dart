import 'dart:math';

import '../../domain/notes_session.dart';
import '../../domain/pairing.dart';
import 'notes_api_client.dart';

/// Typed access to every `octonotes-api` area. Resource-shaped on purpose:
/// screens compose these calls, so redesigning a panel never needs a new
/// endpoint. Rarely-typed payloads stay `Map<String, dynamic>` — the server
/// contract is `GET /v1/openapi.json`.
class OctoNotesApi {
  OctoNotesApi(this.client);

  final NotesApiClient client;

  static String newId() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
    final s = List.generate(16, h).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }

  // ── Home, sessions, courses, devices ──────────────────────────────────────
  Future<HomeData> home() async => HomeData.fromJson(await client.getJson('/v1/home'));

  Future<SessionPage> sessions({String? query, String? courseId, List<String>? status, String? cursor, int limit = 20}) async {
    final q = <String, String>{
      if (query != null && query.isNotEmpty) 'q': query,
      'courseId': ?courseId,
      if (status != null && status.isNotEmpty) 'status': status.join(','),
      'cursor': ?cursor,
      'limit': '$limit',
    };
    return SessionPage.fromJson(await client.getJson('/v1/sessions?${Uri(queryParameters: q).query}'));
  }

  Future<NotesSession> createSession({
    String? id,
    String? title,
    String? courseId,
    String workspaceMode = 'typewriter',
    Map<String, bool>? config,
    String? deckRef,
  }) async {
    final json = await client.postJson('/v1/sessions', {
      'id': id ?? newId(),
      'title': ?title,
      'courseId': ?courseId,
      'workspaceMode': workspaceMode,
      'config': ?config,
      'deckRef': ?deckRef,
    });
    return NotesSession.fromJson(json);
  }

  Future<Map<String, dynamic>> sessionSnapshot(String id) => client.getJson('/v1/sessions/$id');
  Future<NotesSession> updateSession(String id, Map<String, dynamic> patch) async =>
      NotesSession.fromJson(await client.patchJson('/v1/sessions/$id', patch));
  Future<void> deleteSession(String id) => client.delete('/v1/sessions/$id');
  Future<List<dynamic>> courses() => client.getList('/v1/courses');
  Future<Map<String, dynamic>> createCourse(String name, {String? color}) =>
      client.postJson('/v1/courses', {'name': name, 'color': ?color});
  Future<Map<String, dynamic>> registerDevice(String id, String name, String platform) =>
      client.postJson('/v1/devices', {'id': id, 'name': name, 'platform': platform});
  Future<List<dynamic>> deckDestinations() => client.getList('/v1/deck/destinations');

  // ── Recording on another phone (pairing) ──────────────────────────────────
  /// The receiver (this device, where the session is worked on) asks for a code.
  Future<Pairing> createPairing(String receiverDeviceId) async =>
      Pairing.fromJson(await client.postJson('/v1/pairings', {'receiverDeviceId': receiverDeviceId}));

  /// The other phone: [code] typed in, or [secret] (the QR's text).
  Future<Pairing> claimPairing({String? code, String? secret, required String deviceId}) async =>
      Pairing.fromJson(await client.postJson('/v1/pairings/claim', {
        'code': ?code,
        'secret': ?secret,
        'deviceId': deviceId,
      }));
  Future<Pairing> pairing(String id) async => Pairing.fromJson(await client.getJson('/v1/pairings/$id'));
  Future<Pairing> startPairing(String id, String sessionId) async =>
      Pairing.fromJson(await client.postJson('/v1/pairings/$id/start', {'sessionId': sessionId}));
  Future<void> cancelPairing(String id) => client.delete('/v1/pairings/$id');

  // ── Typewriter blocks + ink ───────────────────────────────────────────────
  Future<Map<String, dynamic>> blocks(String sessionId, {int? sinceRev}) =>
      client.getJson('/v1/sessions/$sessionId/blocks${sinceRev == null ? '' : '?sinceRev=$sinceRev'}');
  Future<Map<String, dynamic>> blockOps(String sessionId, List<Map<String, dynamic>> ops, {String? deviceId}) =>
      client.postJson('/v1/sessions/$sessionId/blocks/ops', {'deviceId': ?deviceId, 'ops': ops});
  Future<List<dynamic>> blockHistory(String blockId) => client.getList('/v1/blocks/$blockId/history');
  Future<Map<String, dynamic>> restoreBlock(String blockId, int revision) =>
      client.postJson('/v1/blocks/$blockId/restore', {'revision': revision});
  Future<Map<String, dynamic>> blockFromSource(String sessionId, String kind, String sourceId, {String? afterBlockId}) =>
      client.postJson('/v1/sessions/$sessionId/blocks/from-source', {'kind': kind, 'sourceId': sourceId, 'afterBlockId': ?afterBlockId});
  Future<Map<String, dynamic>> inkPages(String sessionId) => client.getJson('/v1/sessions/$sessionId/ink/pages');
  Future<Map<String, dynamic>> addInkPage(String sessionId, {String? id, String background = 'blank'}) =>
      client.postJson('/v1/sessions/$sessionId/ink/pages', {'id': id ?? newId(), 'background': background});
  Future<Map<String, dynamic>> strokeOps(String pageId, List<Map<String, dynamic>> ops, {String? deviceId}) =>
      client.postJson('/v1/ink/pages/$pageId/ops', {'deviceId': ?deviceId, 'ops': ops});
  Future<Map<String, dynamic>> inkStrokes(String pageId) => client.getJson('/v1/ink/pages/$pageId/strokes');
  Future<Map<String, dynamic>> inkRecognitions(String pageId) => client.getJson('/v1/ink/pages/$pageId/recognitions');

  /// Reads the strokes as a formula on the server; returns its LaTeX.
  Future<Map<String, dynamic>> inkFormula(String pageId, List<String> strokeIds) =>
      client.postJson('/v1/ink/pages/$pageId/formula', {'strokeIds': strokeIds});

  /// Text the phone read itself from a line of handwriting.
  Future<Map<String, dynamic>> addInkRecognition(String pageId, List<String> strokeIds, String text, double confidence) =>
      client.postJson('/v1/ink/pages/$pageId/recognitions', {'strokeIds': strokeIds, 'text': text, 'confidence': confidence});
  Future<Map<String, dynamic>> recognizeInk(String pageId, List<String> strokeIds) =>
      client.postJson('/v1/ink/pages/$pageId/recognize', {'strokeIds': strokeIds});

  // ── Capture + transcript ──────────────────────────────────────────────────
  Future<Map<String, dynamic>> startRecording(String sessionId, String deviceId,
          {String? id, String? container, int? sampleRate, int? chunkMs}) =>
      client.postJson('/v1/sessions/$sessionId/recordings', {
        'id': id ?? newId(),
        'deviceId': deviceId,
        'container': ?container,
        'sampleRate': ?sampleRate,
        'chunkMs': ?chunkMs,
      });
  Future<List<dynamic>> recordings(String sessionId) => client.getList('/v1/sessions/$sessionId/recordings');

  /// Devices in the session: `{deviceId, name, platform, role, isRecording, online}`.
  Future<List<dynamic>> sessionDevices(String sessionId) => client.getList('/v1/sessions/$sessionId/devices');

  /// A photo of the board, kept with the session's materials.
  Future<Map<String, dynamic>> uploadBoardPhoto(String sessionId, List<int> bytes, {String filename = 'board.jpg'}) =>
      client.postFile('/v1/sessions/$sessionId/materials', bytes, filename,
          filename.endsWith('.png') ? 'image/png' : 'image/jpeg', fields: {'kind': 'whiteboardPhoto'});
  Future<Map<String, dynamic>> setRecordingState(String recordingId, String state, {int? durationMs}) =>
      client.patchJson('/v1/recordings/$recordingId', {'state': state, 'durationMs': ?durationMs});
  Future<Map<String, dynamic>> uploadChunk(String recordingId, int seq, List<int> audio,
          {required int startMs, required int durationMs, String contentType = 'audio/ogg', String? sha256}) =>
      client.putBytes('/v1/recordings/$recordingId/chunks/$seq?startMs=$startMs&durationMs=$durationMs', audio, contentType,
          headers: {'x-chunk-sha256': ?sha256});
  Future<Map<String, dynamic>> manifest(String recordingId) => client.getJson('/v1/recordings/$recordingId/manifest');
  Future<Map<String, dynamic>> completeRecording(String recordingId, int lastSeq) =>
      client.postJson('/v1/recordings/$recordingId/complete', {'lastSeq': lastSeq});
  Future<Map<String, dynamic>> audioLink(String recordingId) => client.getJson('/v1/recordings/$recordingId/audio');
  Future<Map<String, dynamic>> transcript(String sessionId, {String? filter, String? query, int? sinceRev}) {
    final q = <String, String>{'filter': ?filter, 'q': ?query, if (sinceRev != null) 'sinceRev': '$sinceRev'};
    return client.getJson('/v1/sessions/$sessionId/transcript?${Uri(queryParameters: q).query}');
  }

  Future<Map<String, dynamic>> correctSegment(String segmentId, {String? text, String? speaker}) =>
      client.patchJson('/v1/transcript/segments/$segmentId', {'correctedText': ?text, 'speaker': ?speaker});
  Future<Map<String, dynamic>> setTranscription(String sessionId, bool on) =>
      client.postJson('/v1/sessions/$sessionId/transcription', {'on': on});
  Future<List<dynamic>> markers(String sessionId) => client.getList('/v1/sessions/$sessionId/markers');
  Future<Map<String, dynamic>> addMarker(String sessionId, String type, int atMs) =>
      client.postJson('/v1/sessions/$sessionId/markers', {'type': type, 'atMs': atMs});

  /// Throws [NotesApiException] with code `other_device_recording` (details:
  /// devices) when another device is still recording and [mode] is null.
  Future<Map<String, dynamic>> finish(String sessionId, {String? deviceId, String? mode}) =>
      client.postJson('/v1/sessions/$sessionId/finish', {'deviceId': ?deviceId, 'mode': ?mode});

  // ── AI (SSE) ──────────────────────────────────────────────────────────────
  Stream<SseEvent> suggest(String sessionId, String blockId, String action) =>
      client.sse('/v1/sessions/$sessionId/ai/suggest', {'blockId': blockId, 'action': action});
  Future<Map<String, dynamic>> applySuggestion(String id, String mode, {String? selection, int? baseRevision}) =>
      client.postJson('/v1/ai/suggestions/$id/apply', {'mode': mode, 'selection': ?selection, 'baseRevision': ?baseRevision});
  Stream<SseEvent> command(String sessionId, String command, {List<Map<String, dynamic>> contexts = const []}) =>
      client.sse('/v1/sessions/$sessionId/ai/command', {'command': command, 'contexts': contexts});
  Stream<SseEvent> summarize(String sessionId) => client.sse('/v1/sessions/$sessionId/summarize');
  Stream<SseEvent> research(String sessionId, String question, {String scope = 'courseFirst', String depth = 'standard'}) =>
      client.sse('/v1/sessions/$sessionId/research', {'question': question, 'scope': scope, 'depth': depth});
  Future<Map<String, dynamic>> relevant(String sessionId, {String? query}) =>
      client.getJson('/v1/sessions/$sessionId/relevant${query == null ? '' : '?q=${Uri.encodeQueryComponent(query)}'}');
  Future<Map<String, dynamic>> organizePreview(String sessionId) => client.postJson('/v1/sessions/$sessionId/organize/preview');
  Future<Map<String, dynamic>> organizeApply(String passId, {List<String>? ids}) =>
      client.postJson('/v1/organize/$passId/apply', ids == null ? {'all': true} : {'suggestionIds': ids});
  Future<Map<String, dynamic>> organizeUndo(String passId) => client.postJson('/v1/organize/$passId/undo');

  // ── Review, finalize, Study Studio ────────────────────────────────────────
  Future<Map<String, dynamic>> prepareReview(String sessionId) => client.postJson('/v1/sessions/$sessionId/review/prepare');
  Future<Map<String, dynamic>> review(String reviewId) => client.getJson('/v1/reviews/$reviewId');
  Future<Map<String, dynamic>> finalizeSummary(String sessionId) => client.getJson('/v1/sessions/$sessionId/finalize/summary');
  Future<Map<String, dynamic>> finalize(String sessionId, {List<String>? includedTopics, String? title, required String idempotencyKey}) =>
      client.postJson('/v1/sessions/$sessionId/finalize', {'includedTopics': ?includedTopics, 'title': ?title},
          {'idempotency-key': idempotencyKey});
  Future<Map<String, dynamic>> export(String finalNotesId, String format) =>
      client.postJson('/v1/final-notes/$finalNotesId/export', {'format': format});
  Future<Map<String, dynamic>> exportStatus(String exportId) => client.getJson('/v1/exports/$exportId');
  Future<Map<String, dynamic>> finalNotes(String id) => client.getJson('/v1/final-notes/$id');
  /// A session's final notes, every version.
  Future<List<dynamic>> finalNotesOf(String sessionId) => client.getList('/v1/final-notes?sessionId=$sessionId');
  /// A page of a material (a board photo, a slide) as an image link.
  Future<Map<String, dynamic>> materialImage(String materialId, int page) => client.getJson('/v1/materials/$materialId/pages/$page/image');
  Future<List<dynamic>> materials(String sessionId) => client.getList('/v1/sessions/$sessionId/materials');
  Future<Map<String, dynamic>> recommendations(String finalNotesId) => client.getJson('/v1/final-notes/$finalNotesId/recommendations');
  Future<Map<String, dynamic>> createConversion(String finalNotesId, {List<String>? topicIds}) =>
      client.postJson('/v1/conversions', {'finalNotesId': finalNotesId, 'topicIds': ?topicIds});
  Future<Map<String, dynamic>> generate(String conversionId) => client.postJson('/v1/conversions/$conversionId/generate');
  Stream<SseEvent> conversionProgress(String conversionId) => client.sseGet('/v1/conversions/$conversionId/progress');
}
