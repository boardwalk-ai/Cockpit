import 'package:cockpit_module/cockpit_module.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'presentation/conversion/conversion_preview_page.dart';
import 'presentation/home/octo_notes_home_page.dart';
import 'presentation/live/live_session_hub_page.dart';
import 'presentation/live/session_finalize_page.dart';
import 'presentation/recommendations/final_notes_page.dart';
import 'presentation/record/octo_notes_record_page.dart';
import 'presentation/review/session_review_page.dart';
import 'presentation/session/octo_notes_session_page.dart';

/// OctoNotes as a pluggable Cockpit module. The shell mounts this only when
/// `octo_notes_enabled` is on.
class OctoNotesModule extends CockpitModule {
  const OctoNotesModule();

  @override
  String get id => 'octo_notes';

  @override
  String get title => 'OctoNotes';

  @override
  String get description =>
      'Capture lectures, transcribe them, and turn them into AI notes.';

  @override
  IconData get icon => Icons.mic_none_rounded;

  @override
  Color? get accentColor => const Color(0xFFE11D2E); // brand red

  @override
  String get rootPath => '/notes';

  @override
  bool get enabledByDefault => true;

  @override
  List<RouteBase> routes() => [
    GoRoute(
      path: '/notes',
      builder: (_, _) => const OctoNotesHomePage(),
      routes: [
        // Panel 3 (redesign) — the Live Session Hub replaces the old combined
        // workspace at /notes/session; Typewriter/Magic Pencil open in place.
        // The old full workspace is kept at /notes/session/full for reference.
        GoRoute(
          path: 'session',
          builder: (_, _) => const LiveSessionHubPage(),
          routes: [
            GoRoute(
              path: 'full',
              builder: (_, _) => const OctoNotesSessionPage(),
            ),
          ],
        ),
        GoRoute(
          path: 'record',
          builder: (_, _) => const OctoNotesRecordPage(),
        ),
        // Panel 3 redesign — the simplified Finalize / export screen the hub's
        // Finalize button opens (replaces Panel 13 in the redesign flow).
        GoRoute(
          path: 'finalize',
          builder: (_, _) => const SessionFinalizePage(),
        ),
        GoRoute(
          path: 'review',
          builder: (_, _) => const SessionReviewPage(),
        ),
        GoRoute(
          path: 'final',
          builder: (_, _) => const FinalNotesPage(),
        ),
        GoRoute(
          path: 'convert',
          builder: (_, _) => const ConversionPreviewPage(),
        ),
      ],
    ),
  ];
}
