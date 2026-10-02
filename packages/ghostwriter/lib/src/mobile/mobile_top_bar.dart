import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'mobile_motion.dart';
import 'mobile_theme.dart';

/// Phone top bar: menu (opens the threads drawer), title, save (once there
/// is a draft) and the OctoCredits balance.
class GhostWriterMobileTopBar extends StatelessWidget {
  const GhostWriterMobileTopBar({
    super.key,
    required this.credits,
    required this.saving,
    this.onSave,
  });

  final int credits;
  final bool saving;

  /// Null hides the save button (nothing to save on the landing screen).
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final onSave = this.onSave;

    const radius = BorderRadius.all(Radius.circular(27));

    // A frosted capsule that floats over the dot background.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 22,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: 54,
              padding: const EdgeInsets.only(left: 5, right: 9),
              decoration: BoxDecoration(
                borderRadius: radius,
                color: const Color(0x0FFFFFFF),
                border: Border.all(color: const Color(0x1AFFFFFF)),
              ),
              child: Row(
                children: [
                  GwPressable(
                    tooltip: 'Threads',
                    onTap: () => Scaffold.of(context).openDrawer(),
                    child: Container(
                      width: kGwButton,
                      height: kGwButton,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0x14FFFFFF),
                      ),
                      child: const Center(child: _MenuGlyph()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Image.asset(GwAssets.ghost, width: 28, height: 28),
                  const SizedBox(width: 7),
                  const Expanded(child: GwWordmark(fontSize: 17)),
                  if (onSave != null)
                    GwPressable(
                      tooltip: saving ? 'Saving...' : 'Save',
                      onTap: saving ? null : onSave,
                      child: SizedBox(
                        width: kGwButton,
                        height: kGwButton,
                        child: Icon(
                          saving
                              ? Icons.hourglass_top_rounded
                              : Icons.save_outlined,
                          color: Colors.white70,
                          size: 21,
                        ),
                      ),
                    ),
                  OctoCreditsPill(credits: credits),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "GhostWriter" with the second half in the accent red.
class GwWordmark extends StatelessWidget {
  const GwWordmark({super.key, required this.fontSize});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      const TextSpan(
        text: 'Ghost',
        children: [
          TextSpan(
            text: 'Writer',
            style: TextStyle(color: GwColors.accentSoft),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
    );
  }
}

/// Two uneven bars, in the style of the ChatGPT menu icon.
class _MenuGlyph extends StatelessWidget {
  const _MenuGlyph();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width) => Container(
      width: width,
      height: 2,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(2),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [bar(18), const SizedBox(height: 5), bar(11)],
    );
  }
}

/// OctoCredits balance: gold coin, counting number and a slow shine sweep.
class OctoCreditsPill extends StatefulWidget {
  const OctoCreditsPill({super.key, required this.credits, this.onTap});

  final int credits;
  final VoidCallback? onTap;

  @override
  State<OctoCreditsPill> createState() => _OctoCreditsPillState();
}

class _OctoCreditsPillState extends State<OctoCreditsPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _shine.stop();
    } else if (!_shine.isAnimating) {
      _shine.repeat();
    }
  }

  @override
  void dispose() {
    _shine.dispose();
    super.dispose();
  }

  static String _format(int value) {
    final digits = value.toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(999));

    return Semantics(
      label: '${widget.credits} OctoCredits',
      child: GwPressable(
        tooltip: 'OctoCredits',
        haptic: GwHaptic.selection,
        pressedScale: 0.93,
        onTap: widget.onTap ?? () {},
        child: Container(
          height: 34,
          padding: const EdgeInsets.all(1),
          decoration: const BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0x99FFC53D), Color(0x22FFC53D), Color(0x66FF8A00)],
            ),
          ),
          child: AnimatedBuilder(
            animation: _shine,
            builder: (context, child) {
              // The shine crosses the pill in the first third of each loop.
              final t = (_shine.value * 3).clamp(0.0, 1.0);
              final x = -2.2 + 4.4 * t;

              return Container(
                foregroundDecoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: LinearGradient(
                    begin: Alignment(x - 0.6, -1),
                    end: Alignment(x + 0.6, 1),
                    colors: const [
                      Color(0x00FFFFFF),
                      Color(0x26FFFFFF),
                      Color(0x00FFFFFF),
                    ],
                  ),
                ),
                decoration: const BoxDecoration(
                  borderRadius: radius,
                  color: Color(0xFF141210),
                ),
                padding: const EdgeInsets.only(left: 5, right: 12),
                child: child,
              );
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _Coin(),
                const SizedBox(width: 7),
                ExcludeSemantics(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: widget.credits.toDouble()),
                    duration: const Duration(milliseconds: 1100),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => Text(
                      _format(value.round()),
                      style: const TextStyle(
                        color: Color(0xFFFFE9B0),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.1,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
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

class _Coin extends StatelessWidget {
  const _Coin();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE082), GwColors.gold, Color(0xFFFF8A00)],
        ),
        boxShadow: [BoxShadow(color: Color(0x55FFB300), blurRadius: 8)],
      ),
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF5A3A00), width: 2.2),
        ),
      ),
    );
  }
}
