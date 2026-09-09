import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';

import '../../theme/octo_notes_theme.dart';
import '../widgets/octo_widgets.dart';

/// Panel 12 — Connected Devices & Sync (ON-P12).
///
/// A live-session control centre: which devices are connected, what each is
/// doing, which one is recording, and the state of every synced data stream.
/// Opened from the "Live Sync / All devices synced" indicator in the session
/// header. Borderless / Poppins design system; mock data for now.
Future<void> showConnectedDevicesDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.62),
    builder: (context) => OctoNotesTheme.wrap(
      context: context,
      child: const _ConnectedDevicesDialog(),
    ),
  );
}

// Role accent colours (device specialisation).
const _blue = Color(0xFF5B8DEF); // Active Editor
const _purple = Color(0xFF9B7EDE); // Magic Pencil

class _ConnectedDevicesDialog extends StatelessWidget {
  const _ConnectedDevicesDialog();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(CockpitSpacing.xl),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CockpitRadii.xl),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Header(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  CockpitSpacing.lg,
                  0,
                  CockpitSpacing.lg,
                  CockpitSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _SyncSummary(),
                    SizedBox(height: CockpitSpacing.lg),
                    _DeviceCard(
                      icon: Icons.smartphone_rounded,
                      name: "Hein's iPhone",
                      role: 'Recording Source',
                      roleColor: null, // brand red (resolved below)
                      detail: 'Microphone active · 42:16 · Audio upload · Live',
                      trailing: _Battery(pct: 68),
                    ),
                    SizedBox(height: CockpitSpacing.sm),
                    _DeviceCard(
                      icon: Icons.laptop_mac_rounded,
                      name: "Hein's MacBook Pro",
                      role: 'Active Editor',
                      roleColor: _blue,
                      detail: 'Typewriter open · Saved · Live Sync',
                    ),
                    SizedBox(height: CockpitSpacing.sm),
                    _DeviceCard(
                      icon: Icons.tablet_mac_rounded,
                      name: "Hein's iPad",
                      role: 'Magic Pencil',
                      roleColor: _purple,
                      detail: 'Original ink synced · Last sync · 5 sec ago',
                    ),
                    SizedBox(height: CockpitSpacing.xl),
                    Eyebrow('Session Sync'),
                    SizedBox(height: CockpitSpacing.md),
                    _StreamRow(
                      icon: Icons.mic_rounded,
                      label: 'Audio Recording',
                      status: 'Live',
                      live: true,
                    ),
                    _StreamRow(
                      icon: Icons.subtitles_outlined,
                      label: 'Live Transcript',
                      status: '3 sec behind',
                    ),
                    _StreamRow(
                      icon: Icons.description_outlined,
                      label: 'Typed Notes',
                      status: 'Synced',
                      synced: true,
                    ),
                    _StreamRow(
                      icon: Icons.gesture_rounded,
                      label: 'Magic Pencil Ink',
                      status: 'Synced',
                      synced: true,
                    ),
                    SizedBox(height: CockpitSpacing.xl),
                    _Actions(),
                    SizedBox(height: CockpitSpacing.md),
                    _PermissionNote(),
                    SizedBox(height: CockpitSpacing.md),
                    _FooterMicrocopy(),
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

// ---------------------------------------------------------------------------
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CockpitSpacing.lg,
        CockpitSpacing.lg,
        CockpitSpacing.sm,
        CockpitSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text('Connected Devices & Sync',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
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

class _SyncSummary extends StatelessWidget {
  const _SyncSummary();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_rounded,
                size: 18, color: CockpitColors.brand.success),
            const SizedBox(width: CockpitSpacing.sm),
            Text('All devices synced',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: CockpitColors.brand.success,
                  fontWeight: FontWeight.w700,
                )),
          ],
        ),
        const SizedBox(height: CockpitSpacing.xxs),
        Padding(
          padding: const EdgeInsets.only(left: 26),
          child: Text('3 devices connected · Last synced just now',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.icon,
    required this.name,
    required this.role,
    required this.roleColor,
    required this.detail,
    this.trailing,
  });

  final IconData icon;
  final String name;
  final String role;
  final Color? roleColor; // null → brand red (Recording Source)
  final String detail;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = roleColor ?? scheme.primary;
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(CockpitRadii.sm),
            ),
            child: Icon(icon, size: 20, color: scheme.onSurface),
          ),
          const SizedBox(width: CockpitSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(name,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall),
                    ),
                    const SizedBox(width: CockpitSpacing.sm),
                    Icon(Icons.circle,
                        size: 7, color: CockpitColors.brand.success),
                    const SizedBox(width: CockpitSpacing.xxs),
                    Text('Connected',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: CockpitColors.brand.success,
                        )),
                  ],
                ),
                const SizedBox(height: CockpitSpacing.xs),
                _RoleTag(label: role, color: accent),
                const SizedBox(height: CockpitSpacing.sm),
                Text(detail,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
              if (trailing != null) ...[
                const SizedBox(height: CockpitSpacing.sm),
                trailing!,
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleTag extends StatelessWidget {
  const _RoleTag({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CockpitSpacing.sm,
        vertical: CockpitSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
      ),
      child: Text(label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              )),
    );
  }
}

class _Battery extends StatelessWidget {
  const _Battery({required this.pct});
  final int pct;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.battery_5_bar_rounded,
            size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: CockpitSpacing.xxs),
        Text('$pct%', style: theme.textTheme.labelSmall),
      ],
    );
  }
}

class _StreamRow extends StatelessWidget {
  const _StreamRow({
    required this.icon,
    required this.label,
    required this.status,
    this.live = false,
    this.synced = false,
  });

  final IconData icon;
  final String label;
  final String status;
  final bool live;
  final bool synced;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColor = live
        ? scheme.primary
        : synced
            ? CockpitColors.brand.success
            : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: CockpitSpacing.md),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          if (live) ...[
            Icon(Icons.circle, size: 7, color: scheme.primary),
            const SizedBox(width: CockpitSpacing.xs),
          ] else if (synced) ...[
            Icon(Icons.check_circle_rounded,
                size: 15, color: CockpitColors.brand.success),
            const SizedBox(width: CockpitSpacing.xs),
          ],
          Text(status,
              style: theme.textTheme.labelMedium?.copyWith(color: statusColor)),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Connect Another Device'),
              ),
            ),
            const SizedBox(width: CockpitSpacing.sm),
            Expanded(
              child: OutlinedButton(
                onPressed: () {},
                child: const Text('Change Recording Source'),
              ),
            ),
          ],
        ),
        const SizedBox(height: CockpitSpacing.sm),
        TextButton(onPressed: () {}, child: const Text('View Sync Details')),
      ],
    );
  }
}

class _PermissionNote extends StatelessWidget {
  const _PermissionNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final green = CockpitColors.brand.success;
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.md),
      decoration: BoxDecoration(
        color: green.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(CockpitRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, size: 18, color: green),
          const SizedBox(width: CockpitSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Only Hein's iPhone microphone is active",
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: CockpitSpacing.xxs),
                Text('Recording permissions are visible and controlled by you.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterMicrocopy extends StatelessWidget {
  const _FooterMicrocopy();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text('One session · Originals preserved · Safe offline recovery',
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}
