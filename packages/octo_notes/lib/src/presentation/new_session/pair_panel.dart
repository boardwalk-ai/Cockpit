import 'dart:async';

import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../application/session_providers.dart';
import '../../application/this_device.dart';
import '../../domain/pairing.dart';
import 'pairing_widgets.dart';

/// Pairing a phone as the session's recorder: this device (the receiver)
/// shows the 6-digit code or a QR; the phone types or scans it. Shows who
/// paired. Used by the phone's New session sheet and the desktop modal.
class PairPanel extends ConsumerStatefulWidget {
  const PairPanel({super.key, required this.onChanged, required this.onPaired, this.qrFirst = false});

  final ValueChanged<Pairing?> onChanged;
  final VoidCallback onPaired;

  /// Start on the QR (a PC: the phone scans it).
  final bool qrFirst;

  @override
  ConsumerState<PairPanel> createState() => _PairPanelState();
}

class _PairPanelState extends ConsumerState<PairPanel> {
  Pairing? _p;
  String? _error;
  bool _qr = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _qr = widget.qrFirst;
    _create();
  }

  Future<void> _create() async {
    final api = ref.read(octoNotesApiProvider);
    if (api == null) {
      setState(() => _error = 'Pairing needs the OctoNotes server. Sign in first.');
      return;
    }
    setState(() => _error = null);
    try {
      final device = await ref.read(thisDeviceProvider.future);
      final p = await api.createPairing(device.id);
      if (!mounted) return;
      setState(() => _p = p);
      widget.onChanged(p);
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Could not make a code: $e');
    }
  }

  Future<void> _refresh() async {
    final p = _p;
    final api = ref.read(octoNotesApiProvider);
    if (p == null || api == null) return;
    try {
      final now = await api.pairing(p.id);
      if (!mounted) return;
      // The receiver keeps its secret (the phone never gets it back).
      final merged = Pairing(
        id: now.id,
        status: now.status,
        code: now.code,
        secret: p.secret,
        receiverName: now.receiverName,
        recorderName: now.recorderName,
        recorderPlatform: now.recorderPlatform,
        sessionId: now.sessionId,
        expiresAt: now.expiresAt,
      );
      final wasPaired = p.isPaired;
      setState(() => _p = merged);
      widget.onChanged(merged);
      if (merged.isPaired && !wasPaired) {
        unawaited(PairHaptics.success());
        widget.onPaired();
      }
      if (merged.isOver || merged.isStarted) _poll?.cancel();
    } on Object {
      // A missed poll; the next one tries again.
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final box = BoxDecoration(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
    );
    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(CockpitSpacing.md),
        decoration: box,
        child: Row(
          children: [
            Expanded(child: Text(_error!, style: theme.textTheme.bodyMedium)),
            TextButton(onPressed: _create, child: const Text('Try again')),
          ],
        ),
      );
    }
    final p = _p;
    final Widget body;
    if (p == null) {
      body = const SizedBox(key: ValueKey('loading'), height: 220, child: Center(child: CircularProgressIndicator()));
    } else if (p.isPaired) {
      body = Column(
        key: const ValueKey('paired'),
        children: [
          const SuccessCheck(size: 70),
          Text('Paired', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: CockpitSpacing.md),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutBack,
            builder: (_, t, child) =>
                Opacity(opacity: t.clamp(0.0, 1.0), child: Transform.translate(offset: Offset(0, (1 - t) * 16), child: child)),
            child: Container(
              padding: const EdgeInsets.all(CockpitSpacing.sm),
              decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(11)),
                    child: const Icon(Icons.smartphone_rounded, size: 20),
                  ),
                  const SizedBox(width: CockpitSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.recorderName ?? 'Your phone', style: theme.textTheme.titleSmall),
                        Text('${_platform(p.recorderPlatform)} · same account',
                            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Icon(Icons.link_rounded, color: CockpitColors.brand.success),
                ],
              ),
            ),
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Text('It starts recording when you start the session.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      );
    } else if (p.isOver) {
      body = Row(
        key: const ValueKey('over'),
        children: [
          Expanded(child: Text('That code expired.', style: theme.textTheme.bodyMedium)),
          FilledButton.tonal(onPressed: _create, child: const Text('New code')),
        ],
      );
    } else {
      body = Column(
        key: const ValueKey('waiting'),
        children: [
          PairSegment(
            labels: const ['Pairing code', 'QR code'],
            icons: const [Icons.pin_outlined, Icons.qr_code_2_rounded],
            index: _qr ? 1 : 0,
            onChanged: (i) => setState(() => _qr = i == 1),
          ),
          RadarRings(
            size: 220,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              transitionBuilder: (child, a) => ScaleTransition(
                scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
                child: FadeTransition(opacity: a, child: child),
              ),
              child: _qr
                  ? Container(
                      key: const ValueKey('qr'),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 30, offset: Offset(0, 10))],
                      ),
                      child: QrImageView(
                        data: p.qrText,
                        size: 160,
                        backgroundColor: Colors.white,
                        eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: scheme.primary),
                        dataModuleStyle:
                            const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: Color(0xFF111111)),
                        semanticsLabel: 'Pairing QR code',
                      ),
                    )
                  : Column(
                      key: const ValueKey('code'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RollingCode(code: p.code),
                        TextButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: p.code));
                            PairHaptics.select();
                          },
                          icon: const Icon(Icons.copy_rounded, size: 14),
                          label: const Text('Copy'),
                        ),
                      ],
                    ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Waiting for your phone', style: theme.textTheme.labelLarge),
              const SizedBox(width: CockpitSpacing.sm),
              CountdownRing(expiresAt: p.expiresAt),
            ],
          ),
          const SizedBox(height: CockpitSpacing.xs),
          Text(
            _qr
                ? 'On your phone: OctoNotes → Join as recorder → Scan QR'
                : 'On your phone: OctoNotes → Join as recorder, then type this code',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      );
    }
    return AnimatedSize(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      child: Container(
        padding: const EdgeInsets.all(CockpitSpacing.md),
        decoration: box,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: ScaleTransition(scale: Tween(begin: 0.95, end: 1.0).animate(a), child: child),
          ),
          child: body,
        ),
      ),
    );
  }

  static String _platform(String? p) => switch (p) {
        'android' => 'Android',
        'ios' => 'iPhone',
        _ => 'Phone',
      };
}
