import 'package:flutter/foundation.dart';

/// A session as the API returns it (`/v1/sessions`, `/v1/home`).
@immutable
class NotesSession {
  const NotesSession({
    required this.id,
    required this.title,
    required this.status,
    required this.workspaceMode,
    required this.updatedAt,
    this.courseId,
    this.deckRef,
    this.durationMs = 0,
  });

  factory NotesSession.fromJson(Map<String, dynamic> j) => NotesSession(
        id: j['id'] as String,
        title: (j['title'] as String?) ?? 'Untitled session',
        status: (j['status'] as String?) ?? 'draft',
        workspaceMode: (j['workspaceMode'] as String?) ?? 'typewriter',
        updatedAt: DateTime.tryParse((j['updatedAt'] as String?) ?? '') ?? DateTime.now(),
        courseId: j['courseId'] as String?,
        deckRef: j['deckRef'] as String?,
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String title;

  /// draft · live · paused · ended · reviewing · finalized · archived
  final String status;
  final String workspaceMode;
  final DateTime updatedAt;
  final String? courseId;
  final String? deckRef;
  final int durationMs;

  bool get isFinalized => status == 'finalized';
}

@immutable
class SessionPage {
  const SessionPage(this.items, this.nextCursor);

  factory SessionPage.fromJson(Map<String, dynamic> j) => SessionPage(
        [for (final s in (j['items'] as List? ?? const [])) NotesSession.fromJson(s as Map<String, dynamic>)],
        j['nextCursor'] as String?,
      );

  final List<NotesSession> items;
  final String? nextCursor;
}

/// `GET /v1/home` — data only; the Home screen decides how to show it.
@immutable
class HomeData {
  const HomeData({
    this.live = const [],
    this.continueSessions = const [],
    this.recent = const [],
    this.processing = const [],
    this.recommended = const [],
  });

  factory HomeData.fromJson(Map<String, dynamic> j) {
    List<NotesSession> sessions(String k) =>
        [for (final s in (j[k] as List? ?? const [])) NotesSession.fromJson(s as Map<String, dynamic>)];
    return HomeData(
      live: sessions('live'),
      continueSessions: sessions('continue'),
      recent: sessions('recent'),
      processing: [for (final p in (j['processing'] as List? ?? const [])) p as Map<String, dynamic>],
      recommended: [for (final r in (j['recommended'] as List? ?? const [])) r as Map<String, dynamic>],
    );
  }

  final List<NotesSession> live;
  final List<NotesSession> continueSessions;
  final List<NotesSession> recent;
  final List<Map<String, dynamic>> processing;
  final List<Map<String, dynamic>> recommended;
}
