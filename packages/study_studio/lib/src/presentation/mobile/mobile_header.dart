import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import 'credits_store_mobile.dart';
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
/// title), the OctoCredits and the profile button — on every page.
class SmHeader extends StatelessWidget {
  const SmHeader({
    super.key,
    this.home = false,
    this.title,
    this.credits,
    this.trailing,
    this.onBack,
  });

  /// The leading button goes to the app's home instead of back.
  final bool home;

  /// Replaces what the leading button does.
  final VoidCallback? onBack;

  /// Shown instead of the wordmark.
  final String? title;
  final int? credits;

  /// After the credits, before the profile button.
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
                    onTap:
                        onBack ??
                        () => home || !context.canPop()
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
                  _Credits(credits: credits),
                  ?trailing,
                  const _Profile(),
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

/// Riverpod is there in the app; widget tests may pump a page without it.
bool _hasScope(BuildContext context) {
  try {
    ProviderScope.containerOf(context, listen: false);
    return true;
  } on Object {
    return false;
  }
}

/// The balance (from `/me` unless the page passes it); tap to buy more.
class _Credits extends StatelessWidget {
  const _Credits({this.credits});

  final int? credits;

  @override
  Widget build(BuildContext context) {
    if (!_hasScope(context)) {
      return credits == null
          ? const SizedBox.shrink()
          : SmCreditsPill(credits: credits!);
    }
    return Consumer(
      builder: (context, ref, _) {
        final n = credits ?? ref.watch(meProvider).valueOrNull?.credits;
        if (n == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(left: 8),
          child: SmPressable(
            semanticLabel: 'Get OctoCredits',
            haptic: SmHaptics.tap,
            onTap: () => showCreditsStore(context, ref),
            child: SmCreditsPill(credits: n),
          ),
        );
      },
    );
  }
}

/// The account: initials in a circle; opens the app's settings.
class _Profile extends StatelessWidget {
  const _Profile();

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    Widget avatar(String initials, String? photo) => Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.accent.withValues(alpha: 0.16),
        border: Border.all(color: c.accent.withValues(alpha: 0.35)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Text(
              initials,
              style: TextStyle(
                fontFamily: SmFonts.heading,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: c.accentSoft,
              ),
            ),
          ),
          // The photo over the initials; they show while it loads or if
          // it fails.
          if (photo != null)
            Image.network(
              photo,
              fit: BoxFit.cover,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
        ],
      ),
    );
    Widget button(String initials, String? photo) => Padding(
      padding: const EdgeInsets.only(left: 8),
      child: SmPressable(
        semanticLabel: 'Profile and settings',
        haptic: SmHaptics.tap,
        scale: 0.9,
        onTap: () => context.push('/settings'),
        child: avatar(initials, photo),
      ),
    );
    if (!_hasScope(context)) return button('?', null);
    return Consumer(
      builder: (context, ref, _) {
        final me = ref.watch(meProvider).valueOrNull;
        final profile = ref.watch(authServiceProvider).profile;
        return button(
          me?.initials ?? profile?.initials ?? '?',
          me?.photoUrl ?? profile?.photoUrl,
        );
      },
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
              padding: const EdgeInsets.only(left: 2, right: 12),
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
                          ? const Color(0xFFFFC7D0)
                          : const Color(0xFF8A0F22),
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
  Widget build(BuildContext context) => const OctoCreditsIcon(size: 32);
}

/// The OctoCredits mark: the neon octopus coin stack.
class OctoCreditsIcon extends StatelessWidget {
  const OctoCreditsIcon({super.key, this.size = 28, this.large = false});

  final double size;

  /// The 512 px picture, for big uses (the store sheet).
  final bool large;

  @override
  Widget build(BuildContext context) => Image.asset(
    large
        ? 'assets/images/octocredits_large.png'
        : 'assets/images/octocredits.png',
    package: 'study_studio',
    width: size,
    height: size,
    filterQuality: FilterQuality.medium,
    excludeFromSemantics: true,
  );
}
