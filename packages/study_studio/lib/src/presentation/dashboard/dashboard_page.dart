import 'dart:async';

import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../data/api/upload_api.dart';
import '../../domain/entities/studio.dart';
import '../../domain/entities/topic.dart';
import '../format.dart';
import '../widgets/mobile_layout.dart';
import '../widgets/studio_scaffold.dart';

/// Screen 5 — Inside Your Study Studio.
///
/// Not an analytics dashboard: entering a studio should feel like entering the
/// course itself. An AI companion greets the user with a recommendation, the
/// learning modes take centre stage, and small cards resume the last session
/// and surface the knowledge snapshot. Driven entirely by the [Studio] so it
/// works for any course. Same visual language as Screens 1–4 + Outfit.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key, required this.studioId, this.buildId});

  final String studioId;

  /// When set (via `?building=<id>`), the studio is generating — show a live
  /// progress banner and refresh as lessons land, instead of a blocking spinner.
  final String? buildId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(studioProvider(studioId));

    final content = async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (studio) => isDesktop(context)
          ? _DashboardDesktop(studio: studio)
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: _DashboardBody(studio: studio),
              ),
            ),
    );

    return StudioShell(
      selectedIndex: 1,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (buildId != null)
              _BuildBanner(studioId: studioId, buildId: buildId!),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Desktop / web layout
// ---------------------------------------------------------------------------

class _DashboardDesktop extends StatelessWidget {
  const _DashboardDesktop({required this.studio});
  final Studio studio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topics = studio.topics;
    final weakest = topics.isEmpty
        ? null
        : topics.reduce((a, b) => a.mastery <= b.mastery ? a : b);
    final strongest = topics.isEmpty
        ? null
        : topics.reduce((a, b) => a.mastery >= b.mastery ? a : b);
    final connected = topics.isEmpty
        ? null
        : topics.reduce(
            (a, b) =>
                a.relatedTopicIds.length >= b.relatedTopicIds.length ? a : b,
          );
    final base = '/study/${studio.id}';
    final modes = _modesFor(context, studio, weakest);

    // No-scroll bento: header + status banner pinned, then a two-column main
    // area that fills the rest — learning-mode grid on the left, snapshot +
    // resume stacked on the right. Everything sizes with Expanded/flex so the
    // whole studio fits one viewport without scrolling.
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 14, 32, 16),
      child: ContentColumn(
        maxWidth: 1320,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(studio: studio),
            const SizedBox(height: CockpitSpacing.md),
            _CompanionCard(studio: studio, recommended: weakest, compact: true),
            const SizedBox(height: CockpitSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Choose how you want to learn',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => context.go('$base/topics'),
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.chevron_right, size: 18),
                  label: const Text('Explore all'),
                ),
              ],
            ),
            const SizedBox(height: CockpitSpacing.sm),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 63, child: _ModeBento(modes: modes)),
                  const SizedBox(width: CockpitSpacing.lg),
                  Expanded(
                    flex: 37,
                    child: Column(
                      children: [
                        Expanded(
                          child:
                              (weakest != null &&
                                  strongest != null &&
                                  connected != null)
                              ? _KnowledgePanelVertical(
                                  connected: connected,
                                  weakest: weakest,
                                  strongest: strongest,
                                )
                              : const _EmptyPanel(),
                        ),
                        if (weakest != null) ...[
                          const SizedBox(height: CockpitSpacing.md),
                          _ContinueCard(
                            topic: weakest,
                            lastStudied: studio.lastStudied,
                            onTap: () =>
                                context.go('$base/teach/${weakest.id}'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Desktop learning-mode bento: two rows of three cards, each flexing to fill
/// the available height so the grid never scrolls.
class _ModeBento extends StatelessWidget {
  const _ModeBento({required this.modes});
  final List<_Mode> modes;

  Widget _row(List<_Mode> row) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < row.length; i++) ...[
        if (i > 0) const SizedBox(width: CockpitSpacing.md),
        Expanded(child: _ModeCard(mode: row[i])),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final top = modes.take(3).toList();
    final bottom = modes.skip(3).take(3).toList();
    return Column(
      children: [
        Expanded(child: _row(top)),
        const SizedBox(height: CockpitSpacing.md),
        Expanded(child: _row(bottom)),
      ],
    );
  }
}

/// Placeholder for the right column while a studio has no topics yet.
class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: Center(
        child: Text(
          'Topics appear here as your\nstudio finishes building.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.studio});
  final Studio studio;

  @override
  Widget build(BuildContext context) {
    final base = '/study/${studio.id}';
    final topics = studio.topics;

    // Derive the study companion's recommendation from the real study objects.
    final weakest = topics.isEmpty
        ? null
        : topics.reduce((a, b) => a.mastery <= b.mastery ? a : b);
    final strongest = topics.isEmpty
        ? null
        : topics.reduce((a, b) => a.mastery >= b.mastery ? a : b);
    final connected = topics.isEmpty
        ? null
        : topics.reduce(
            (a, b) =>
                a.relatedTopicIds.length >= b.relatedTopicIds.length ? a : b,
          );

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _Header(studio: studio),
        const SizedBox(height: CockpitSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
          child: _CompanionCard(studio: studio, recommended: weakest),
        ),
        const SizedBox(height: CockpitSpacing.xl),
        _SectionHeader(
          title: 'Choose How You Want to Learn',
          trailing: TextButton.icon(
            onPressed: () => context.go('$base/topics'),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.chevron_right, size: 18),
            label: const Text('Explore All'),
          ),
        ),
        const SizedBox(height: CockpitSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
          child: _LearningModeGrid(studio: studio, recommended: weakest),
        ),
        const SizedBox(height: CockpitSpacing.xl),
        if (weakest != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
            child: _ContinueCard(
              topic: weakest,
              lastStudied: studio.lastStudied,
              onTap: () => context.go('$base/teach/${weakest.id}'),
            ),
          ),
        const SizedBox(height: CockpitSpacing.lg),
        if (weakest != null && strongest != null && connected != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
            child: _KnowledgeSnapshot(
              connected: connected,
              weakest: weakest,
              strongest: strongest,
            ),
          ),
        const SizedBox(height: CockpitSpacing.xl),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.studio});
  final Studio studio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final desktop = isDesktop(context);
    TextSpan meta(String value, String label) => TextSpan(
      children: [
        TextSpan(
          text: '$value ',
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        TextSpan(text: label),
      ],
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        CockpitSpacing.xs,
        desktop ? 0 : CockpitSpacing.sm,
        CockpitSpacing.xs,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _CircleButton(
            icon: Icons.arrow_back_ios_new,
            onTap: () => context.go('/study'),
          ),
          const SizedBox(width: CockpitSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: desktop
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                Text(
                  studio.title,
                  textAlign: desktop ? TextAlign.start : TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      (desktop
                              ? theme.textTheme.headlineSmall
                              : theme.textTheme.titleLarge)
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                ),
                const SizedBox(height: 1),
                Text.rich(
                  TextSpan(
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    children: [
                      meta('${studio.topicCount}', 'topics'),
                      const TextSpan(text: '   ·   '),
                      meta('${studio.flashcardCount}', 'flashcards'),
                      const TextSpan(text: '   ·   '),
                      meta('${studio.quizCount}', 'quizzes'),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: desktop ? TextAlign.start : TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          _CircleButton(
            icon: Icons.search,
            onTap: () => context.go('/study/${studio.id}/topics'),
          ),
          const SizedBox(width: CockpitSpacing.xs),
          _StudioMenu(studio: studio),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Live build banner — polls the studio build and fills in lessons as they land
// ---------------------------------------------------------------------------

class _BuildBanner extends ConsumerStatefulWidget {
  const _BuildBanner({required this.studioId, required this.buildId});
  final String studioId;
  final String buildId;

  @override
  ConsumerState<_BuildBanner> createState() => _BuildBannerState();
}

class _BuildBannerState extends ConsumerState<_BuildBanner> {
  Timer? _timer;
  BuildSnapshot? _snap;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(milliseconds: 900), (_) => _poll());
  }

  Future<void> _poll() async {
    final api = ref.read(uploadApiProvider);
    if (api == null) {
      _timer?.cancel();
      return;
    }
    try {
      final s = await api.buildSnapshot(
        studioId: widget.studioId,
        buildId: widget.buildId,
      );
      if (!mounted) return;
      setState(() => _snap = s);
      // Refresh the studio so newly-written lessons appear live.
      ref.invalidate(studioProvider(widget.studioId));
      if (!s.inProgress) {
        _timer?.cancel();
        if (s.isDone && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Your studio is ready ✨')),
          );
        }
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _dismissed = true);
        });
      }
    } catch (_) {
      // Transient network/DB hiccup — keep polling.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _snap;
    if (_dismissed || s == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = s.lessonsTotal;
    final done = s.lessonsDone;
    final frac = s.progressPct.clamp(0.0, 1.0);
    final pctLabel = '${(frac * 100).round()}%';
    final accent = s.isFailed ? scheme.error : scheme.primary;
    final label = s.isFailed
        ? (s.stage.isNotEmpty ? s.stage : 'Build failed — please try again')
        : s.isDone
        ? (s.stage.isNotEmpty ? s.stage : 'Your studio is ready')
        : (s.stage.isNotEmpty ? s.stage : 'Building your study studio…');

    return Container(
      margin: const EdgeInsets.fromLTRB(
        CockpitSpacing.md,
        CockpitSpacing.sm,
        CockpitSpacing.md,
        0,
      ),
      padding: const EdgeInsets.all(CockpitSpacing.md),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (s.inProgress)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: accent,
                  ),
                )
              else
                Icon(
                  s.isFailed ? Icons.error_outline : Icons.check_circle,
                  size: 20,
                  color: accent,
                ),
              const SizedBox(width: CockpitSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (s.inProgress || s.isDone)
                Text(
                  pctLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          if (s.inProgress) ...[
            const SizedBox(height: CockpitSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(CockpitRadii.pill),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 6,
                backgroundColor: scheme.surfaceContainerHighest,
                color: accent,
              ),
            ),
            const SizedBox(height: CockpitSpacing.sm),
            _BuildPhaseRow(
              status: s.status,
              lessonsDone: done,
              lessonsTotal: total,
            ),
            const SizedBox(height: 4),
            Text(
              s.status == 'extracting' && total > 0
                  ? 'Ingesting files: $done of $total — you can keep browsing.'
                  : total > 0 && s.status == 'generating'
                  ? 'Lessons ready: $done of $total — keep browsing while AI works.'
                  : 'You can keep browsing — lessons appear as they’re ready.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BuildPhaseRow extends StatelessWidget {
  const _BuildPhaseRow({
    required this.status,
    required this.lessonsDone,
    required this.lessonsTotal,
  });

  final String status;
  final int lessonsDone;
  final int lessonsTotal;

  static const _phases = <(String, String)>[
    ('extracting', 'Materials'),
    ('generating', 'Lessons'),
    ('scenarios', 'Scenarios'),
    ('done', 'Ready'),
  ];

  int get _activeIndex {
    switch (status) {
      case 'queued':
      case 'extracting':
        return 0;
      case 'generating':
        return 1;
      case 'scenarios':
        return 2;
      case 'done':
        return 3;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = _activeIndex;
    return Row(
      children: [
        for (var i = 0; i < _phases.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: i <= active
                    ? scheme.primary.withValues(alpha: 0.55)
                    : scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          _PhaseChip(
            label: i == 0 && lessonsTotal > 0 && status == 'extracting'
                ? 'Materials $lessonsDone/$lessonsTotal'
                : i == 1 && lessonsTotal > 0 && status == 'generating'
                ? 'Lessons $lessonsDone/$lessonsTotal'
                : _phases[i].$2,
            done: i < active,
            current: i == active,
          ),
        ],
      ],
    );
  }
}

class _PhaseChip extends StatelessWidget {
  const _PhaseChip({
    required this.label,
    required this.done,
    required this.current,
  });

  final String label;
  final bool done;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = done || current ? scheme.primary : scheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          done
              ? Icons.check_circle
              : current
              ? Icons.radio_button_checked
              : Icons.radio_button_unchecked,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: current || done ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _StudioMenu extends ConsumerWidget {
  const _StudioMenu({required this.studio});
  final Studio studio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: PopupMenuButton<String>(
        icon: Icon(
          Icons.more_horiz,
          size: 20,
          color: theme.colorScheme.onSurface,
        ),
        onSelected: (v) {
          if (v == 'Delete') {
            _confirmAndDelete(context, ref);
          } else {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('$v — coming soon')));
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'Rename', child: Text('Rename')),
          const PopupMenuItem(value: 'Duplicate', child: Text('Duplicate')),
          const PopupMenuItem(
            value: 'Export notes',
            child: Text('Export notes'),
          ),
          const PopupMenuItem(
            value: 'Rebuild Studio',
            child: Text('Rebuild Studio'),
          ),
          PopupMenuItem(
            value: 'Delete',
            child: Text(
              'Delete',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final repo = ref.read(studioRepositoryProvider);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('Delete studio?'),
          content: Text(
            'This permanently deletes "${studio.title}" and all of its topics, '
            'flashcards, quizzes, and scenarios. This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: scheme.error),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    try {
      await repo.deleteStudio(studio.id);
      ref.invalidate(studioListProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('Deleted "${studio.title}"')),
      );
      router.go('/study');
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not delete studio: $e')),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// AI companion hero
// ---------------------------------------------------------------------------

class _CompanionCard extends StatelessWidget {
  const _CompanionCard({
    required this.studio,
    required this.recommended,
    this.compact = false,
  });
  final Studio studio;
  final Topic? recommended;

  /// Desktop packs the companion into a single dense band so the whole studio
  /// fits the viewport without scrolling.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = '/study/${studio.id}';
    final rec = recommended;
    final retention = rec == null
        ? 70
        : (40 + (1 - rec.mastery) * 50).clamp(0, 95).round();
    final session = rec?.estimatedStudyTimeMinutes ?? 15;

    if (compact) {
      return Container(
        padding: const EdgeInsets.all(CockpitSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(CockpitRadii.xl),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primary.withValues(alpha: 0.10),
              scheme.secondary.withValues(alpha: 0.06),
            ],
          ),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            const _RobotAvatar(size: 56),
            const SizedBox(width: CockpitSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 15, color: scheme.primary),
                      const SizedBox(width: CockpitSpacing.xs),
                      Text(
                        'Welcome back 👋',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Your Study Studio is ready.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (rec != null) ...[
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        children: [
                          const TextSpan(text: "You're "),
                          TextSpan(
                            text: '$retention%',
                            style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const TextSpan(
                            text: ' likely to improve by reviewing ',
                          ),
                          TextSpan(
                            text: rec.title,
                            style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(text: '  •  ~$session min'),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: CockpitSpacing.lg),
            SizedBox(
              width: 196,
              child: _GradientButton(
                icon: Icons.play_circle_outline,
                label: 'Continue Learning',
                onTap: () => context.go(
                  rec != null ? '$base/teach/${rec.id}' : '$base/topics',
                ),
              ),
            ),
            const SizedBox(width: CockpitSpacing.sm),
            _OutlineButton(
              icon: Icons.chat_bubble_outline,
              label: 'Ask AI',
              onTap: () => context.go('$base/ask-ai'),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CockpitRadii.xl),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: 0.10),
            scheme.secondary.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MobileWrap(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 16,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: CockpitSpacing.xs),
                        Text(
                          'Welcome back 👋',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: CockpitSpacing.sm),
                    Text(
                      'Your Study Studio\nis ready.',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: CockpitSpacing.sm),
                    if (rec != null)
                      Text.rich(
                        TextSpan(
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                          children: [
                            const TextSpan(text: "You're "),
                            TextSpan(
                              text: '$retention%',
                              style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const TextSpan(
                              text:
                                  ' likely to improve retention by '
                                  'reviewing ',
                            ),
                            TextSpan(
                              text: rec.title,
                              style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const TextSpan(text: ' first.'),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: CockpitSpacing.sm),
              const _RobotAvatar(),
            ],
          ),
          const SizedBox(height: CockpitSpacing.md),
          MobileWrap(
            children: [
              Icon(Icons.schedule, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: CockpitSpacing.xs),
              Text(
                'Estimated session: $session minutes',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _GradientButton(
                  icon: Icons.play_circle_outline,
                  label: 'Continue Learning',
                  onTap: () => context.go(
                    rec != null ? '$base/teach/${rec.id}' : '$base/topics',
                  ),
                ),
              ),
              const SizedBox(width: CockpitSpacing.md),
              _OutlineButton(
                icon: Icons.chat_bubble_outline,
                label: 'Ask AI',
                onTap: () => context.go(
                  rec != null ? '$base/teach/${rec.id}' : '$base/topics',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RobotAvatar extends StatelessWidget {
  const _RobotAvatar({this.size = 78});
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, Colors.black, 0.4)!,
          ],
        ),
        border: Border.all(color: Colors.black, width: 1),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.4),
            blurRadius: size * 0.26,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(
        Icons.smart_toy_rounded,
        color: Colors.white,
        size: size * 0.5,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Learning modes
// ---------------------------------------------------------------------------

class _LearningModeGrid extends StatelessWidget {
  const _LearningModeGrid({required this.studio, required this.recommended});
  final Studio studio;
  final Topic? recommended;

  @override
  Widget build(BuildContext context) {
    final modes = _modesFor(context, studio, recommended);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: modes.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 230,
        mainAxisSpacing: CockpitSpacing.md,
        crossAxisSpacing: CockpitSpacing.md,
        mainAxisExtent: 188,
      ),
      itemBuilder: (context, i) => _ModeCard(mode: modes[i]),
    );
  }
}

/// The six learning modes, derived from the studio's real counts. Shared by the
/// mobile grid and the desktop bento.
List<_Mode> _modesFor(BuildContext context, Studio studio, Topic? recommended) {
  final base = '/study/${studio.id}';
  final recId = (recommended ?? studio.topics.firstOrNull)?.id;
  void soon(String label) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('$label — Phase 2')));
  return <_Mode>[
    _Mode(
      icon: Icons.school_rounded,
      color: const Color(0xFF8B5CF6),
      title: 'Teach Me',
      desc: 'Learn any topic with AI explanations and follow-up questions.',
      count: '${studio.topicCount} topics',
      onTap: () =>
          context.go(recId != null ? '$base/teach/$recId' : '$base/topics'),
    ),
    _Mode(
      icon: Icons.help_rounded,
      color: const Color(0xFFE5484D),
      title: 'Quiz Me',
      desc: 'AI-generated quizzes to test your understanding.',
      count: '${studio.quizCount} quizzes',
      onTap: () => context.go('$base/quiz'),
    ),
    _Mode(
      icon: Icons.bolt_rounded,
      color: const Color(0xFFF5A623),
      title: 'Lightning Recall',
      desc: 'Rapid-fire questions for quick recall practice.',
      count: '${studio.flashcardCount + studio.quizCount} questions',
      onTap: () => context.go('$base/recall'),
    ),
    _Mode(
      icon: Icons.style_rounded,
      color: const Color(0xFF30A46C),
      title: 'Flashcards',
      desc: 'Smart flashcards spaced for long-term retention.',
      count: '${studio.flashcardCount} flashcards',
      onTap: () => context.go('$base/flashcards'),
    ),
    _Mode(
      icon: Icons.theater_comedy_rounded,
      color: const Color(0xFF3B82F6),
      title: 'Scenario Mode',
      desc: 'Real-world scenarios to apply your knowledge.',
      count: '${studio.scenarioCount} scenarios',
      onTap: () => context.go('$base/scenario'),
    ),
    _Mode(
      icon: Icons.view_in_ar_rounded,
      color: const Color(0xFF7C3AED),
      title: 'Visualize',
      desc: 'Diagrams, concept maps, and interactive visuals.',
      count: '${studio.topicCount} visuals',
      onTap: () => soon('Visualize'),
    ),
  ];
}

class _Mode {
  const _Mode({
    required this.icon,
    required this.color,
    required this.title,
    required this.desc,
    required this.count,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String desc;
  final String count;
  final VoidCallback onTap;
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.mode});
  final _Mode mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(CockpitRadii.lg),
      child: InkWell(
        onTap: mode.onTap,
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        hoverColor: mode.color.withValues(alpha: 0.06),
        child: Ink(
          padding: const EdgeInsets.all(CockpitSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CockpitRadii.lg),
            border: Border.all(color: Colors.black, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: mode.color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(CockpitRadii.md),
                  border: Border.all(color: mode.color.withValues(alpha: 0.35)),
                ),
                child: Icon(mode.icon, color: mode.color, size: 23),
              ),
              const Spacer(),
              Text(
                mode.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                mode.desc,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: CockpitSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      mode.count,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: mode.color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_outward_rounded,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Continue where you left off
// ---------------------------------------------------------------------------

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.topic,
    required this.lastStudied,
    required this.onTap,
  });
  final Topic topic;
  final DateTime? lastStudied;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pct = (topic.mastery * 100).round();
    return _OutlinedCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(CockpitRadii.sm),
            ),
            child: Icon(
              Icons.menu_book_rounded,
              color: scheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: CockpitSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Continue Where You Left Off',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  topic.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: CockpitSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(CockpitRadii.pill),
                        child: LinearProgressIndicator(
                          value: topic.mastery.clamp(0, 1).toDouble(),
                          minHeight: 6,
                          backgroundColor: scheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    const SizedBox(width: CockpitSpacing.sm),
                    Text(
                      '$pct%',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: CockpitSpacing.xs),
                MobileWrap(
                  children: [
                    Icon(
                      Icons.schedule,
                      size: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'Last studied ${relativeDay(lastStudied).toLowerCase()}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.chevron_right, color: scheme.primary, size: 20),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Knowledge snapshot
// ---------------------------------------------------------------------------

class _KnowledgeSnapshot extends StatelessWidget {
  const _KnowledgeSnapshot({
    required this.connected,
    required this.weakest,
    required this.strongest,
  });
  final Topic connected;
  final Topic weakest;
  final Topic strongest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _OutlinedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MobileWrap(
            children: [
              Icon(Icons.insights_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: CockpitSpacing.sm),
              Expanded(
                child: Text(
                  'Knowledge Snapshot',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              InkWell(
                onTap: () =>
                    context.go('/study/${connected.studioId}/knowledge-graph'),
                child: MobileWrap(
                  children: [
                    Text(
                      'View Knowledge Graph',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 16, color: scheme.primary),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _SnapshotMetric(
                  icon: Icons.hub_rounded,
                  iconColor: scheme.primary,
                  label: 'Most Connected Topic',
                  value: connected.title,
                  sub: '${connected.relatedTopicIds.length} connections',
                ),
              ),
              Expanded(
                child: _SnapshotMetric(
                  icon: Icons.trending_down_rounded,
                  iconColor: scheme.error,
                  label: 'Weakest Topic',
                  value: weakest.title,
                  sub: '${(weakest.mastery * 100).round()}% mastery',
                  subColor: scheme.error,
                ),
              ),
              Expanded(
                child: _SnapshotMetric(
                  icon: Icons.trending_up_rounded,
                  iconColor: scheme.tertiary,
                  label: 'Strongest Topic',
                  value: strongest.title,
                  sub: '${(strongest.mastery * 100).round()}% mastery',
                  subColor: scheme.tertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SnapshotMetric extends StatelessWidget {
  const _SnapshotMetric({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.sub,
    this.subColor,
  });
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String sub;
  final Color? subColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: CockpitSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(height: CockpitSpacing.xs),
          Text(
            label,
            maxLines: 2,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 11,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: subColor ?? scheme.onSurfaceVariant,
              fontWeight: subColor != null ? FontWeight.w600 : FontWeight.w400,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// Vertical Knowledge Snapshot for the desktop right column — three metric rows
/// that flex to fill the panel height, over a full-width "View Knowledge Graph"
/// button.
class _KnowledgePanelVertical extends StatelessWidget {
  const _KnowledgePanelVertical({
    required this.connected,
    required this.weakest,
    required this.strongest,
  });
  final Topic connected;
  final Topic weakest;
  final Topic strongest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: CockpitSpacing.sm),
              Text(
                'Knowledge Snapshot',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _SnapRow(
                  icon: Icons.hub_rounded,
                  color: scheme.primary,
                  label: 'Most connected',
                  value: connected.title,
                  sub: '${connected.relatedTopicIds.length} links',
                ),
                Divider(height: 1, color: scheme.outlineVariant),
                _SnapRow(
                  icon: Icons.trending_down_rounded,
                  color: scheme.error,
                  label: 'Weakest topic',
                  value: weakest.title,
                  sub: '${(weakest.mastery * 100).round()}%',
                ),
                Divider(height: 1, color: scheme.outlineVariant),
                _SnapRow(
                  icon: Icons.trending_up_rounded,
                  color: scheme.tertiary,
                  label: 'Strongest topic',
                  value: strongest.title,
                  sub: '${(strongest.mastery * 100).round()}%',
                ),
              ],
            ),
          ),
          const SizedBox(height: CockpitSpacing.sm),
          InkWell(
            onTap: () =>
                context.go('/study/${connected.studioId}/knowledge-graph'),
            borderRadius: BorderRadius.circular(CockpitRadii.md),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.sm),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(CockpitRadii.md),
                border: Border.all(color: Colors.black, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'View Knowledge Graph',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right, size: 16, color: scheme.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SnapRow extends StatelessWidget {
  const _SnapRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.sub,
  });
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(CockpitRadii.md),
            border: Border.all(color: color.withValues(alpha: 0.32)),
          ),
          child: Icon(icon, size: 19, color: color),
        ),
        const SizedBox(width: CockpitSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: CockpitSpacing.sm),
        Text(
          sub,
          style: theme.textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: CockpitSpacing.lg,
        right: CockpitSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _OutlinedCard extends StatelessWidget {
  const _OutlinedCard({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(CockpitRadii.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        child: Ink(
          padding: const EdgeInsets.all(CockpitSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CockpitRadii.lg),
            border: Border.all(color: Colors.black, width: 1),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CockpitRadii.pill),
            gradient: LinearGradient(
              colors: [scheme.primary, scheme.secondary],
            ),
            border: Border.all(color: Colors.black, width: 1),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: SizedBox(
            height: 46,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: CockpitSpacing.sm),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CockpitRadii.pill),
            border: Border.all(color: Colors.black, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
            child: SizedBox(
              height: 46,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: scheme.onSurface),
                  const SizedBox(width: CockpitSpacing.sm),
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black, width: 1),
        ),
        child: Icon(icon, size: 18, color: theme.colorScheme.onSurface),
      ),
    );
  }
}
