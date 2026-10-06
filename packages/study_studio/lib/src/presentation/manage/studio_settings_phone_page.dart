import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../dashboard/dashboard_page.dart' show confirmDeleteStudio;
import '../mobile/mobile_header.dart';
import '../mobile/mobile_style.dart';
import '../mobile/studio_export.dart';
import '../mobile/studio_settings_mobile.dart';
import '../mobile/study_build_run.dart';
import '../upload/build_flow_phone.dart';

/// The phone's studio settings: rename, add files and rebuild (through the
/// building page and the ready moment), export, delete.
class StudioSettingsPhonePage extends ConsumerStatefulWidget {
  const StudioSettingsPhonePage({super.key, required this.studioId});

  final String studioId;

  @override
  ConsumerState<StudioSettingsPhonePage> createState() =>
      _StudioSettingsPhonePageState();
}

class _StudioSettingsPhonePageState
    extends ConsumerState<StudioSettingsPhonePage> {
  StudyBuildRun? _run;

  String get _base => '/study/${widget.studioId}';

  @override
  Widget build(BuildContext context) {
    final run = _run;
    if (run != null) return StudyBuildFlowPhone(run: run);
    final c = SmColors.of(context);
    Widget plain(Widget child) => Scaffold(
      backgroundColor: c.background,
      body: SmHeaderPage(
        header: SmHeader(title: 'Studio', onBack: () => context.go(_base)),
        child: SafeArea(child: Center(child: child)),
      ),
    );
    return ref
        .watch(studioProvider(widget.studioId))
        .when(
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          loading: () => plain(
            CircularProgressIndicator(color: c.accent, strokeWidth: 2.5),
          ),
          error: (_, _) => plain(
            Text(
              'Couldn’t open this studio',
              style: SmText.of(context).small.copyWith(fontSize: 13),
            ),
          ),
          data: (studio) => StudioSettingsMobile(
            studio: studio,
            onBack: () => context.go(_base),
            onRename: (title) async {
              final ok = await ref
                  .read(studioRepositoryProvider)
                  .renameStudio(studio.id, title);
              if (ok) {
                ref.invalidate(studioProvider(studio.id));
                ref.invalidate(studioListProvider);
              }
              return ok;
            },
            onUpdate: (files) {
              final upload = ref.read(uploadApiProvider);
              if (upload == null) {
                SmHaptics.error();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Adding files needs the Study server'),
                  ),
                );
                return;
              }
              final run = StudyBuildRun(
                backend: ApiStudyBuildBackend(
                  ref.read(studioRepositoryProvider),
                  upload,
                ),
                title: studio.title,
                files: files,
                studioId: studio.id,
              );
              setState(() => _run = run);
              unawaited(run.start());
            },
            onExportNotes: () async {
              final bytes = await studyNotesPdf(studio);
              await shareFile(
                bytes,
                name: '${exportName(studio)}-notes.pdf',
                mime: 'application/pdf',
                subject: '${studio.title} — study notes',
              );
            },
            onExportCards: () => shareFile(
              utf8Bytes(ankiTsv(studio)),
              name: '${exportName(studio)}-anki.txt',
              mime: 'text/plain',
              subject: '${studio.title} — flashcards',
            ),
            onDelete: () => confirmDeleteStudio(context, ref, studio),
          ),
        );
  }
}
