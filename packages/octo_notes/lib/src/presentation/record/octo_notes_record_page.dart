import 'dart:math' as math;

import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/octo_notes_theme.dart';

/// Width at/above which the recording companion uses the desktop two-column
/// layout. Mobile is the primary target — this screen is what the *recording
/// device* (a phone) shows — but PC gets a distributed hero + rail layout.
const double _kRecordDesktop = 1000;

/// OctoNotes — live recording companion (Screen 4).
///
/// This is the view on the device that is actually **recording** the lecture:
/// a big transport (timer · waveform · pause/stop), quick capture markers, the
/// most recent marker, and a live transcript peek. The paired note-taking
/// device (the MacBook) is shown as a connected source up top.
///
/// Mobile-first: a single scrolling column that matches the phone mock. On a
/// wide screen the same pieces redistribute into a recording hero (left) and a
/// capture + transcript rail (right), with Finish Session promoted to the
/// header. Dark theme by default; everything tracks the app brightness.
class OctoNotesRecordPage extends StatefulWidget {
  const OctoNotesRecordPage({super.key});

  @override
  State<OctoNotesRecordPage> createState() => _OctoNotesRecordPageState();
}

class _OctoNotesRecordPageState extends State<OctoNotesRecordPage> {
  bool _paused = false;
  bool _followLive = true;

  void _togglePause() => setState(() => _paused = !_paused);
  void _end() => context.canPop() ? context.pop() : context.go('/notes');

  @override
  Widget build(BuildContext context) {
    return OctoNotesTheme.wrap(
      context: context,
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          final desktop = MediaQuery.sizeOf(context).width >= _kRecordDesktop;
          return Scaffold(
            backgroundColor: scheme.surface,
            body: SafeArea(
              child: desktop ? _buildDesktop(context) : _buildMobile(context),
            ),
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Mobile — the primary layout. One scrolling column.
  // -------------------------------------------------------------------------
  Widget _buildMobile(BuildContext context) {
    return Column(
      children: [
        _HeaderBar(desktop: false, onBack: _end, onFinish: _end),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              CockpitSpacing.lg,
              CockpitSpacing.sm,
              CockpitSpacing.lg,
              CockpitSpacing.lg,
            ),
            children: [
              const _DeviceBar(),
              const SizedBox(height: CockpitSpacing.md),
              _RecordingPanel(
                paused: _paused,
                onPause: _togglePause,
                onStop: _end,
              ),
              const SizedBox(height: CockpitSpacing.md),
              const _QuickCaptureCard(),
              const SizedBox(height: CockpitSpacing.md),
              const _RecentMarkerCard(),
              const SizedBox(height: CockpitSpacing.md),
              _LiveTranscriptCard(
                followLive: _followLive,
                onToggleFollow: () =>
                    setState(() => _followLive = !_followLive),
              ),
              const SizedBox(height: CockpitSpacing.md),
              SizedBox(
                width: double.infinity,
                child: _FinishButton(onPressed: _end),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Desktop — recording hero (left) + capture/transcript rail (right).
  // -------------------------------------------------------------------------
  Widget _buildDesktop(BuildContext context) {
    return Column(
      children: [
        _HeaderBar(desktop: true, onBack: _end, onFinish: _end),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              CockpitSpacing.xxl,
              CockpitSpacing.lg,
              CockpitSpacing.xxl,
              CockpitSpacing.xxl,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1240),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        children: [
                          const _DeviceBar(),
                          const SizedBox(height: CockpitSpacing.lg),
                          _RecordingPanel(
                            paused: _paused,
                            onPause: _togglePause,
                            onStop: _end,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: CockpitSpacing.xl),
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                          const _QuickCaptureCard(),
                          const SizedBox(height: CockpitSpacing.lg),
                          const _RecentMarkerCard(),
                          const SizedBox(height: CockpitSpacing.lg),
                          _LiveTranscriptCard(
                            followLive: _followLive,
                            onToggleFollow: () =>
                                setState(() => _followLive = !_followLive),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------
class _HeaderBar extends StatelessWidget {
  const _HeaderBar({
    required this.desktop,
    required this.onBack,
    required this.onFinish,
  });
  final bool desktop;
  final VoidCallback onBack;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Cellular Respiration Lecture',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis),
        Text('Biology 101 • Week 4',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
            overflow: TextOverflow.ellipsis),
      ],
    );

    final menu = _OverflowMenu();

    return Container(
      padding: EdgeInsets.fromLTRB(
        desktop ? CockpitSpacing.xxl : CockpitSpacing.sm,
        CockpitSpacing.sm,
        desktop ? CockpitSpacing.xxl : CockpitSpacing.sm,
        CockpitSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: onBack,
          ),
          const SizedBox(width: CockpitSpacing.xs),
          Flexible(child: titleBlock),
          const SizedBox(width: CockpitSpacing.md),
          const _LiveBadge(),
          if (desktop) ...[
            const Spacer(),
            _FinishButton(onPressed: onFinish),
            const SizedBox(width: CockpitSpacing.xs),
            menu,
          ] else ...[
            const Spacer(),
            menu,
          ],
        ],
      ),
    );
  }
}

class _OverflowMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (_) {},
      itemBuilder: (context) => const [
        PopupMenuItem(value: 0, child: Text('Recording settings')),
        PopupMenuItem(value: 1, child: Text('Switch source device')),
        PopupMenuItem(value: 2, child: Text('Audio quality')),
      ],
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CockpitSpacing.md,
        vertical: CockpitSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, size: 8, color: Colors.white),
          const SizedBox(width: CockpitSpacing.xs),
          Text('LIVE',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  )),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Connected note-taking device
// ---------------------------------------------------------------------------
class _DeviceBar extends StatelessWidget {
  const _DeviceBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _Card(
      padding: const EdgeInsets.symmetric(
        horizontal: CockpitSpacing.lg,
        vertical: CockpitSpacing.md,
      ),
      child: Row(
        children: [
          Icon(Icons.laptop_mac_rounded, size: 20, color: scheme.onSurface),
          const SizedBox(width: CockpitSpacing.md),
          Flexible(
            child: Text.rich(
              TextSpan(
                style: theme.textTheme.bodyMedium,
                children: [
                  TextSpan(
                    text: 'MacBook Pro',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  TextSpan(
                    text: ' — Typewriter active',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: CockpitSpacing.md),
          Icon(Icons.circle, size: 8, color: CockpitColors.brand.success),
          const SizedBox(width: CockpitSpacing.xs),
          Text('Connected',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: CockpitColors.brand.success)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recording hero (timer · waveform · transport)
// ---------------------------------------------------------------------------
class _RecordingPanel extends StatelessWidget {
  const _RecordingPanel({
    required this.paused,
    required this.onPause,
    required this.onStop,
  });
  final bool paused;
  final VoidCallback onPause;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _Card(
      padding: const EdgeInsets.symmetric(
        horizontal: CockpitSpacing.lg,
        vertical: CockpitSpacing.xxl,
      ),
      child: Column(
        children: [
          Text(
            '42:16',
            style: theme.textTheme.displayMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 60,
              height: 1,
              letterSpacing: -1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Text(
            paused ? 'Paused — this iPhone' : 'Recording on this iPhone',
            style: theme.textTheme.titleSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: CockpitSpacing.xl),
          _Waveform(dimmed: paused),
          const SizedBox(height: CockpitSpacing.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.mic_rounded, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: CockpitSpacing.xs),
              Text('iPhone Microphone',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_rounded,
                  size: 16, color: CockpitColors.brand.success),
              const SizedBox(width: CockpitSpacing.sm),
              Text('Saved locally • Live Sync',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: CockpitSpacing.xxl),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _TransportButton(
                icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                label: paused ? 'Resume' : 'Pause',
                filled: true,
                onTap: onPause,
              ),
              const SizedBox(width: CockpitSpacing.xxl),
              _TransportButton(
                icon: Icons.stop_rounded,
                label: 'Stop',
                filled: false,
                onTap: onStop,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A big round transport control with a caption underneath. [filled] renders a
/// solid red disc (Pause/Resume); otherwise a red ring around a red glyph
/// (Stop).
class _TransportButton extends StatelessWidget {
  const _TransportButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  static const double _size = 72;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: filled ? scheme.primary : Colors.transparent,
          shape: CircleBorder(
            side: filled
                ? const BorderSide(color: Colors.black, width: 1)
                : BorderSide(color: scheme.primary, width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: _size,
              height: _size,
              child: Icon(
                icon,
                size: 32,
                color: filled ? Colors.white : scheme.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: CockpitSpacing.sm),
        Text(label, style: theme.textTheme.titleSmall),
      ],
    );
  }
}

/// A responsive faux audio waveform: irregular red bars that fill the width.
class _Waveform extends StatelessWidget {
  const _Waveform({required this.dimmed});
  final bool dimmed;

  static const int _bars = 56;
  static const double _maxHeight = 56;

  double _amplitude(int i) {
    // Two out-of-phase sine waves make an irregular, audio-like envelope.
    final v = (math.sin(i * 0.9) * 0.5 + math.sin(i * 0.37 + 1.3) * 0.5).abs();
    return 0.12 + 0.88 * v;
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context)
        .colorScheme
        .primary
        .withValues(alpha: dimmed ? 0.28 : 0.9);
    return SizedBox(
      height: _maxHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < _bars; i++)
            Expanded(
              child: Center(
                child: Container(
                  width: 2.5,
                  height: math.max(2, _amplitude(i) * _maxHeight),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(CockpitRadii.pill),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick Capture
// ---------------------------------------------------------------------------
class _QuickCaptureCard extends StatelessWidget {
  const _QuickCaptureCard();

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.star_outline_rounded, 'Important'),
      (Icons.help_outline_rounded, 'Question'),
      (Icons.photo_camera_outlined, 'Board Photo'),
      (Icons.sticky_note_2_outlined, 'Quick Note'),
    ];
    return _SectionCard(
      title: 'Quick Capture',
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            Expanded(
              child: _CaptureButton(icon: items[i].$1, label: items[i].$2),
            ),
            if (i != items.length - 1) const SizedBox(width: CockpitSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _CaptureButton extends StatelessWidget {
  const _CaptureButton({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(CockpitRadii.md),
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.xs,
          vertical: CockpitSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(CockpitRadii.md),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          children: [
            Icon(icon, size: 24, color: scheme.onSurface),
            const SizedBox(height: CockpitSpacing.sm),
            SizedBox(
              height: 32,
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium,
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
// Recent Marker
// ---------------------------------------------------------------------------
class _RecentMarkerCard extends StatelessWidget {
  const _RecentMarkerCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _SectionCard(
      title: 'Recent Marker',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _TimePill('18:32'),
              const SizedBox(width: CockpitSpacing.sm),
              TagChip(label: 'Exam Hint', color: scheme.primary),
              const Spacer(),
              _SquareIconButton(
                icon: Icons.edit_outlined,
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.md),
          Text(
            'Professor said this process will be on the midterm.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _TimePill extends StatelessWidget {
  const _TimePill(this.time);
  final String time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CockpitSpacing.md,
        vertical: CockpitSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(CockpitRadii.sm),
      ),
      child: Text(
        time,
        style: theme.textTheme.labelMedium?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SquareIconButton extends StatelessWidget {
  const _SquareIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(CockpitRadii.sm),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(CockpitSpacing.sm),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(CockpitRadii.sm),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Icon(icon, size: 18, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Live Transcript peek
// ---------------------------------------------------------------------------
class _LiveTranscriptCard extends StatelessWidget {
  const _LiveTranscriptCard({
    required this.followLive,
    required this.onToggleFollow,
  });
  final bool followLive;
  final VoidCallback onToggleFollow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _SectionCard(
      title: 'Live Transcript',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FollowLiveChip(following: followLive, onTap: onToggleFollow),
          const SizedBox(width: CockpitSpacing.sm),
          TextButton.icon(
            onPressed: () {},
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: CockpitSpacing.sm,
              ),
              foregroundColor: scheme.onSurface,
            ),
            icon: const Text('Expand'),
            label: const Icon(Icons.open_in_new_rounded, size: 15),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _TxRow(time: '18:25', text: 'Glycolysis occurs in the cytoplasm.'),
          _txDivider(scheme),
          const _TxRow(
              time: '18:32', text: 'The net result is two ATP and two NADH.'),
          _txDivider(scheme),
          const _TxRow(
            time: '18:44',
            text: 'Pyruvate enters the mitochondria next.',
            active: true,
          ),
          const SizedBox(height: CockpitSpacing.md),
          Row(
            children: [
              Icon(Icons.podcasts_rounded,
                  size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: CockpitSpacing.xs),
              Text('Stable transcript • Audio linked',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _txDivider(ColorScheme scheme) =>
      Divider(height: 1, color: scheme.outlineVariant);
}

class _FollowLiveChip extends StatelessWidget {
  const _FollowLiveChip({required this.following, required this.onTap});
  final bool following;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dot = following ? scheme.primary : scheme.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.xs,
          vertical: CockpitSpacing.xxs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 8, color: dot),
            const SizedBox(width: CockpitSpacing.xs),
            Text(following ? 'Following Live' : 'Paused scroll',
                style: theme.textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

class _TxRow extends StatelessWidget {
  const _TxRow({required this.time, required this.text, this.active = false});
  final String time;
  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CockpitSpacing.sm,
        vertical: CockpitSpacing.md,
      ),
      decoration: BoxDecoration(
        color: active ? scheme.primary.withValues(alpha: 0.06) : null,
        border: active
            ? Border(left: BorderSide(color: scheme.primary, width: 3))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(time,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: active ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: active ? FontWeight.w700 : null,
                )),
          ),
          const SizedBox(width: CockpitSpacing.md),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Finish Session
// ---------------------------------------------------------------------------
class _FinishButton extends StatelessWidget {
  const _FinishButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.primary,
        side: BorderSide(color: scheme.primary),
        padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.xl,
          vertical: CockpitSpacing.md,
        ),
      ),
      onPressed: onPressed,
      child: const Text('Finish Session'),
    );
  }
}

// ---------------------------------------------------------------------------
// Small shared pieces
// ---------------------------------------------------------------------------

/// Bordered surface matching the app card treatment, but with a configurable
/// pad (used for the slim device bar and the padded section cards).
class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding ?? const EdgeInsets.all(CockpitSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: child,
    );
  }
}

/// A titled section card: bold title (with optional trailing action) over its
/// body content.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
  });
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: CockpitSpacing.lg),
          child,
        ],
      ),
    );
  }
}
