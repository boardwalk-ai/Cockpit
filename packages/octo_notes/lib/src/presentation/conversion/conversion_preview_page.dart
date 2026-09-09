import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/conversion_controller.dart';
import '../../domain/recommendations_controller.dart' show StudyActivity;
import '../../theme/octo_notes_theme.dart';
import '../widgets/octo_widgets.dart';

/// Width at/above which the conversion preview shows the three-column workspace.
const double _kConvDesktop = 1040;

/// Panel 15 — Study Studio Conversion Preview (ON-P15).
///
/// Borderless / typography-first (see `DESIGN.md`). The final OctoNotes
/// checkpoint before selected notes become Study Studio material: review the
/// selected material, detected topics, source coverage, the editable activity
/// plan and the create-or-update destination. Nothing is created or updated —
/// and the source note is never mutated — until the student approves. See
/// `docs/panel-15-conversion-preview.md`.
class ConversionPreviewPage extends StatefulWidget {
  const ConversionPreviewPage({super.key});

  @override
  State<ConversionPreviewPage> createState() => _ConversionPreviewPageState();
}

class _ConversionPreviewPageState extends State<ConversionPreviewPage> {
  late final ConversionController _c;

  @override
  void initState() {
    super.initState();
    _c = ConversionController(sourceFinalNotesId: 'final-bio101-w4');
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _back() =>
      context.canPop() ? context.pop() : context.go('/notes/final');

  @override
  Widget build(BuildContext context) {
    return OctoNotesTheme.wrap(
      context: context,
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          final desktop = MediaQuery.sizeOf(context).width >= _kConvDesktop;
          return AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              return Scaffold(
                backgroundColor: scheme.surface,
                body: SafeArea(
                  child: Column(
                    children: [
                      _Header(controller: _c, onBack: _back),
                      Divider(height: 1, color: scheme.outlineVariant),
                      _Stepper(controller: _c),
                      Divider(height: 1, color: scheme.outlineVariant),
                      Expanded(
                        child: desktop
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                      flex: 3,
                                      child:
                                          _MaterialColumn(controller: _c)),
                                  VerticalDivider(
                                      width: 1, color: scheme.outlineVariant),
                                  Expanded(
                                      flex: 3,
                                      child:
                                          _ActivitiesColumn(controller: _c)),
                                  VerticalDivider(
                                      width: 1, color: scheme.outlineVariant),
                                  Expanded(
                                      flex: 3,
                                      child:
                                          _DestinationColumn(controller: _c)),
                                ],
                              )
                            : ListView(
                                padding: const EdgeInsets.all(CockpitSpacing.xl),
                                children: [
                                  _MaterialColumn(controller: _c, embed: true),
                                  const SizedBox(height: CockpitSpacing.xxl),
                                  _ActivitiesColumn(controller: _c, embed: true),
                                  const SizedBox(height: CockpitSpacing.xxl),
                                  _DestinationColumn(
                                      controller: _c, embed: true),
                                ],
                              ),
                      ),
                      Divider(height: 1, color: scheme.outlineVariant),
                      _BottomBar(controller: _c, onBack: _back),
                    ],
                  ),
                ),
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

/// A number + muted label metric, grouped by proximity (no box).
class _Metric extends StatelessWidget {
  const _Metric(this.value, this.label, {this.compact = false});
  final String value;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: (compact ? theme.textTheme.titleMedium : theme.textTheme.titleLarge)
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = color ?? scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: (color == null ? scheme.surfaceContainerHigh : c.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
      ),
      child: Text(label,
          style: theme.textTheme.labelSmall?.copyWith(
              color: c, fontWeight: color == null ? null : FontWeight.w600)),
    );
  }
}

/// A borderless segmented control — the selected segment fills red.
class _Segmented<T> extends StatelessWidget {
  const _Segmented(
      {required this.value, required this.items, required this.onChanged});
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.xxs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
      ),
      child: Row(
        children: [
          for (final (v, label) in items)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(CockpitRadii.pill),
                onTap: () => onChanged(v),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: CockpitSpacing.sm),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: v == value ? scheme.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(CockpitRadii.pill),
                  ),
                  child: Text(label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: v == value
                            ? Colors.white
                            : scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      )),
                ),
              ),
            ),
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

// ===========================================================================
// Header + stepper
// ===========================================================================
class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.onBack});
  final ConversionController controller;
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
              icon: const Icon(Icons.arrow_back_rounded), onPressed: onBack),
          const SizedBox(width: CockpitSpacing.xs),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Study Studio Conversion Preview',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              if (!compact)
                Text(
                    'Review exactly what OctoNotes will send before generation '
                    'begins.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
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
          _StatusText('Source Note Finalized', CockpitColors.brand.success,
              icon: Icons.check_circle_rounded),
          IconButton(
              icon: const Icon(Icons.more_vert_rounded), onPressed: () {}),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.controller});
  final ConversionController controller;

  @override
  Widget build(BuildContext context) {
    final steps = ['Material Selected', 'Configure Activities', 'Destination'];
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.xxl, vertical: CockpitSpacing.md),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Row(
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                _Step(index: i, label: steps[i], current: controller.step),
                if (i != steps.length - 1)
                  Expanded(child: _Connector(done: i < controller.step)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(
      {required this.index, required this.label, required this.current});
  final int index;
  final String label;
  final int current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done = index < current;
    final active = index == current;
    final color = done
        ? CockpitColors.brand.success
        : active
            ? scheme.primary
            : scheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done || active ? color : scheme.surfaceContainerHigh,
            shape: BoxShape.circle,
          ),
          child: done
              ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
              : Text('${index + 1}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: active ? Colors.white : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  )),
        ),
        const SizedBox(width: CockpitSpacing.sm),
        Text(label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: active ? scheme.primary : scheme.onSurface,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            )),
      ],
    );
  }
}

class _Connector extends StatelessWidget {
  const _Connector({required this.done});
  final bool done;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: CockpitSpacing.md),
      color: done ? CockpitColors.brand.success : scheme.outlineVariant,
    );
  }
}

// ===========================================================================
// Column 1 — Selected material (spec §6–7, §13)
// ===========================================================================
class _MaterialColumn extends StatelessWidget {
  const _MaterialColumn({required this.controller, this.embed = false});
  final ConversionController controller;
  final bool embed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = controller;
    final content = <Widget>[
      const Eyebrow('Selected Material'),
      const SizedBox(height: CockpitSpacing.lg),
      Wrap(
        spacing: CockpitSpacing.xl,
        runSpacing: CockpitSpacing.lg,
        children: [for (final s in c.stats) _Metric(s.value, s.label, compact: true)],
      ),
      const SizedBox(height: CockpitSpacing.xl),
      for (final t in c.selectedTopics)
        OctoHoverRow(
          onTap: () {},
          child: Row(
            children: [
              Icon(Icons.check_circle_rounded,
                  size: 18, color: CockpitColors.brand.success),
              const SizedBox(width: CockpitSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(t.meta,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Text('Edit',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: scheme.primary)),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      const SizedBox(height: CockpitSpacing.xl),
      Row(
        children: [
          const Eyebrow('Source Coverage'),
          const SizedBox(width: CockpitSpacing.md),
          _StatusText('Strong coverage', CockpitColors.brand.success,
              icon: Icons.check_circle_rounded),
        ],
      ),
      const SizedBox(height: CockpitSpacing.md),
      Wrap(
        spacing: CockpitSpacing.xs,
        runSpacing: CockpitSpacing.xs,
        children: [
          for (var i = 0; i < c.coverageTags.length; i++)
            _Tag(c.coverageTags[i],
                color: i == c.coverageTags.length - 1 ? scheme.primary : null),
        ],
      ),
      const SizedBox(height: CockpitSpacing.md),
      for (final s in c.sourceRows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.xs),
          child: Row(
            children: [
              Icon(s.icon, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: CockpitSpacing.md),
              Text(s.label, style: theme.textTheme.bodyMedium),
              Text('  ·  ${s.detail}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      const SizedBox(height: CockpitSpacing.lg),
      OutlinedButton.icon(
        onPressed: () {},
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outlineVariant),
        ),
        icon: const Icon(Icons.visibility_outlined, size: 16),
        label: const Text('Preview Sources'),
      ),
      const SizedBox(height: CockpitSpacing.lg),
      Row(
        children: [
          Icon(Icons.check_circle_rounded,
              size: 16, color: CockpitColors.brand.success),
          const SizedBox(width: CockpitSpacing.sm),
          Expanded(
            child: Text('Every generated activity will link back to its source.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    ];
    if (embed) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: content);
    }
    return ListView(
      padding: const EdgeInsets.all(CockpitSpacing.xl),
      children: content,
    );
  }
}

// ===========================================================================
// Column 2 — Proposed activities (spec §10–12)
// ===========================================================================
class _ActivitiesColumn extends StatelessWidget {
  const _ActivitiesColumn({required this.controller, this.embed = false});
  final ConversionController controller;
  final bool embed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = controller;
    final content = <Widget>[
      const Eyebrow('Proposed Learning Activities'),
      const SizedBox(height: CockpitSpacing.xs),
      Text('Adjust the plan before generation.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant)),
      const SizedBox(height: CockpitSpacing.lg),
      for (var i = 0; i < c.activities.length; i++)
        _ActivityRow(controller: c, activity: c.activities[i], number: i + 1),
      const SizedBox(height: CockpitSpacing.xl),
      const Eyebrow('Learning Level'),
      const SizedBox(height: CockpitSpacing.md),
      _Segmented<LearningLevel>(
        value: c.level,
        onChanged: c.setLevel,
        items: const [
          (LearningLevel.foundation, 'Foundation'),
          (LearningLevel.balanced, 'Balanced'),
          (LearningLevel.challenging, 'Challenging'),
        ],
      ),
      const SizedBox(height: CockpitSpacing.sm),
      Text('Counts are generation targets and can be changed.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant)),
      const SizedBox(height: CockpitSpacing.xl),
      const Eyebrow('Detected Topics'),
      const SizedBox(height: CockpitSpacing.md),
      for (final t in c.topics) _DetectedTopicRow(topic: t),
    ];
    if (embed) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: content);
    }
    return ListView(
      padding: const EdgeInsets.all(CockpitSpacing.xl),
      children: content,
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow(
      {required this.controller, required this.activity, required this.number});
  final ConversionController controller;
  final PlannedActivity activity;
  final int number;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final a = activity;
    final color = _activityColor(a.type, scheme);
    final dim = !a.available;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.sm),
      child: Row(
        children: [
          Icon(a.type.icon,
              size: 22,
              color: dim ? scheme.onSurfaceVariant.withValues(alpha: 0.5) : color),
          const SizedBox(width: CockpitSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$number. ${a.type.label}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: dim ? scheme.onSurfaceVariant : scheme.onSurface,
                    )),
                const SizedBox(height: 2),
                Text(a.outputLabel,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (a.available) ...[
            _CountStepper(
              value: a.count,
              onDec: () => controller.bumpActivity(a.type, -1),
              onInc: () => controller.bumpActivity(a.type, 1),
            ),
            const SizedBox(width: CockpitSpacing.md),
            SizedBox(
              width: 96,
              child: Text(a.scope,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: CockpitSpacing.sm),
          ],
          Switch(
            value: a.enabled,
            onChanged:
                a.available ? (_) => controller.toggleActivity(a.type) : null,
          ),
        ],
      ),
    );
  }
}

class _CountStepper extends StatelessWidget {
  const _CountStepper(
      {required this.value, required this.onDec, required this.onInc});
  final int value;
  final VoidCallback onDec;
  final VoidCallback onInc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget btn(IconData i, VoidCallback t) => InkWell(
          borderRadius: BorderRadius.circular(CockpitRadii.pill),
          onTap: t,
          child: Padding(
            padding: const EdgeInsets.all(CockpitSpacing.xs),
            child: Icon(i, size: 16, color: scheme.onSurfaceVariant),
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.xs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(Icons.remove_rounded, onDec),
          SizedBox(
            width: 24,
            child: Text('$value',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          btn(Icons.add_rounded, onInc),
        ],
      ),
    );
  }
}

class _DetectedTopicRow extends StatelessWidget {
  const _DetectedTopicRow({required this.topic});
  final ConversionTopic topic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_rounded,
              size: 18, color: CockpitColors.brand.success),
          const SizedBox(width: CockpitSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(topic.title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(topic.subtopics.join(', '),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          _StatusText(topic.coverage.label, CockpitColors.brand.success,
              icon: Icons.check_circle_rounded),
          const SizedBox(width: CockpitSpacing.sm),
          Icon(Icons.edit_outlined, size: 15, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

// ===========================================================================
// Column 3 — Destination (spec §15–18)
// ===========================================================================
class _DestinationColumn extends StatelessWidget {
  const _DestinationColumn({required this.controller, this.embed = false});
  final ConversionController controller;
  final bool embed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = controller;
    final updating = c.destination == DestinationMode.updateExisting;
    final content = <Widget>[
      const Eyebrow('Destination'),
      const SizedBox(height: CockpitSpacing.lg),
      _Segmented<DestinationMode>(
        value: c.destination,
        onChanged: c.setDestination,
        items: const [
          (DestinationMode.createNew, 'Create New'),
          (DestinationMode.updateExisting, 'Update Existing'),
        ],
      ),
      const SizedBox(height: CockpitSpacing.xl),
      if (updating) ...[
        // Existing studio match.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.menu_book_rounded, color: scheme.primary),
            const SizedBox(width: CockpitSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.existingStudioName,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: CockpitSpacing.xs),
                  _StatusText('Existing Study Studio',
                      CockpitColors.brand.success),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: CockpitSpacing.lg),
        Wrap(
          spacing: CockpitSpacing.xl,
          runSpacing: CockpitSpacing.md,
          children: [
            _Metric(c.existingMastery, 'Current mastery', compact: true),
            _Metric(c.existingLastStudied, 'Last studied', compact: true),
            _Metric('${c.existingTopicCount}', 'Existing topics', compact: true),
          ],
        ),
        const SizedBox(height: CockpitSpacing.xl),
        const Eyebrow('Update Strategy'),
        const SizedBox(height: CockpitSpacing.sm),
        for (final s in UpdateStrategy.values)
          _StrategyRow(controller: c, strategy: s),
        const SizedBox(height: CockpitSpacing.lg),
        // Preservation assurance — plain row, no box.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline_rounded,
                size: 18, color: CockpitColors.brand.success),
            const SizedBox(width: CockpitSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Preserve mastery and study history',
                      style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: CockpitColors.brand.success)),
                  const SizedBox(height: 2),
                  Text(
                      'Quiz attempts, flashcard progress, spaced repetition and '
                      'weak-area tracking remain unchanged.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ] else ...[
        // Create-new fields.
        Text('New Study Studio',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: CockpitSpacing.md),
        TextField(
          controller: TextEditingController(text: 'Cellular Respiration'),
          decoration: const InputDecoration(labelText: 'Study Studio title'),
        ),
        const SizedBox(height: CockpitSpacing.md),
        TextField(
          controller: TextEditingController(text: c.course),
          decoration: const InputDecoration(labelText: 'Course'),
        ),
        const SizedBox(height: CockpitSpacing.md),
        Text('Topics: ${c.topics.map((t) => t.title.replaceFirst(RegExp(r'^\d+\.\s*'), '')).join(', ')}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant)),
      ],
      const SizedBox(height: CockpitSpacing.xxl),
      const Eyebrow('Conversion Summary'),
      const SizedBox(height: CockpitSpacing.md),
      Wrap(
        spacing: CockpitSpacing.xxl,
        runSpacing: CockpitSpacing.lg,
        children: [for (final m in c.summary) _Metric(m.value, m.label, compact: true)],
      ),
      const SizedBox(height: CockpitSpacing.xl),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: CockpitSpacing.sm),
          Expanded(
            child: Text(
                'Original OctoNotes material will remain unchanged. Study Studio '
                'will use only the material shown in this preview.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    ];
    if (embed) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: content);
    }
    return ListView(
      padding: const EdgeInsets.all(CockpitSpacing.xl),
      children: content,
    );
  }
}

class _StrategyRow extends StatelessWidget {
  const _StrategyRow({required this.controller, required this.strategy});
  final ConversionController controller;
  final UpdateStrategy strategy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = controller.strategy == strategy;
    final recommended = strategy == UpdateStrategy.updateMatching;
    return InkWell(
      borderRadius: BorderRadius.circular(CockpitRadii.sm),
      onTap: () => controller.setStrategy(strategy),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: CockpitSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(strategy.label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600)),
                      ),
                      if (recommended) ...[
                        const SizedBox(width: CockpitSpacing.sm),
                        _Tag('Recommended', color: CockpitColors.brand.success),
                      ],
                    ],
                  ),
                  if (selected) ...[
                    const SizedBox(height: 2),
                    Text(strategy.detail,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Bottom action bar (spec §19)
// ===========================================================================
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.controller, required this.onBack});
  final ConversionController controller;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = controller;
    final compact = MediaQuery.sizeOf(context).width < 1180;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.lg, vertical: CockpitSpacing.md),
      child: Row(
        children: [
          if (!compact) ...[
            Icon(Icons.check_circle_rounded,
                size: 16, color: CockpitColors.brand.success),
            const SizedBox(width: CockpitSpacing.xs),
            Text('Conversion draft saved',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
          const Spacer(),
          TextButton(
            onPressed: onBack,
            style: TextButton.styleFrom(foregroundColor: scheme.onSurface),
            child: const Text('Back to Recommendations'),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          OutlinedButton.icon(
            onPressed: () {
              c.saveDraft();
              _snack(context, 'Conversion draft saved');
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.onSurface,
              side: BorderSide(color: scheme.outlineVariant),
            ),
            icon: const Icon(Icons.save_outlined, size: 16),
            label: const Text('Save Conversion Draft'),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => _snack(context, 'Preview sources'),
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.onSurface,
              side: BorderSide(color: scheme.outlineVariant),
            ),
            icon: const Icon(Icons.visibility_outlined, size: 16),
            label: const Text('Preview Sources'),
          ),
          const SizedBox(width: CockpitSpacing.lg),
          if (!compact) ...[
            Icon(Icons.lock_outline_rounded,
                size: 15, color: scheme.onSurfaceVariant),
            const SizedBox(width: CockpitSpacing.xs),
            Text('Nothing is created\nuntil you approve.',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(width: CockpitSpacing.lg),
          ],
          FilledButton.icon(
            onPressed:
                c.canGenerate ? () => _showConfirm(context, c) : null,
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: Text(c.destination == DestinationMode.createNew
                ? 'Create & Generate'
                : 'Update & Generate'),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Confirmation (spec §20)
// ===========================================================================
void _showConfirm(BuildContext pageContext, ConversionController c) {
  final creating = c.destination == DestinationMode.createNew;
  showDialog<void>(
    context: pageContext,
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      Widget line(IconData i, String text) => Padding(
            padding: const EdgeInsets.only(bottom: CockpitSpacing.sm),
            child: Row(children: [
              Icon(i, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: CockpitSpacing.sm),
              Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
            ]),
          );
      return AlertDialog(
        title: Text(creating
            ? 'Create “Cellular Respiration” in Study Studio?'
            : 'Update “${c.existingStudioName}” with ${c.topics.length} topics?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            line(Icons.folder_outlined,
                creating ? 'New Study Studio' : c.existingStudioName),
            line(Icons.account_tree_outlined, '${c.topics.length} topics'),
            line(Icons.auto_awesome_rounded,
                '${c.activityTypeCount} activity types'),
            line(Icons.link_rounded, '${c.sourceConnections} source connections'),
            if (!creating)
              line(Icons.lock_outline_rounded,
                  'Existing mastery and study history preserved'),
            const SizedBox(height: CockpitSpacing.xs),
            Text('AI will generate ${c.learningItemsPlanned} learning items.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Continue Editing'),
          ),
          FilledButton(
            onPressed: () {
              c.generate();
              Navigator.of(context).pop();
              ScaffoldMessenger.of(pageContext).showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  content: Text(creating
                      ? 'Creating Study Studio · generating ${c.learningItemsPlanned} items…'
                      : 'Updating ${c.existingStudioName} · generating ${c.learningItemsPlanned} items…'),
                ),
              );
            },
            child: Text(creating ? 'Create and Generate' : 'Update and Generate'),
          ),
        ],
      );
    },
  );
}

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
  );
}
