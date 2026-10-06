import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../application/providers.dart';
import '../../application/study_voice.dart';
import '../../data/api/upload_api.dart';
import '../../domain/entities/studio.dart';
import '../lightning_recall/lightning_recall_page.dart' show recallItems;
import '../mobile/lightning_mobile.dart';
import '../mobile/mobile_header.dart';
import '../mobile/mobile_style.dart';
import '../mobile/studio_main_mobile.dart';
import 'dashboard_page.dart' show confirmDeleteStudio;

/// The phone's studio: loads it, follows a running build, and hands the
/// page its ways to learn and its menu.
class StudioPhonePage extends ConsumerStatefulWidget {
  const StudioPhonePage({super.key, required this.studioId, this.buildId});

  final String studioId;

  /// A build still running (`?building=<id>`).
  final String? buildId;

  @override
  ConsumerState<StudioPhonePage> createState() => _StudioPhonePageState();
}

class _StudioPhonePageState extends ConsumerState<StudioPhonePage> {
  Timer? _poll;
  BuildSnapshot? _build;
  var _buildGone = false;

  @override
  void initState() {
    super.initState();
    if (widget.buildId != null) {
      unawaited(_follow());
      _poll = Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => _follow(),
      );
    }
  }

  Future<void> _follow() async {
    final api = ref.read(uploadApiProvider);
    if (api == null) {
      _poll?.cancel();
      return;
    }
    try {
      final s = await api.buildSnapshot(
        studioId: widget.studioId,
        buildId: widget.buildId!,
      );
      if (!mounted || !(_poll?.isActive ?? false)) return;
      setState(() => _build = s);
      // New lessons show up as they land.
      ref.invalidate(studioProvider(widget.studioId));
      if (!s.inProgress) {
        _poll?.cancel();
        if (s.isDone) {
          SmHaptics.done();
          Future<void>.delayed(const Duration(seconds: 4), () {
            if (mounted) setState(() => _buildGone = true);
          });
        } else {
          SmHaptics.error();
        }
      }
    } on Object {
      // A hiccup: the next poll tries again.
    }
  }

  /// The studio whose first Lightning recall question is already being
  /// voiced, so the session opens with it ready.
  String? _warmed;

  Future<void> _warmRecall(Studio studio) async {
    final voice = ref.read(studyVoiceProvider);
    final first = recallItems(studio).firstOrNull;
    // A studio still building may have no questions yet: try again later.
    if (voice == null || first == null || _warmed == studio.id) return;
    _warmed = studio.id;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(LightningMobile.mutedKey) ?? false) return;
    } on Object {
      // Not muted, as far as we know.
    }
    voice.warm(first.question);
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final async = ref.watch(studioProvider(widget.studioId));
    Widget plain(Widget child) => Scaffold(
      backgroundColor: c.background,
      body: SmHeaderPage(
        header: SmHeader(title: '', onBack: () => context.go('/study')),
        child: SafeArea(child: Center(child: child)),
      ),
    );
    return async.when(
      // Keep showing the studio while it refreshes under a build.
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () =>
          plain(CircularProgressIndicator(color: c.accent, strokeWidth: 2.5)),
      error: (e, _) => plain(
        Text(
          'Couldn’t open this studio',
          style: SmText.of(context).small.copyWith(fontSize: 13),
        ),
      ),
      data: (studio) {
        unawaited(_warmRecall(studio));
        return StudioMainMobile(
          studio: studio,
          modes: phoneModes(context, studio),
          build: _buildGone ? null : _build,
          onMenu: () => _menu(context, studio),
          onRefresh: () async {
            ref.invalidate(studioProvider(widget.studioId));
            await ref.read(studioProvider(widget.studioId).future);
          },
        );
      },
    );
  }

  void _menu(BuildContext context, Studio studio) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    void soon(String what) => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$what is coming soon')));
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (sheet) {
        Widget row(
          IconData icon,
          String label,
          VoidCallback onTap, {
          bool danger = false,
        }) {
          final color = danger ? c.accentSoft : c.text;
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              SmHaptics.select();
              Navigator.of(sheet).pop();
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: color),
                  const SizedBox(width: 14),
                  Text(
                    label,
                    style: t.body.copyWith(fontSize: 14, color: color),
                  ),
                ],
              ),
            ),
          );
        }

        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF2A2B2B) : Colors.white,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: c.line),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: c.line,
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
                row(
                  Icons.insights_rounded,
                  'Mastery report',
                  () => context.go('/study/${studio.id}/mastery-report'),
                ),
                row(Icons.edit_outlined, 'Rename', () => soon('Renaming')),
                row(
                  Icons.ios_share_rounded,
                  'Export notes',
                  () => soon('Exporting notes'),
                ),
                row(
                  Icons.refresh_rounded,
                  'Rebuild studio',
                  () => soon('Rebuilding'),
                ),
                row(
                  Icons.delete_outline_rounded,
                  'Delete',
                  () => confirmDeleteStudio(context, ref, studio),
                  danger: true,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The six ways to learn a studio, with its real counts.
List<StudyMode> phoneModes(BuildContext context, Studio studio) {
  final base = '/study/${studio.id}';
  final weakest = studio.topics.isEmpty
      ? null
      : studio.topics.reduce((a, b) => a.mastery <= b.mastery ? a : b);
  return [
    StudyMode(
      icon: Icons.school_rounded,
      color: const Color(0xFFC40C1A),
      title: 'Teach me',
      blurb: 'AI explains, you ask follow-ups',
      count: '${studio.topicCount} topics',
      onTap: () => context.go(
        weakest != null ? '$base/teach/${weakest.id}' : '$base/topics',
      ),
    ),
    StudyMode(
      icon: Icons.help_rounded,
      color: const Color(0xFF378ADD),
      title: 'Quiz me',
      blurb: 'Test what you know',
      count: '${studio.quizCount} questions',
      onTap: () => context.go('$base/quiz'),
    ),
    StudyMode(
      icon: Icons.bolt_rounded,
      color: const Color(0xFFF5A623),
      title: 'Lightning recall',
      blurb: 'Rapid-fire questions',
      count: '${studio.flashcardCount + studio.quizCount} questions',
      onTap: () => context.go('$base/recall'),
    ),
    StudyMode(
      icon: Icons.style_rounded,
      color: const Color(0xFFF0997B),
      title: 'Flashcards',
      blurb: 'Spaced for long-term memory',
      count: '${studio.flashcardCount} cards',
      onTap: () => context.go('$base/flashcards'),
    ),
    StudyMode(
      icon: Icons.route_rounded,
      color: const Color(0xFF30A46C),
      title: 'Scenarios',
      blurb: 'Apply it to real situations',
      count: '${studio.scenarioCount} scenarios',
      onTap: () => context.go('$base/scenario'),
    ),
    StudyMode(
      icon: Icons.hub_rounded,
      color: const Color(0xFF8B83E6),
      title: 'Visualize',
      blurb: 'How the topics connect',
      count: '${studio.topicCount} topics',
      onTap: () => context.go('$base/knowledge-graph'),
    ),
    StudyMode(
      icon: Icons.calendar_month_rounded,
      color: const Color(0xFF378ADD),
      title: 'Study plan',
      blurb: 'A little every day, for an exam or not',
      count: '${studio.topicCount} topics',
      onTap: () => context.go('$base/study-plan'),
    ),
    StudyMode(
      icon: Icons.insights_rounded,
      color: const Color(0xFFF5A623),
      title: 'Mastery report',
      blurb: 'Where you stand, what’s next',
      count: '${(studio.overallMastery * 100).round()}% mastered',
      onTap: () => context.go('$base/mastery-report'),
    ),
  ];
}
