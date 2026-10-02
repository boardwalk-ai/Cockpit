import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'mobile_motion.dart';
import 'mobile_theme.dart';

/// Frosted prompt box docked at the bottom of the phone UI. Its border turns
/// into a slowly rotating red light while the field has focus.
class GwComposer extends StatefulWidget {
  const GwComposer({
    super.key,
    required this.controller,
    required this.canSend,
    required this.onChanged,
    required this.onSend,
    this.hintText = 'Drop your brief',
    this.sendLabel = 'Start',
  });

  final TextEditingController controller;
  final bool canSend;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;
  final String hintText;
  final String sendLabel;

  @override
  State<GwComposer> createState() => _GwComposerState();
}

class _GwComposerState extends State<GwComposer> with TickerProviderStateMixin {
  final FocusNode _focus = FocusNode();

  /// 0 = resting border, 1 = fully lit.
  late final AnimationController _lit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  /// Rotates the light around the border while focused.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  );

  static const _outerRadius = BorderRadius.all(Radius.circular(30));
  static const _innerRadius = BorderRadius.all(Radius.circular(28.6));
  static const _ember = Color(0xFFFF8A5C);

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (_focus.hasFocus) {
      _lit.forward();
      if (!MediaQuery.disableAnimationsOf(context)) _spin.repeat();
    } else {
      _lit.reverse().whenComplete(() {
        if (mounted && !_focus.hasFocus) _spin.stop();
      });
    }
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocusChanged)
      ..dispose();
    _lit.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 640),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: AnimatedBuilder(
          animation: Listenable.merge([_lit, _spin]),
          builder: (context, child) {
            final lit = Curves.easeOutCubic.transform(_lit.value);
            Color glow(Color color) => Color.lerp(GwColors.border, color, lit)!;

            return DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: _outerRadius,
                gradient: SweepGradient(
                  transform: GradientRotation(_spin.value * 2 * math.pi),
                  colors: [
                    glow(GwColors.accent),
                    GwColors.border,
                    glow(_ember),
                    GwColors.border,
                    glow(GwColors.accent),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: GwColors.accent.withValues(alpha: 0.20 * lit),
                    blurRadius: 30,
                    spreadRadius: 1,
                  ),
                  const BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(padding: const EdgeInsets.all(1.4), child: child),
            );
          },
          child: ClipRRect(
            borderRadius: _innerRadius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                color: GwColors.panel.withValues(alpha: 0.86),
                padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: TextField(
                        controller: widget.controller,
                        focusNode: _focus,
                        onChanged: widget.onChanged,
                        minLines: 1,
                        maxLines: 6,
                        textCapitalization: TextCapitalization.sentences,
                        keyboardType: TextInputType.multiline,
                        cursorColor: GwColors.accent,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: GwFonts.secondary,
                          fontFamilyFallback: GwFonts.secondaryFallback,
                          fontSize: 16,
                          height: 1.4,
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                          hintText: widget.hintText,
                          hintStyle: const TextStyle(
                            color: GwColors.hint,
                            fontFamily: GwFonts.secondary,
                            fontFamilyFallback: GwFonts.secondaryFallback,
                            fontSize: 16,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        // TODO: wire up attachments, sources and voice input.
                        GwIconButton(
                          icon: Icons.add_rounded,
                          tooltip: 'Attach',
                          onTap: () {},
                        ),
                        const SizedBox(width: 6),
                        _SourcePill(compact: widget.canSend, onTap: () {}),
                        const Spacer(),
                        GwIconButton(
                          icon: Icons.mic_none_rounded,
                          tooltip: 'Voice',
                          onTap: () {},
                        ),
                        const SizedBox(width: 6),
                        _SendButton(
                          label: widget.sendLabel,
                          enabled: widget.canSend,
                          onTap: widget.onSend,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Globe + "Source". Folds down to just the globe when the send button
/// needs the room.
class _SourcePill extends StatelessWidget {
  const _SourcePill({required this.compact, required this.onTap});

  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GwPressable(
      tooltip: 'Source',
      onTap: onTap,
      child: Container(
        height: kGwButton,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF2A1416),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFF7A2D31)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language_rounded, size: 19, color: Colors.white),
            AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              child: compact
                  ? const SizedBox(height: 20)
                  : const Padding(
                      padding: EdgeInsets.only(left: 7),
                      child: Text(
                        'Source',
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grey arrow circle while there is nothing to send; grows into a glowing
/// red pill with a label once there is.
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  static const _duration = Duration(milliseconds: 280);

  @override
  Widget build(BuildContext context) {
    return GwPressable(
      key: const ValueKey('gw-start'),
      tooltip: label,
      haptic: GwHaptic.medium,
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: _duration,
        curve: Curves.easeOutCubic,
        height: kGwButton,
        padding: EdgeInsets.symmetric(horizontal: enabled ? 16 : 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: enabled
                ? const [Color(0xFFFF4A4F), Color(0xFFE8202A)]
                : const [Color(0xFF34363A), Color(0xFF2C2E31)],
          ),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: GwColors.accent.withValues(alpha: enabled ? 0.42 : 0),
              blurRadius: 22,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: _duration,
              curve: Curves.easeOutCubic,
              child: enabled
                  ? Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : const SizedBox(height: 20),
            ),
            AnimatedRotation(
              duration: _duration,
              curve: Curves.easeOutBack,
              // Arrow points up while idle and swings right when ready.
              turns: enabled ? 0 : -0.25,
              child: Icon(
                Icons.arrow_forward_rounded,
                size: 20,
                color: enabled ? Colors.white : GwColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
