import 'package:flutter/material.dart';

import 'mobile_background.dart';
import 'mobile_landing.dart';
import 'mobile_motion.dart';
import 'mobile_theme.dart';
import 'mobile_top_bar.dart';

/// Shown until the user signs in: the ghost, the wordmark and one button.
class GhostWriterSignIn extends StatefulWidget {
  const GhostWriterSignIn({super.key, required this.onSignIn});

  /// Runs the platform's Google sign-in.
  final Future<void> Function() onSignIn;

  @override
  State<GhostWriterSignIn> createState() => _GhostWriterSignInState();
}

class _GhostWriterSignInState extends State<GhostWriterSignIn>
    with TickerProviderStateMixin {
  late final AnimationController _entry = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  bool _busy = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _entry.value = 1;
      _ambient.stop();
    } else {
      if (_entry.status == AnimationStatus.dismissed) _entry.forward();
      if (!_ambient.isAnimating) _ambient.repeat();
    }
  }

  @override
  void dispose() {
    _entry.dispose();
    _ambient.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSignIn();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Sign-in did not go through. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GwColors.background,
      body: GwBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GwReveal(
                      animation: _entry,
                      from: 0,
                      to: 0.5,
                      scaleFrom: 0.85,
                      child: GwFloatingGhost(ambient: _ambient),
                    ),
                    const SizedBox(height: 22),
                    GwReveal(
                      animation: _entry,
                      from: 0.15,
                      to: 0.6,
                      child: const GwWordmark(fontSize: 30),
                    ),
                    const SizedBox(height: 8),
                    GwReveal(
                      animation: _entry,
                      from: 0.25,
                      to: 0.7,
                      child: Text(
                        'Draft fast. Revise cleanly.',
                        style: kGwBody.copyWith(color: GwColors.muted),
                      ),
                    ),
                    const SizedBox(height: 40),
                    GwReveal(
                      animation: _entry,
                      from: 0.4,
                      to: 0.9,
                      offset: const Offset(0, 28),
                      child: _GoogleButton(busy: _busy, onTap: _signIn),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 260),
                      child: _error == null
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: kGwBody.copyWith(
                                  fontSize: 13,
                                  color: const Color(0xFFFF9A9E),
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: 18),
                    GwReveal(
                      animation: _entry,
                      from: 0.55,
                      to: 1,
                      child: Text(
                        'Use the Google account you use on Octopilot.\n'
                        'Your OctoCredits come with it.',
                        textAlign: TextAlign.center,
                        style: kGwBody.copyWith(
                          fontSize: 12.5,
                          height: 1.5,
                          color: GwColors.hint,
                        ),
                      ),
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

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GwPressable(
      haptic: GwHaptic.medium,
      pressedScale: 0.96,
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 54,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: busy ? 0.85 : 1),
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF1C1D1F),
                ),
              )
            else
              const Text(
                'G',
                style: TextStyle(
                  color: Color(0xFF4285F4),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            const SizedBox(width: 12),
            Text(
              busy ? 'Signing in…' : 'Continue with Google',
              style: const TextStyle(
                color: Color(0xFF1C1D1F),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
