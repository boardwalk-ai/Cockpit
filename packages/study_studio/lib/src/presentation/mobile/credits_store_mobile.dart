import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/providers.dart';
import '../../data/api/billing_api.dart';
import 'mobile_header.dart' show OctoCreditsIcon;
import 'mobile_motion.dart';
import 'mobile_style.dart';

/// Get OctoCredits: the packs, each opening Stripe Checkout in the browser.
/// Coming back to the app re-reads the balance (the webhook adds the
/// credits when the payment lands).
Future<void> showCreditsStore(BuildContext context, WidgetRef ref) {
  final c = SmColors.of(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.background,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => const _Store(),
  );
}

class _Store extends ConsumerStatefulWidget {
  const _Store();

  @override
  ConsumerState<_Store> createState() => _StoreState();
}

class _StoreState extends ConsumerState<_Store> {
  String? _opening;
  String? _error;

  Future<void> _buy(CreditPack pack) async {
    final billing = ref.read(billingProvider);
    if (billing == null || _opening != null) return;
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() {
      _opening = pack.key;
      _error = null;
    });
    try {
      final url = await billing.checkout(pack);
      // Re-read the balance when the student comes back from paying.
      late final AppLifecycleListener listener;
      listener = AppLifecycleListener(
        onResume: () {
          container.invalidate(meProvider);
          listener.dispose();
        },
      );
      final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!ok) throw Exception('no browser');
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      SmHaptics.error();
      if (!mounted) return;
      setState(() {
        _opening = null;
        _error = e is Exception && '$e'.contains('Sign in')
            ? 'Sign in to buy OctoCredits.'
            : 'Couldn’t open checkout. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final balance = ref.watch(meProvider).valueOrNull?.credits;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: OctoCreditsIcon(size: 120, large: true)),
            const SizedBox(height: 8),
            Text('Get OctoCredits', style: t.title),
            const SizedBox(height: 4),
            Text(
              balance == null
                  ? 'Ask AI, concept maps and studio builds use credits.'
                  : 'You have $balance. Ask AI, concept maps and studio '
                        'builds use credits.',
              style: t.small.copyWith(color: c.muted),
            ),
            const SizedBox(height: 16),
            for (final pack in creditPacks)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SmPressable(
                  semanticLabel: '${pack.credits} OctoCredits, ${pack.price}',
                  haptic: SmHaptics.tap,
                  onTap: () => _buy(pack),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: c.line),
                    ),
                    child: Row(
                      children: [
                        const OctoCreditsIcon(size: 26),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${pack.credits} credits',
                            style: t.body,
                          ),
                        ),
                        if (_opening == pack.key)
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: c.accent,
                            ),
                          )
                        else
                          Text(
                            pack.price,
                            style: t.body.copyWith(color: c.accentSoft),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: t.small.copyWith(color: c.accent)),
            ],
            const SizedBox(height: 6),
            Text(
              'Paid securely with Stripe. Credits arrive a few seconds '
              'after payment.',
              style: t.small.copyWith(fontSize: 12, color: c.hint),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
