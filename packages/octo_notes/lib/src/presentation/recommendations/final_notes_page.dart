import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/recommendations_controller.dart';
import '../../theme/octo_notes_theme.dart';
import '../widgets/octo_widgets.dart';

/// Width at/above which the Final Notes view shows the recommendations drawer
/// beside the note (spec §2 — desktop/tablet right drawer).
const double _kFinalDesktop = 1040;

/// Panel 14 — Study Studio Recommendations (ON-P14), hosted on the finalized
/// **Final Notes** view reached after Panel 13's *Finalize & Save*.
///
/// Borderless / typography-first (see `DESIGN.md`): grouping comes from
/// whitespace, an [Eyebrow] label and proximity — not cards or outlines. The
/// approved note stays on the left; a recommendation drawer proposes topic
/// clusters ready to become Study Studio sessions. Nothing is created here — it
/// prepares a conversion draft the student approves in Panel 15. See
/// `docs/panel-14-study-recommendations.md`.
class FinalNotesPage extends StatefulWidget {
  const FinalNotesPage({super.key});

  @override
  State<FinalNotesPage> createState() => _FinalNotesPageState();
}

class _FinalNotesPageState extends State<FinalNotesPage> {
  late final RecommendationsController _c;

  @override
  void initState() {
    super.initState();
    _c = RecommendationsController(finalNotesId: 'final-bio101-w4');
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _back() => context.canPop() ? context.pop() : context.go('/notes');

  @override
  Widget build(BuildContext context) {
    return OctoNotesTheme.wrap(
      context: context,
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          final desktop = MediaQuery.sizeOf(context).width >= _kFinalDesktop;
          return AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              return Scaffold(
                backgroundColor: scheme.surface,
                floatingActionButton: (_c.drawerOpen || !desktop)
                    ? null
                    : FloatingActionButton.extended(
                        onPressed: _c.openDrawer,
                        backgroundColor: scheme.primary,
                        foregroundColor: Colors.white,
                        icon: const Icon(Icons.psychology_outlined),
                        label: const Text('Study Studio'),
                      ),
                body: SafeArea(
                  child: Column(
                    children: [
                      _FinalHeader(controller: _c, onBack: _back),
                      Divider(height: 1, color: scheme.outlineVariant),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _FinalNoteView(controller: _c)),
                            if (desktop && _c.drawerOpen) ...[
                              VerticalDivider(
                                  width: 1, color: scheme.outlineVariant),
                              _RecommendationsDrawer(controller: _c),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                bottomSheet: (!desktop && _c.drawerOpen)
                    ? SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.7,
                        child: _RecommendationsDrawer(controller: _c),
                      )
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}

// ===========================================================================
// Shared borderless bits
// ===========================================================================

/// Status = a small coloured dot + label (never a filled pill). See DESIGN.md §6.
class _StatusText extends StatelessWidget {
  const _StatusText(this.label, this.color, {this.icon = Icons.circle});
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: icon == Icons.circle ? 8 : 15, color: color),
        const SizedBox(width: CockpitSpacing.xs),
        Text(label,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// A subtle, borderless source/provenance tag (muted — like [OctoChip]).
class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.icon});
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: scheme.onSurfaceVariant),
            const SizedBox(width: 3),
          ],
          Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ===========================================================================
// Header
// ===========================================================================
class _FinalHeader extends StatelessWidget {
  const _FinalHeader({required this.controller, required this.onBack});
  final RecommendationsController controller;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = controller;
    final compact = MediaQuery.sizeOf(context).width < 1180;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.md, vertical: CockpitSpacing.sm),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: onBack,
          ),
          const SizedBox(width: CockpitSpacing.xs),
          Text('Final Notes',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const Spacer(),
          if (!compact)
            Column(
              children: [
                Text(c.sourceTitle,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                Text('${c.course} • ${c.week}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          const Spacer(),
          _StatusText('Saved to The Deck', CockpitColors.brand.success,
              icon: Icons.check_circle_rounded),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: () => _snack(context, 'Note menu'),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Final note document (left)
// ===========================================================================
class _FinalNoteView extends StatelessWidget {
  const _FinalNoteView({required this.controller});
  final RecommendationsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(CockpitSpacing.xxl, CockpitSpacing.xl,
          CockpitSpacing.xxl, CockpitSpacing.xl),
      children: [
        // Success confirmation — a status line, not a box (spec §3).
        Row(
          children: [
            Icon(Icons.check_circle_rounded,
                color: CockpitColors.brand.success, size: 20),
            const SizedBox(width: CockpitSpacing.md),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: theme.textTheme.bodyMedium,
                  children: [
                    TextSpan(
                        text: 'Session finalized successfully.  ',
                        style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: CockpitColors.brand.success)),
                    TextSpan(
                        text:
                            'Original audio, transcript, notes and ink preserved.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: CockpitSpacing.xxxl),
        // Document title.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cellular Respiration',
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: CockpitSpacing.xxs),
                  Text('Biology 101 • Week 4 • 42:16 lecture',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            _StatusText('Final Notes', scheme.primary,
                icon: Icons.verified_outlined),
          ],
        ),
        const SizedBox(height: CockpitSpacing.xxl),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 156, child: _OutlineNav()),
            const SizedBox(width: CockpitSpacing.xxl),
            const Expanded(child: _NoteBody()),
          ],
        ),
        const SizedBox(height: CockpitSpacing.xxxl),
        // Footer — muted meta, no box.
        Wrap(
          spacing: CockpitSpacing.xl,
          runSpacing: CockpitSpacing.sm,
          children: [
            _FooterChip(Icons.link_rounded, 'Final Notes'),
            _FooterChip(Icons.link_rounded, 'Sources linked'),
            _FooterChip(Icons.verified_outlined, 'Originals accessible'),
          ],
        ),
      ],
    );
  }
}

class _OutlineNav extends StatelessWidget {
  const _OutlineNav();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget item(String text, {bool active = false, bool sub = false}) => Padding(
          padding: EdgeInsets.only(
              left: sub ? CockpitSpacing.md : 0, bottom: CockpitSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (active)
                Container(
                    width: 3,
                    height: 16,
                    margin: const EdgeInsets.only(right: CockpitSpacing.sm),
                    color: scheme.primary)
              else if (sub)
                Padding(
                  padding: const EdgeInsets.only(right: CockpitSpacing.sm),
                  child: Icon(Icons.subdirectory_arrow_right_rounded,
                      size: 14, color: scheme.onSurfaceVariant),
                ),
              Flexible(
                child: Text(text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? scheme.primary : scheme.onSurface,
                    )),
              ),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Outline'),
        const SizedBox(height: CockpitSpacing.lg),
        item('1. Glycolysis', active: true),
        item('2. Electron Transport\nChain'),
        item('Role of Oxygen', sub: true),
      ],
    );
  }
}

class _NoteBody extends StatelessWidget {
  const _NoteBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _NoteSection(
          number: '1',
          title: 'Glycolysis',
          source: 'Transcript • 18:32',
          sourceIcon: Icons.record_voice_over_outlined,
          bullets: [
            'Occurs in the cytoplasm',
            'Net result: two ATP and two NADH.',
          ],
        ),
        const SizedBox(height: CockpitSpacing.xl),
        const _NoteSection(
          number: '2',
          title: 'Electron Transport Chain',
          source: 'Slide 7',
          sourceIcon: Icons.slideshow_outlined,
          bullets: [
            'Located on the inner mitochondrial membrane',
            'Builds a proton gradient used by ATP synthase.',
          ],
        ),
        const SizedBox(height: CockpitSpacing.lg),
        const _SubHeading('Role of Oxygen'),
        const _Bullet('Oxygen acts as the final electron acceptor.',
            source: 'Student Typed', sourceIcon: Icons.edit_outlined),
        const SizedBox(height: CockpitSpacing.xl),
        // Callouts — an icon + coloured eyebrow + text, grouped by whitespace.
        const _Callout(
          color: _CalloutColor.info,
          icon: Icons.help_outline_rounded,
          label: 'Student Question',
          body: 'Why is oxygen required indirectly?',
        ),
        const SizedBox(height: CockpitSpacing.lg),
        const _Callout(
          color: _CalloutColor.gold,
          icon: Icons.lightbulb_outline_rounded,
          label: 'Exam Hint',
          body: 'ATP synthase uses the proton gradient.',
          source: 'Transcript • 18:32',
          sourceIcon: Icons.record_voice_over_outlined,
        ),
      ],
    );
  }
}

class _NoteSection extends StatelessWidget {
  const _NoteSection({
    required this.number,
    required this.title,
    required this.bullets,
    required this.source,
    required this.sourceIcon,
  });
  final String number;
  final String title;
  final List<String> bullets;
  final String source;
  final IconData sourceIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('$number. $title',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            _Tag(source, icon: sourceIcon),
          ],
        ),
        const SizedBox(height: CockpitSpacing.md),
        for (final b in bullets) _Bullet(b),
      ],
    );
  }
}

class _SubHeading extends StatelessWidget {
  const _SubHeading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: CockpitSpacing.sm),
      child: Text(text,
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700)),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text, {this.source, this.sourceIcon});
  final String text;
  final String? source;
  final IconData? sourceIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: CockpitSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 9, right: CockpitSpacing.md),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant, shape: BoxShape.circle),
            ),
          ),
          Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
          if (source != null) ...[
            const SizedBox(width: CockpitSpacing.sm),
            _Tag(source!, icon: sourceIcon),
          ],
        ],
      ),
    );
  }
}

enum _CalloutColor { info, gold }

class _Callout extends StatelessWidget {
  const _Callout({
    required this.color,
    required this.icon,
    required this.label,
    required this.body,
    this.source,
    this.sourceIcon,
  });
  final _CalloutColor color;
  final IconData icon;
  final String label;
  final String body;
  final String? source;
  final IconData? sourceIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tint =
        color == _CalloutColor.info ? CockpitColors.brand.info : scheme.tertiary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, right: CockpitSpacing.md),
          child: Icon(icon, size: 18, color: tint),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(label.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: tint,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      )),
                  if (source != null) ...[
                    const Spacer(),
                    _Tag(source!, icon: sourceIcon),
                  ],
                ],
              ),
              const SizedBox(height: CockpitSpacing.xs),
              Text(body, style: theme.textTheme.bodyLarge),
            ],
          ),
        ),
      ],
    );
  }
}

class _FooterChip extends StatelessWidget {
  const _FooterChip(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: CockpitSpacing.xs),
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

// ===========================================================================
// Panel 14 — recommendations drawer (right)
// ===========================================================================
class _RecommendationsDrawer extends StatelessWidget {
  const _RecommendationsDrawer({required this.controller});
  final RecommendationsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = controller;
    return SizedBox(
      width: 430,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(CockpitSpacing.xl,
                  CockpitSpacing.xl, CockpitSpacing.xl, CockpitSpacing.md),
              children: [
                // Header.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.psychology_outlined,
                        color: scheme.primary, size: 26),
                    const SizedBox(width: CockpitSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Study Studio Recommendations',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          Text(
                              'Turn your approved notes into focused learning '
                              'sessions.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: c.closeDrawer,
                    ),
                  ],
                ),
                const SizedBox(height: CockpitSpacing.xl),
                // Summary — count + status lines (no pills).
                Row(
                  children: [
                    Text('${c.detectedCount} topics detected',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    _StatusText('${c.readyCount} Ready',
                        CockpitColors.brand.success),
                    const SizedBox(width: CockpitSpacing.lg),
                    _StatusText('${c.needsReviewCount} Needs Review',
                        CockpitColors.brand.warning),
                  ],
                ),
                const SizedBox(height: 2),
                Text('From ${c.sourceTitle}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: CockpitSpacing.xl),
                // Topic recommendations — borderless blocks.
                for (var i = 0; i < c.topics.length; i++) ...[
                  _TopicBlock(controller: c, topic: c.topics[i]),
                  if (i != c.topics.length - 1)
                    const SizedBox(height: CockpitSpacing.xl),
                ],
                const SizedBox(height: CockpitSpacing.xxl),
                // Manual selection.
                OutlinedButton.icon(
                  onPressed:
                      c.manualMode ? c.exitManualMode : c.enterManualMode,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    foregroundColor: scheme.onSurface,
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
                  icon: Icon(
                      c.manualMode
                          ? Icons.close_rounded
                          : Icons.ads_click_rounded,
                      size: 18),
                  label: Text(c.manualMode
                      ? 'Exit Manual Selection'
                      : 'Choose Sections Manually'),
                ),
                const SizedBox(height: CockpitSpacing.xl),
                if (c.manualMode)
                  _ManualSummary(controller: c)
                else
                  _SelectionSummary(controller: c),
                const SizedBox(height: CockpitSpacing.xl),
                _InfoLine(
                  icon: Icons.info_outline_rounded,
                  text: 'Suggested activities can be changed before creation.',
                  tint: CockpitColors.brand.info,
                ),
                const SizedBox(height: CockpitSpacing.md),
                _InfoLine(
                  icon: Icons.verified_user_outlined,
                  text: 'Nothing will be created without your approval.',
                  tint: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          // Bottom actions.
          Padding(
            padding: const EdgeInsets.all(CockpitSpacing.lg),
            child: Row(
              children: [
                TextButton(
                  onPressed: c.closeDrawer,
                  style:
                      TextButton.styleFrom(foregroundColor: scheme.onSurface),
                  child: const Text('Not Now'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: c.canContinue
                      ? () => _continueToPanel15(context, c)
                      : null,
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('Review Study Studio Conversion'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A recommended topic — grouping by whitespace + an [OctoHoverRow] selection
/// tint, never a card outline.
class _TopicBlock extends StatelessWidget {
  const _TopicBlock({required this.controller, required this.topic});
  final RecommendationsController controller;
  final StudyTopic topic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final t = topic;
    final ready = t.readiness == Readiness.ready;
    final statusColor =
        ready ? CockpitColors.brand.success : CockpitColors.brand.warning;
    return OctoHoverRow(
      selected: t.selected,
      onTap: () => controller.toggleTopic(t.id),
      padding: const EdgeInsets.all(CockpitSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: t.selected,
                  onChanged: (_) => controller.toggleTopic(t.id),
                  activeColor: scheme.primary,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: CockpitSpacing.md),
              Expanded(
                child: Text(t.title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              _StatusText(t.readiness.label, statusColor,
                  icon: t.readiness.icon),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 34, top: CockpitSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (t.counts.isNotEmpty)
                  Text(t.counts.map((c) => c.label).join('  ·  '),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                if (t.reviewReason != null)
                  Text(t.reviewReason!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                if (t.activities.isNotEmpty) ...[
                  const SizedBox(height: CockpitSpacing.md),
                  Wrap(
                    spacing: CockpitSpacing.xs,
                    runSpacing: CockpitSpacing.xs,
                    children: [
                      for (final a in t.activities) _ActivityChip(activity: a),
                    ],
                  ),
                ],
                if (t.sources.isNotEmpty) ...[
                  const SizedBox(height: CockpitSpacing.sm),
                  Text(t.sources.map((s) => s.label).join('  ·  '),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
                const SizedBox(height: CockpitSpacing.sm),
                if (ready)
                  Row(
                    children: [
                      _LinkAction(
                          label: 'View in Notes',
                          onTap: () =>
                              _snack(context, 'Opening ${t.title} in notes')),
                      const SizedBox(width: CockpitSpacing.lg),
                      _LinkAction(
                          label: 'Why Recommended',
                          onTap: () => _showWhy(context, t)),
                    ],
                  )
                else
                  Row(
                    children: [
                      _LinkAction(
                          label: 'Review Question',
                          onTap: () =>
                              _snack(context, 'Review unresolved question')),
                      const SizedBox(width: CockpitSpacing.lg),
                      _LinkAction(
                          label: 'Include Anyway',
                          onTap: () => controller.toggleTopic(t.id)),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityChip extends StatelessWidget {
  const _ActivityChip({required this.activity});
  final StudyActivity activity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _activityColor(activity, theme.colorScheme);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(activity.icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(activity.label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

Color _activityColor(StudyActivity a, ColorScheme scheme) {
  switch (a) {
    case StudyActivity.teachMe:
      return CockpitColors.brand.info;
    case StudyActivity.quizMe:
      return scheme.primary;
    case StudyActivity.flashcards:
      return CockpitColors.brand.success;
    case StudyActivity.lightningRecall:
      return CockpitColors.brand.warning;
    case StudyActivity.scenarios:
      return const Color(0xFF8B5CF6);
    case StudyActivity.oralExam:
      return scheme.tertiary;
    case StudyActivity.mockExam:
      return scheme.onSurfaceVariant;
  }
}

class _LinkAction extends StatelessWidget {
  const _LinkAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(CockpitRadii.sm),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(label,
            style: theme.textTheme.labelMedium?.copyWith(color: scheme.primary)),
      ),
    );
  }
}

class _SelectionSummary extends StatelessWidget {
  const _SelectionSummary({required this.controller});
  final RecommendationsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Eyebrow('${c.selectedCount} Topics Selected')),
            if (c.selectedCount > 0)
              InkWell(
                onTap: c.clearSelection,
                child: Text('Clear',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: scheme.primary)),
              )
            else
              InkWell(
                onTap: c.selectAllReady,
                child: Text('Select All Ready',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: scheme.primary)),
              ),
          ],
        ),
        if (c.selectedCount > 0) ...[
          const SizedBox(height: CockpitSpacing.sm),
          Text(c.selectionSummary,
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: CockpitColors.brand.success,
                  fontWeight: FontWeight.w600)),
        ],
      ],
    );
  }
}

class _ManualSummary extends StatelessWidget {
  const _ManualSummary({required this.controller});
  final RecommendationsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow('${controller.manualBlockCount} Blocks Selected'),
        const SizedBox(height: CockpitSpacing.sm),
        Text(RecommendationsController.manualBreakdown.join('  ·  '),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(
      {required this.icon, required this.text, required this.tint});
  final IconData icon;
  final String text;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: tint),
        const SizedBox(width: CockpitSpacing.sm),
        Expanded(
          child: Text(text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}

// ===========================================================================
// Dialogs / navigation
// ===========================================================================
void _showWhy(BuildContext context, StudyTopic t) {
  showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle_rounded,
                color: CockpitColors.brand.success),
            const SizedBox(width: CockpitSpacing.sm),
            const Expanded(child: Text('Why this is ready')),
          ],
        ),
        content: Text(t.reasonWhy ?? 'This topic has sufficient material.',
            style: theme.textTheme.bodyMedium),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      );
    },
  );
}

void _continueToPanel15(BuildContext context, RecommendationsController c) {
  // Panel 14 → Panel 15: hand the selection to the conversion preview.
  context.go('/notes/convert');
}

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
  );
}
