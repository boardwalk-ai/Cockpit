import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'mobile_motion.dart';
import 'mobile_style.dart';

/// A phone page with GhostWriter's header: a frosted capsule floating over
/// the content, which scrolls up under it and fades into the background.
class SmHeaderPage extends StatelessWidget {
  const SmHeaderPage({super.key, required this.header, required this.child});

  final SmHeader header;

  /// The content; it should leave [SmHeader.clearance] free at its top.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final top = MediaQuery.paddingOf(context).top;
    return ColoredBox(
      color: c.background,
      child: Stack(
        children: [
          Positioned.fill(child: child),
          // The fade: content dissolves into the background under the bar.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: top + SmHeader.clearance,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, 0.55, 1],
                    colors: [
                      c.background,
                      c.background.withValues(alpha: 0.88),
                      c.background.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(top: top, left: 0, right: 0, child: header),
        ],
      ),
    );
  }
}

/// The floating bar: Home (or back), the Study Studio wordmark (or a
/// title), and the OctoCredits.
class SmHeader extends StatelessWidget {
  const SmHeader({
    super.key,
    this.home = false,
    this.title,
    this.credits,
    this.trailing,
  });

  /// The leading button goes to the app's home instead of back.
  final bool home;

  /// Shown instead of the wordmark.
  final String? title;
  final int? credits;

  /// After the credits (or in their place).
  final Widget? trailing;

  /// Room the content leaves at its top for the bar and its fade.
  static const clearance = 78.0;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    const radius = BorderRadius.all(Radius.circular(27));
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.25 : 0.08),
              blurRadius: 22,
              offset: const Offset(0, 8),
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
                color: dark
                    ? const Color(0x0FFFFFFF)
                    : Colors.white.withValues(alpha: 0.72),
                border: Border.all(
                  color: dark ? const Color(0x1AFFFFFF) : c.line,
                ),
              ),
              child: Row(
                children: [
                  SmPressable(
                    semanticLabel: home ? 'Home' : 'Back',
                    haptic: SmHaptics.tap,
                    scale: 0.9,
                    onTap: () => home || !context.canPop()
                        ? context.go('/')
                        : context.pop(),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dark
                            ? const Color(0x14FFFFFF)
                            : c.raised.withValues(alpha: 0.8),
                      ),
                      child: Icon(
                        home
                            ? Icons.home_outlined
                            : Icons.arrow_back_ios_new_rounded,
                        size: home ? 21 : 17,
                        color: c.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: title != null
                        ? Text(
                            title!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SmText.of(context).title,
                          )
                        : const _Wordmark(),
                  ),
                  if (credits != null) SmCreditsPill(credits: credits!),
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ✦ Study Studio, the second word in the accent.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    return Row(
      children: [
        Icon(Icons.auto_awesome_rounded, size: 20, color: c.accent),
        const SizedBox(width: 7),
        Flexible(
          child: Text.rich(
            TextSpan(
              text: 'Study',
              children: [
                TextSpan(
                  text: 'Studio',
                  style: TextStyle(color: c.accentSoft),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: SmFonts.heading,
              color: c.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
        ),
      ],
    );
  }
}

/// GhostWriter's OctoCredits pill: a gold coin, the balance counting up,
/// a shine crossing now and then.
class SmCreditsPill extends StatefulWidget {
  const SmCreditsPill({super.key, required this.credits});

  final int credits;

  @override
  State<SmCreditsPill> createState() => _SmCreditsPillState();
}

class _SmCreditsPillState extends State<SmCreditsPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (smReduceMotion(context)) {
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    const radius = BorderRadius.all(Radius.circular(999));
    return Semantics(
      label: '${widget.credits} OctoCredits',
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
                color: dark ? const Color(0xFF141210) : const Color(0xFFFFF8E6),
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
                    style: TextStyle(
                      fontFamily: SmFonts.heading,
                      color: dark
                          ? const Color(0xFFFFE9B0)
                          : const Color(0xFF7A4B00),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ],
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
          colors: [Color(0xFFFFE082), Color(0xFFFFC53D), Color(0xFFFF8A00)],
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
