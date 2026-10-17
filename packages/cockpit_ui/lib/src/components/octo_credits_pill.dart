import 'package:flutter/material.dart';

import '../theme/borderless_theme.dart';

/// The OctoCredits coin (`assets/images/octocredits.png`, 1x/2x/3x).
class OctoCreditsCoin extends StatelessWidget {
  const OctoCreditsCoin({super.key, this.size = 28, this.large = false});

  final double size;

  /// The 512 px picture, for big uses.
  final bool large;

  @override
  Widget build(BuildContext context) => Image.asset(
    large
        ? 'assets/images/octocredits_large.png'
        : 'assets/images/octocredits.png',
    package: 'cockpit_ui',
    width: size,
    height: size,
    filterQuality: FilterQuality.medium,
    excludeFromSemantics: true,
  );
}

/// The OctoCredits balance as a pill: coin, number counting up to the
/// balance, a red edge and a light sweeping across now and then. The same
/// pill the Study Studio header shows, for every module.
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

  static String format(int value) {
    final digits = value.abs().toString();
    final out = StringBuffer(value < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const radius = BorderRadius.all(Radius.circular(999));
    final pill = Container(
      height: 32,
      padding: const EdgeInsets.all(1),
      decoration: const BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x99FF2A47), Color(0x22FF2A47), Color(0x668A0F22)],
        ),
      ),
      child: AnimatedBuilder(
        animation: _shine,
        builder: (context, child) {
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
            decoration: BoxDecoration(
              borderRadius: radius,
              color: dark ? const Color(0xFF140A0D) : const Color(0xFFFFF0F2),
            ),
            padding: const EdgeInsets.only(left: 2, right: 11),
            child: child,
          );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const OctoCreditsCoin(size: 30),
            const SizedBox(width: 6),
            TweenAnimationBuilder<double>(
              tween: Tween(end: widget.credits.toDouble()),
              duration: const Duration(milliseconds: 1100),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => Text(
                format(value.round()),
                style: TextStyle(
                  fontFamily: BorderlessTheme.font,
                  color: dark
                      ? const Color(0xFFFFC7D0)
                      : const Color(0xFF8A0F22),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      label: '${widget.credits} OctoCredits',
      button: widget.onTap != null,
      child: widget.onTap == null
          ? pill
          : GestureDetector(onTap: widget.onTap, child: pill),
    );
  }
}
