import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/octo_notes_theme.dart';
import '../widgets/octo_widgets.dart';

/// Opens the "New OctoNotes Session" modal. Wrapped in [OctoNotesTheme] so the
/// dialog (which lives in the root overlay, outside the home page's Theme) still
/// gets Work Sans + pill buttons, and tracks the app-wide dark/light setting.
Future<void> showNewSessionDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.62),
    builder: (context) => OctoNotesTheme.wrap(
      context: context,
      child: const NewSessionDialog(),
    ),
  );
}

class NewSessionDialog extends StatefulWidget {
  const NewSessionDialog({super.key});

  @override
  State<NewSessionDialog> createState() => _NewSessionDialogState();
}

class _NewSessionDialogState extends State<NewSessionDialog> {
  int _workspace = 0; // 0=Typewriter, 1=Magic Pencil, 2=Lecture Capture
  bool _record = true;
  bool _liveTranscription = true;
  bool _smartOrganization = true;
  bool _liveSuggestions = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final narrow = MediaQuery.sizeOf(context).width < 820;

    return Dialog(
      // The modal surface: a slightly-raised warm near-black that separates from
      // the near-black page behind it. On light it becomes the warm off-white.
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: CockpitSpacing.xl,
        vertical: CockpitSpacing.lg,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CockpitRadii.xl),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 900),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Header(),
            const SizedBox(height: CockpitSpacing.xs),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(CockpitSpacing.lg),
                child: narrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SessionDetails(),
                          const SizedBox(height: CockpitSpacing.lg),
                          _buildWorkspacePanel(),
                        ],
                      )
                    : IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _SessionDetails()),
                            const SizedBox(width: CockpitSpacing.xl),
                            Expanded(child: _buildWorkspacePanel()),
                          ],
                        ),
                      ),
              ),
            ),
            const SizedBox(height: CockpitSpacing.xs),
            _Footer(workspaceLabel: _workspaceLabels[_workspace], recording: _record),
          ],
        ),
      ),
    );
  }

  static const _workspaceLabels = ['Typewriter', 'Magic Pencil', 'Lecture Capture'];

  _WorkspacePanel _buildWorkspacePanel() => _WorkspacePanel(
        workspace: _workspace,
        onWorkspace: (i) => setState(() => _workspace = i),
        record: _record,
        onRecord: (v) => setState(() => _record = v),
        liveTranscription: _liveTranscription,
        onLiveTranscription: (v) => setState(() => _liveTranscription = v),
        smartOrganization: _smartOrganization,
        onSmartOrganization: (v) => setState(() => _smartOrganization = v),
        liveSuggestions: _liveSuggestions,
        onLiveSuggestions: (v) => setState(() => _liveSuggestions = v),
      );
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CockpitSpacing.xl,
        CockpitSpacing.lg,
        CockpitSpacing.lg,
        CockpitSpacing.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'New OctoNotes Session',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: CockpitSpacing.xxs),
                Text(
                  'Set up your workspace and start taking notes',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.history_rounded, size: 18),
            label: const Text('Use Last Settings'),
          ),
          const SizedBox(width: CockpitSpacing.xs),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Left column — Session Details
// ---------------------------------------------------------------------------
class _SessionDetails extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Session Details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel('Session Title'),
          const _TextInput(hint: 'Cellular Respiration Lecture'),
          const SizedBox(height: CockpitSpacing.lg),
          const _FieldLabel('Course'),
          const _SelectInput(value: 'Biology 101'),
          const SizedBox(height: CockpitSpacing.lg),
          const _FieldLabel('Topic'),
          const _SelectInput(value: 'Cellular Respiration'),
          const SizedBox(height: CockpitSpacing.lg),
          const _DeckRow(),
          const SizedBox(height: CockpitSpacing.lg),
          Text('Materials & Slides',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: CockpitSpacing.sm),
          const _MaterialRow(),
          const SizedBox(height: CockpitSpacing.sm),
          const _AddMaterialsButton(),
        ],
      ),
    );
  }
}

class _DeckRow extends StatelessWidget {
  const _DeckRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _Tile(
      child: Row(
        children: [
          _IconBadge(icon: Icons.folder_rounded, color: scheme.primary),
          const SizedBox(width: CockpitSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Save in The Deck', style: theme.textTheme.titleSmall),
                const SizedBox(height: CockpitSpacing.xxs),
                Text(
                  'Biology 101 / Lectures / Week 4',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: () {}, child: const Text('Change')),
        ],
      ),
    );
  }
}

class _MaterialRow extends StatelessWidget {
  const _MaterialRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _Tile(
      child: Row(
        children: [
          _IconBadge(icon: Icons.picture_as_pdf_rounded, color: scheme.primary),
          const SizedBox(width: CockpitSpacing.md),
          Expanded(
            child: Text('Week 4 Slides.pdf', style: theme.textTheme.titleSmall),
          ),
          Icon(Icons.check_circle_rounded,
              size: 16, color: CockpitColors.brand.success),
          const SizedBox(width: CockpitSpacing.xs),
          Text('Ready',
              style: theme.textTheme.labelMedium?.copyWith(
                color: CockpitColors.brand.success,
              )),
        ],
      ),
    );
  }
}

class _AddMaterialsButton extends StatelessWidget {
  const _AddMaterialsButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Add Materials'),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Right column — Primary Workspace + AI Assistance
// ---------------------------------------------------------------------------
class _WorkspacePanel extends StatelessWidget {
  const _WorkspacePanel({
    required this.workspace,
    required this.onWorkspace,
    required this.record,
    required this.onRecord,
    required this.liveTranscription,
    required this.onLiveTranscription,
    required this.smartOrganization,
    required this.onSmartOrganization,
    required this.liveSuggestions,
    required this.onLiveSuggestions,
  });

  final int workspace;
  final ValueChanged<int> onWorkspace;
  final bool record;
  final ValueChanged<bool> onRecord;
  final bool liveTranscription;
  final ValueChanged<bool> onLiveTranscription;
  final bool smartOrganization;
  final ValueChanged<bool> onSmartOrganization;
  final bool liveSuggestions;
  final ValueChanged<bool> onLiveSuggestions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _Panel(
      title: 'Primary Workspace',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                Expanded(
                  child: _WorkspaceCard(
                    icon: _workspaceIcons[i],
                    label: _NewSessionDialogState._workspaceLabels[i],
                    selected: workspace == i,
                    onTap: () => onWorkspace(i),
                  ),
                ),
                if (i != 2) const SizedBox(width: CockpitSpacing.sm),
              ],
            ],
          ),
          const SizedBox(height: CockpitSpacing.lg),
          _ToggleTile(
            title: 'Record Lecture',
            value: record,
            onChanged: onRecord,
          ),
          if (record) ...[
            const SizedBox(height: CockpitSpacing.sm),
            const _FieldLabel('Recording Source'),
            _Tile(
              child: Row(
                children: [
                  Icon(Icons.smartphone_rounded, size: 18, color: scheme.primary),
                  const SizedBox(width: CockpitSpacing.md),
                  Expanded(
                    child: Text("Hein's iPhone",
                        style: theme.textTheme.titleSmall),
                  ),
                  Icon(Icons.circle, size: 8, color: CockpitColors.brand.success),
                  const SizedBox(width: CockpitSpacing.xs),
                  Text('Connected',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: CockpitColors.brand.success,
                      )),
                  const Icon(Icons.arrow_drop_down_rounded),
                ],
              ),
            ),
          ],
          const SizedBox(height: CockpitSpacing.lg),
          Text('AI Assistance', style: theme.textTheme.titleSmall),
          const SizedBox(height: CockpitSpacing.sm),
          _ToggleTile(
            icon: Icons.mic_none_rounded,
            title: 'Live Transcription',
            value: liveTranscription,
            onChanged: onLiveTranscription,
          ),
          const SizedBox(height: CockpitSpacing.sm),
          _ToggleTile(
            icon: Icons.folder_open_rounded,
            title: 'Smart Organization',
            value: smartOrganization,
            onChanged: onSmartOrganization,
          ),
          const SizedBox(height: CockpitSpacing.sm),
          _ToggleTile(
            icon: Icons.lightbulb_outline_rounded,
            title: 'Live AI Suggestions',
            value: liveSuggestions,
            onChanged: onLiveSuggestions,
          ),
          const SizedBox(height: CockpitSpacing.sm),
          _Tile(
            onTap: () {},
            child: Row(
              children: [
                Expanded(
                  child: Text('Advanced AI Settings',
                      style: theme.textTheme.titleSmall),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _workspaceIcons = [
    Icons.keyboard_rounded,
    Icons.auto_fix_high_rounded,
    Icons.graphic_eq_rounded,
  ];
}

class _WorkspaceCard extends StatelessWidget {
  const _WorkspaceCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(CockpitRadii.md),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.sm,
          vertical: CockpitSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(CockpitRadii.md),
        ),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant),
                const SizedBox(height: CockpitSpacing.sm),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: selected ? scheme.primary : scheme.onSurface,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
            if (selected)
              Positioned(
                top: 0,
                right: 0,
                child: Icon(Icons.check_circle_rounded,
                    size: 16, color: scheme.primary),
              ),
          ],
        ),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.title,
    required this.value,
    required this.onChanged,
    this.icon,
  });
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _Tile(
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(width: CockpitSpacing.md),
          ],
          Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: scheme.primary,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Footer
// ---------------------------------------------------------------------------
class _Footer extends StatelessWidget {
  const _Footer({required this.workspaceLabel, required this.recording});
  final String workspaceLabel;
  final bool recording;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summary = [
      recording ? '$workspaceLabel + recording' : workspaceLabel,
      '1 material',
      'All devices synced',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded,
              size: 16, color: CockpitColors.brand.success),
          const SizedBox(width: CockpitSpacing.sm),
          Expanded(
            child: Text(
              summary,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: CockpitSpacing.md),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          FilledButton(
            onPressed: () {
              final router = GoRouter.of(context);
              Navigator.of(context).pop();
              router.go('/notes/session');
            },
            child: const Text('Start Session'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small shared pieces
// ---------------------------------------------------------------------------
class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Borderless: the column is grouped by its eyebrow + whitespace, not a box.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(title),
        const SizedBox(height: CockpitSpacing.lg),
        child,
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Boxless: a plain row on the modal surface — no fill, no border. Grouping
    // comes from whitespace; hover gives the only affordance.
    return InkWell(
      borderRadius: BorderRadius.circular(CockpitRadii.md),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.sm),
        child: child,
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(CockpitRadii.sm),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: CockpitSpacing.xs),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _TextInput extends StatelessWidget {
  const _TextInput({required this.hint});
  final String hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: TextEditingController(text: hint),
      decoration: InputDecoration(
        isDense: true,
        filled: false,
        contentPadding: const EdgeInsets.symmetric(vertical: CockpitSpacing.sm),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
    );
  }
}

class _SelectInput extends StatelessWidget {
  const _SelectInput({required this.value});
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Boxless underline field — no fill.
    return Container(
      padding: const EdgeInsets.only(bottom: CockpitSpacing.sm),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(child: Text(value, style: theme.textTheme.bodyLarge)),
          Icon(Icons.keyboard_arrow_down_rounded,
              color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }
}
