import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../data/api/octo_notes_api.dart';
import '../domain/notes_session.dart';

/// Opens a session where it is in its life: still running → back into it
/// with the mic off; ended → Finalize; finalized → its final notes.
Future<void> openSession(BuildContext context, OctoNotesApi? api, NotesSession s) async {
  final router = GoRouter.of(context);
  switch (s.status) {
    case 'ended' || 'reviewing':
      router.go('/notes/finalize?id=${s.id}');
    case 'finalized' || 'archived':
      String? id;
      try {
        id = (await api?.finalNotesOf(s.id))?.cast<Map<String, dynamic>>().firstOrNull?['id'] as String?;
      } on Object {
        id = null;
      }
      router.go(id == null ? '/notes/finalize?id=${s.id}' : '/notes/final?id=$id');
    default:
      // Reopening must never start a recording by itself.
      router.go('/notes/session?id=${s.id}&role=solo&record=0');
  }
}
