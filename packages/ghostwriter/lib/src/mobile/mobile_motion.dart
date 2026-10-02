import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mobile_theme.dart';

enum GwHaptic { selection, light, medium }

void gwHaptic(GwHaptic haptic) {
  switch (haptic) {
    case GwHaptic.selection:
      HapticFeedback.selectionClick();
    case GwHaptic.light:
      HapticFeedback.lightImpact();
    case GwHaptic.medium:
      HapticFeedback.mediumImpact();
  }
}

/// Tap target that squashes on press, springs back on release and fires a
/// haptic tick. A null [onTap] disables it.
class GwPressable extends StatefulWidget {
  const GwPressable({
    super.key,
    required this.child,
    required this.onTap,
    this.tooltip,
    this.haptic = GwHaptic.light,
    this.pressedScale = 0.88,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;
  final GwHaptic haptic;
  final double pressedScale;

  @override
  State<GwPressable> createState() => _GwPressableState();
}

class _GwPressableState extends State<GwPressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    Widget result = Semantics(
      button: true,
      enabled: widget.onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap == null
            ? null
            : () {
                gwHaptic(widget.haptic);
                widget.onTap!();
              },
        child: AnimatedScale(
          scale: _pressed && !reduceMotion ? widget.pressedScale : 1,
          duration: Duration(milliseconds: _pressed ? 90 : 480),
          curve: _pressed ? Curves.easeOut : Curves.elasticOut,
          child: widget.child,
        ),
      ),
    );

    final tooltip = widget.tooltip;
    if (tooltip != null) {
      result = Tooltip(message: tooltip, child: result);
    }
    return result;
  }
}

/// Fades and slides [child] in during the [from]..[to] slice of [animation],
/// so one controller can stagger a whole screen.
class GwReveal extends StatelessWidget {
  const GwReveal({
    super.key,
    required this.animation,
    required this.from,
    required this.to,
    required this.child,
    this.offset = const Offset(0, 18),
    this.scaleFrom = 1,
  });

  final Animation<double> animation;
  final double from;
  final double to;
  final Widget child;
  final Offset offset;
  final double scaleFrom;

  @override
  Widget build(BuildContext context) {
    final interval = Interval(from, to, curve: Curves.easeOutCubic);

    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = interval.transform(animation.value);

        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: offset * (1 - t),
            child: Transform.scale(
              scale: scaleFrom + (1 - scaleFrom) * t,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Round icon button used in the composer.
class GwIconButton extends StatelessWidget {
  const GwIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return GwPressable(
      tooltip: tooltip,
      onTap: onTap,
      child: Container(
        width: kGwButton,
        height: kGwButton,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accent ? const Color(0xFF211012) : GwColors.chip,
          border: Border.all(
            color: accent ? const Color(0xFF7A2D31) : const Color(0xFF2A2C30),
          ),
        ),
        child: Icon(
          icon,
          size: 20,
          color: accent ? Colors.white : const Color(0xFFD7D7D9),
        ),
      ),
    );
  }
}
