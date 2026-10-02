import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'mobile_motion.dart';
import 'mobile_theme.dart';

/// The top-right corner of the chat: **Sources** once the sources are in,
/// and **Open Editor** under it once writing starts. Each fades and slides in
/// the moment it becomes available.
class GwCornerPills extends StatelessWidget {
  const GwCornerPills({
    super.key,
    required this.sourceCount,
    required this.onSources,
    required this.showEditor,
    required this.writing,
    required this.onEditor,
  });

  /// Null hides the Sources pill.
  final int? sourceCount;
  final VoidCallback onSources;
  final bool showEditor;

  /// The agent is writing right now: the editor pill shows a live dot.
  final bool writing;
  final VoidCallback onEditor;

  @override
  Widget build(BuildContext context) {
    final sources = sourceCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Arrive(
          visible: sources != null,
          child: _Pill(
            key: const ValueKey('sources-pill'),
            icon: Icons.public_rounded,
            label: sources == null || sources == 0
                ? 'Sources'
                : 'Sources · $sources',
            onTap: onSources,
          ),
        ),
        _Arrive(
          visible: showEditor,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _Pill(
              key: const ValueKey('editor-pill'),
              icon: Icons.edit_note_rounded,
              label: 'Open Editor',
              accent: true,
              live: writing,
              onTap: onEditor,
            ),
          ),
        ),
      ],
    );
  }
}

/// Fades and slides its child in from the right when [visible] turns true.
class _Arrive extends StatelessWidget {
  const _Arrive({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final duration = Duration(milliseconds: reduce ? 0 : 520);
    return AnimatedSize(
      duration: duration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topRight,
      child: !visible
          ? const SizedBox.shrink()
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: duration,
              curve: Curves.easeOutCubic,
              child: child,
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(24 * (1 - t), 0),
                  child: child,
                ),
              ),
            ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
    this.live = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool accent;
  final bool live;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(999));
    return GwPressable(
      tooltip: label,
      pressedScale: 0.92,
      onTap: onTap,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              height: 36,
              padding: const EdgeInsets.only(left: 11, right: 14),
              decoration: BoxDecoration(
                borderRadius: radius,
                color: accent
                    ? const Color(0xCC2A1416)
                    : const Color(0x24FFFFFF),
                border: Border.all(
                  color: accent
                      ? const Color(0xFF7A2D31)
                      : const Color(0x26FFFFFF),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 17,
                    color: accent ? GwColors.accentSoft : Colors.white,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (live) ...[const SizedBox(width: 8), const _LiveDot()],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small red dot that pulses while the essay is being written.
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Writing now',
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) => Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: GwColors.accent,
            boxShadow: [
              BoxShadow(
                color: GwColors.accent.withValues(alpha: 0.7 * _pulse.value),
                blurRadius: 8 * _pulse.value,
                spreadRadius: 1.5 * _pulse.value,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
