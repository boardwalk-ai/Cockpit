import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/octo_notes_theme.dart';
import '../new_session/new_session_dialog.dart';
import '../widgets/octo_widgets.dart';

/// Width at/above which OctoNotes uses the desktop layout. PC-first for now.
const double kOctoDesktop = 900;

bool _isDesktop(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kOctoDesktop;

/// OctoNotes — Home (Page 1). Borderless / typography-first: grouping comes from
/// whitespace, hierarchy and proximity rather than cards and dividers.
class OctoNotesHomePage extends StatelessWidget {
  const OctoNotesHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return OctoNotesTheme.wrap(
      context: context,
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          final desktop = _isDesktop(context);
          final pad = desktop ? CockpitSpacing.xxxl : CockpitSpacing.lg;
          return Scaffold(
            backgroundColor: scheme.surface,
            drawer: const _OctoDrawer(),
            body: SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1600),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      pad,
                      CockpitSpacing.lg,
                      pad,
                      CockpitSpacing.lg,
                    ),
                    // Desktop: everything fits the viewport — the page never
                    // scrolls; only the Recent Notes list flexes/scrolls if a
                    // very short screen forces it. Mobile: normal page scroll.
                    child: desktop
                        ? _DesktopHome()
                        : ListView(
                            padding: EdgeInsets.zero,
                            children: const [
                              _HeaderBar(),
                              SizedBox(height: CockpitSpacing.lg),
                              _LiveSessionStrip(),
                              SizedBox(height: CockpitSpacing.xl),
                              _QuickStartSection(),
                              SizedBox(height: CockpitSpacing.xl),
                              _MainColumns(desktop: false),
                              SizedBox(height: CockpitSpacing.xl),
                              _SyncFooter(),
                            ],
                          ),
                  ),
                ),
                  ),
                  const Positioned(
                    right: CockpitSpacing.xl,
                    bottom: CockpitSpacing.xl,
                    child: OctoThemeSwitcher(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Desktop home that fills the viewport height with no page scroll.
class _DesktopHome extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _HeaderBar(),
        const SizedBox(height: CockpitSpacing.lg),
        const _LiveSessionStrip(),
        const SizedBox(height: CockpitSpacing.xl),
        const _QuickStartSection(),
        const SizedBox(height: CockpitSpacing.xl),
        const Expanded(child: _MainColumns(desktop: true)),
        const SizedBox(height: CockpitSpacing.md),
        const _SyncFooter(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------
class _HeaderBar extends StatelessWidget {
  const _HeaderBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final desktop = _isDesktop(context);

    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Menu',
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
        const SizedBox(width: CockpitSpacing.sm),
        Text('OctoNotes', style: theme.textTheme.headlineMedium),
      ],
    );

    final newSession = FilledButton.icon(
      onPressed: () => showNewSessionDialog(context),
      icon: const Icon(Icons.add_rounded, size: 20),
      label: const Text('New Session'),
    );

    if (!desktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Flexible(child: title), newSession],
          ),
          const SizedBox(height: CockpitSpacing.lg),
          const _SearchField(),
          const SizedBox(height: CockpitSpacing.md),
          const _DevicesStatus(),
        ],
      );
    }

    return Row(
      children: [
        title,
        const SizedBox(width: CockpitSpacing.xxl),
        const Expanded(child: _SearchField()),
        const SizedBox(width: CockpitSpacing.xxl),
        const _DevicesStatus(),
        const SizedBox(width: CockpitSpacing.lg),
        newSession,
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      decoration: InputDecoration(
        hintText: 'Search notes, courses, or topics',
        prefixIcon: Icon(Icons.search_rounded, color: scheme.onSurfaceVariant),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: CockpitSpacing.md),
      ),
    );
  }
}

class _DevicesStatus extends StatelessWidget {
  const _DevicesStatus();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 8, color: CockpitColors.brand.success),
        const SizedBox(width: CockpitSpacing.sm),
        Text('All devices synced',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// LIVE session — the one place a subtle background earns its keep.
// ---------------------------------------------------------------------------
class _LiveSessionStrip extends StatelessWidget {
  const _LiveSessionStrip();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final desktop = _isDesktop(context);

    return OctoSurface(
      onTap: () => context.go('/notes/session'),
      padding: const EdgeInsets.symmetric(
        horizontal: CockpitSpacing.xl,
        vertical: CockpitSpacing.lg,
      ),
      child: Row(
        children: [
          const LiveDot(label: 'LIVE'),
          const SizedBox(width: CockpitSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Biology 101 — Cellular Respiration',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: CockpitSpacing.xxs),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.smartphone_rounded,
                        size: 14, color: scheme.onSurfaceVariant),
                    const SizedBox(width: CockpitSpacing.xs),
                    Text("Recording on Hein's iPhone",
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ),
          if (desktop) ...[
            const Waveform(),
            const SizedBox(width: CockpitSpacing.xl),
            Text('42:16', style: theme.textTheme.titleMedium),
            const SizedBox(width: CockpitSpacing.xl),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 8, color: CockpitColors.brand.success),
                const SizedBox(width: CockpitSpacing.xs),
                Text('Live Sync', style: theme.textTheme.labelMedium),
              ],
            ),
            const SizedBox(width: CockpitSpacing.xl),
          ],
          FilledButton(
            onPressed: () => context.go('/notes/session'),
            child: const Text('Open Live Session'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick Start — borderless items, whitespace-separated.
// ---------------------------------------------------------------------------
class _QuickStartSection extends StatelessWidget {
  const _QuickStartSection();

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.mic_none_rounded, 'Start Recording'),
      (Icons.note_add_outlined, 'New Note'),
      (Icons.history_rounded, 'Continue Last Session'),
    ];
    final desktop = _isDesktop(context);
    final tiles = [for (final (i, l) in items) _QuickStartTile(icon: i, label: l)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Quick Start'),
        const SizedBox(height: CockpitSpacing.lg),
        if (desktop)
          Row(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                Expanded(child: tiles[i]),
                if (i != tiles.length - 1)
                  const SizedBox(width: CockpitSpacing.lg),
              ],
            ],
          )
        else
          Column(children: [
            for (final t in tiles) ...[
              t,
              const SizedBox(height: CockpitSpacing.xs)
            ],
          ]),
      ],
    );
  }
}

class _QuickStartTile extends StatelessWidget {
  const _QuickStartTile({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OctoHoverRow(
      onTap: () {},
      padding: const EdgeInsets.symmetric(
        horizontal: CockpitSpacing.md,
        vertical: CockpitSpacing.md,
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: CockpitSpacing.md),
          Text(label, style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Two columns
// ---------------------------------------------------------------------------
class _MainColumns extends StatelessWidget {
  const _MainColumns({required this.desktop});
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    if (!desktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          _ContinueSection(),
          SizedBox(height: CockpitSpacing.xl),
          _SuggestionSection(),
          SizedBox(height: CockpitSpacing.xl),
          _RecentNotesSection(),
        ],
      );
    }
    // Fill the available height: Continue stays fixed at the top of the left
    // column; Recent Notes takes the rest (and only IT scrolls if a short screen
    // demands it). The suggestion panel scrolls internally as a safety net too.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ContinueSection(),
              SizedBox(height: CockpitSpacing.xl),
              Expanded(child: _RecentNotesSection(expand: true)),
            ],
          ),
        ),
        SizedBox(width: CockpitSpacing.xxl),
        Expanded(
          flex: 2,
          child: SingleChildScrollView(child: _SuggestionSection()),
        ),
      ],
    );
  }
}

class _ContinueSection extends StatelessWidget {
  const _ContinueSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Eyebrow('Continue'),
        SizedBox(height: CockpitSpacing.lg),
        _ContinueRow(
          leading: Icon(Icons.hourglass_top_rounded),
          title: 'Macroeconomics — Inflation & Monetary Policy',
          subtitle: 'Transcribing 72%',
          progress: 0.72,
        ),
        SizedBox(height: CockpitSpacing.sm),
        _ContinueRow(
          leading: Icon(Icons.check_circle_rounded),
          title: 'Contract Law — Consideration',
          subtitle: 'Ready for Review',
          ready: true,
        ),
      ],
    );
  }
}

class _ContinueRow extends StatelessWidget {
  const _ContinueRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    this.progress,
    this.ready = false,
  });
  final Widget leading;
  final String title;
  final String subtitle;
  final double? progress;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return OctoHoverRow(
      onTap: () {},
      child: Row(
        children: [
          IconTheme(
            data: IconThemeData(
              color: ready ? CockpitColors.brand.success : scheme.primary,
              size: 22,
            ),
            child: leading,
          ),
          const SizedBox(width: CockpitSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: CockpitSpacing.xxs),
                Text(subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ready
                          ? CockpitColors.brand.success
                          : scheme.onSurfaceVariant,
                    )),
                if (progress != null) ...[
                  const SizedBox(height: CockpitSpacing.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(CockpitRadii.pill),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: scheme.surfaceContainerHigh,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: CockpitSpacing.md),
          Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recent Notes
// ---------------------------------------------------------------------------
class _RecentNotesSection extends StatelessWidget {
  const _RecentNotesSection({this.expand = false});

  /// When true, the note list fills remaining height and scrolls internally
  /// (only IT scrolls — the page never does).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final header = Row(
      children: [
        const Expanded(child: Eyebrow('Recent Notes')),
        Wrap(
          spacing: CockpitSpacing.xs,
          children: const [
            _FilterButton('Course'),
            _FilterButton('Status'),
            _FilterButton('Date'),
            _FilterButton('Study Ready'),
          ],
        ),
      ],
    );
    const notes = [
      _NoteRow(
        icon: Icons.mic_none_rounded,
        title: 'Cellular Respiration — Glycolysis',
        course: 'Biology 101',
        date: 'May 8, 2025',
        duration: '38:24',
        deck: 'The Deck / Biology 101',
      ),
      _NoteRow(
        icon: Icons.edit_note_rounded,
        title: 'Inflation: Causes & Effects',
        course: 'Macroeconomics',
        date: 'May 7, 2025',
        duration: '52:11',
        deck: 'The Deck / Macroecon',
      ),
      _NoteRow(
        icon: Icons.check_circle_rounded,
        title: 'Contract Law — Offer & Acceptance',
        course: 'Contract Law',
        date: 'May 5, 2025',
        duration: '45:02',
        deck: 'The Deck / Contract Law',
        finalized: true,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: CockpitSpacing.md),
        if (expand)
          Expanded(
            child: ListView(padding: EdgeInsets.zero, children: notes),
          )
        else
          ...notes,
      ],
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextButton(
      onPressed: () {},
      style: TextButton.styleFrom(
        foregroundColor: theme.colorScheme.onSurfaceVariant,
        padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.sm,
          vertical: CockpitSpacing.xs,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          const Icon(Icons.expand_more_rounded, size: 16),
        ],
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.icon,
    required this.title,
    required this.course,
    required this.date,
    required this.duration,
    required this.deck,
    this.finalized = false,
  });

  final IconData icon;
  final String title;
  final String course;
  final String date;
  final String duration;
  final String deck;
  final bool finalized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final desktop = _isDesktop(context);

    return OctoHoverRow(
      onTap: () {},
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: CockpitSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: CockpitSpacing.xxs),
                Wrap(
                  spacing: CockpitSpacing.md,
                  runSpacing: CockpitSpacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(course,
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: scheme.primary)),
                    if (desktop) ...[
                      Text('$date · $duration',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                      Text(deck,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (finalized) ...[
            Text('Finalized',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: CockpitColors.brand.success)),
            const SizedBox(width: CockpitSpacing.lg),
          ],
          for (final a in const [
            Icons.mic_none_rounded,
            Icons.text_fields_rounded,
            Icons.edit_outlined,
          ])
            Padding(
              padding: const EdgeInsets.only(left: CockpitSpacing.sm),
              child: Icon(a, size: 17, color: scheme.onSurfaceVariant),
            ),
          const SizedBox(width: CockpitSpacing.sm),
          Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Study Studio suggestion
// ---------------------------------------------------------------------------
class _SuggestionSection extends StatelessWidget {
  const _SuggestionSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Study Studio Suggestions'),
        const SizedBox(height: CockpitSpacing.lg),
        OctoSurface(
          padding: const EdgeInsets.all(CockpitSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.menu_book_rounded, color: scheme.primary),
              const SizedBox(height: CockpitSpacing.lg),
              Text('Cellular Respiration Study Set',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: CockpitSpacing.xs),
              Text('3 connected lectures are ready for active study',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: CockpitSpacing.lg),
              Wrap(
                spacing: CockpitSpacing.sm,
                runSpacing: CockpitSpacing.sm,
                children: const [
                  OctoChip('Glycolysis'),
                  OctoChip('Krebs Cycle'),
                  OctoChip('ETC'),
                  OctoChip('ATP Synthesis'),
                  OctoChip('Fermentation'),
                ],
              ),
              const SizedBox(height: CockpitSpacing.xl),
              Row(
                children: [
                  FilledButton(
                      onPressed: () {}, child: const Text('Review Suggestion')),
                  const SizedBox(width: CockpitSpacing.sm),
                  TextButton(onPressed: () {}, child: const Text('Not Now')),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Footer + Drawer
// ---------------------------------------------------------------------------
class _SyncFooter extends StatelessWidget {
  const _SyncFooter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.circle, size: 8, color: CockpitColors.brand.success),
        const SizedBox(width: CockpitSpacing.sm),
        Text('All devices synced',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _OctoDrawer extends StatelessWidget {
  const _OctoDrawer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const items = [
      (Icons.description_outlined, 'OctoNotes', true),
      (Icons.layers_outlined, 'The Deck', false),
      (Icons.school_rounded, 'Study Studio', false),
      (Icons.article_outlined, 'DocOct', false),
    ];
    return Drawer(
      backgroundColor: scheme.surface,
      elevation: 0,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(CockpitSpacing.xl),
              child: Row(
                children: [
                  Icon(Icons.hub_rounded, color: scheme.primary),
                  const SizedBox(width: CockpitSpacing.sm),
                  Text('OctoPilot', style: theme.textTheme.titleMedium),
                ],
              ),
            ),
            for (final (icon, label, active) in items)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: CockpitSpacing.md,
                  vertical: CockpitSpacing.xxs,
                ),
                child: OctoHoverRow(
                  onTap: () => Navigator.of(context).pop(),
                  selected: active,
                  child: Row(
                    children: [
                      Icon(icon,
                          size: 20,
                          color: active
                              ? scheme.primary
                              : scheme.onSurfaceVariant),
                      const SizedBox(width: CockpitSpacing.md),
                      Text(label,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: active ? scheme.primary : null,
                          )),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
