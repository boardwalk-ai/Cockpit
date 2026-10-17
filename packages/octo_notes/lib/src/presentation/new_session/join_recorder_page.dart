import 'dart:async';

import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../application/session_providers.dart';
import '../../application/this_device.dart';
import '../../domain/pairing.dart';
import '../../theme/octo_notes_theme.dart';
import 'pairing_widgets.dart';

/// The recorder phone: type the 6-digit code on the pad or scan the QR your
/// other device shows, then wait; when that device starts the session, this
/// phone opens it as the recorder.
class JoinRecorderPage extends ConsumerStatefulWidget {
  const JoinRecorderPage({super.key});

  @override
  ConsumerState<JoinRecorderPage> createState() => _JoinRecorderPageState();
}

class _JoinRecorderPageState extends ConsumerState<JoinRecorderPage> {
  String _code = '';
  bool _scan = false;
  String? _error;
  bool _busy = false;
  CodeBoxesState _boxes = CodeBoxesState.typing;
  int _shake = 0;
  Pairing? _paired;
  Timer? _poll;

  Future<void> _claim({String? code, String? secret}) async {
    final api = ref.read(octoNotesApiProvider);
    if (api == null) {
      return _wrong('Joining needs the OctoNotes server. Sign in first.');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final device = await ref.read(thisDeviceProvider.future);
      final p = await api.claimPairing(code: code, secret: secret, deviceId: device.id);
      if (!mounted) return;
      setState(() => _boxes = CodeBoxesState.right);
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted) return;
      unawaited(PairHaptics.success());
      setState(() => _paired = p);
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _wait());
    } on Object catch (e) {
      if (mounted) await _wrong(_plain(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Red boxes, a shake and three buzzes, then empty boxes to try again.
  Future<void> _wrong(String message) async {
    unawaited(PairHaptics.error());
    setState(() {
      _error = message;
      _boxes = CodeBoxesState.wrong;
      _shake++;
    });
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) {
      setState(() {
        _boxes = CodeBoxesState.typing;
        _code = '';
      });
    }
  }

  /// The server's message without the client's prefix.
  static String _plain(Object e) {
    final s = '$e';
    final i = s.indexOf(': ');
    return i > 0 && i < 40 ? s.substring(i + 2) : s;
  }

  Future<void> _wait() async {
    final p = _paired;
    final api = ref.read(octoNotesApiProvider);
    if (p == null || api == null) return;
    try {
      final now = await api.pairing(p.id);
      if (!mounted) return;
      setState(() => _paired = now);
      if (now.isStarted && now.sessionId != null) {
        _poll?.cancel();
        PairHaptics.start();
        // The recorder screen starts the recording (mic permission first).
        context.go('/notes/session?id=${now.sessionId}&role=recorder');
      } else if (now.isOver) {
        _poll?.cancel();
      }
    } on Object {
      // A missed poll; the next one tries again.
    }
  }

  void _type(String digits) {
    if (_busy || _boxes != CodeBoxesState.typing) return;
    final next = (_code + digits).replaceAll(RegExp(r'\D'), '');
    setState(() {
      _code = next.length > 6 ? next.substring(0, 6) : next;
      _error = null;
    });
    if (_code.length == 6) _claim(code: _code);
  }

  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    final digits = text.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 6) {
      setState(() => _code = '');
      _type(digits);
    } else if (mounted) {
      setState(() => _error = 'The clipboard has no 6-digit code.');
    }
  }

  void _scanned(String raw) {
    final secret = Pairing.secretFromQr(raw);
    if (secret == null) {
      setState(() => _error = "That QR isn't an OctoNotes pairing code.");
      return;
    }
    PairHaptics.found();
    _claim(secret: secret);
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OctoNotesTheme.wrap(
        context: context,
        child: Builder(builder: _build),
      );

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = _paired;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        title: const Text('Join as recorder'),
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/notes'),
        ),
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(a), child: child),
          ),
          child: p != null ? _pairedView(context, p) : _entry(context),
        ),
      ),
    );
  }

  Widget _entry(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      key: const ValueKey('entry'),
      padding: const EdgeInsets.fromLTRB(CockpitSpacing.lg, CockpitSpacing.xs, CockpitSpacing.lg, CockpitSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PairSegment(
            labels: const ['Code', 'Scan QR'],
            icons: const [Icons.pin_outlined, Icons.qr_code_scanner_rounded],
            index: _scan ? 1 : 0,
            onChanged: (i) => setState(() {
              _scan = i == 1;
              _error = null;
              _code = '';
            }),
          ),
          const SizedBox(height: CockpitSpacing.lg),
          if (_scan)
            Expanded(child: _Scanner(onCode: _scanned, busy: _busy))
          else ...[
            Text(
              'Type the 6 digits shown on your other device. Use the same account on both.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: CockpitSpacing.lg),
            Shake(trigger: _shake, child: CodeBoxes(value: _code, state: _boxes)),
          ],
          SizedBox(
            height: 40,
            child: Center(
              child: _busy
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: CockpitSpacing.sm),
                        Text('Pairing…', style: theme.textTheme.labelLarge),
                      ],
                    )
                  : _error != null
                      ? Text(_error!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(color: CockpitColors.brand.error))
                      : null,
            ),
          ),
          if (!_scan) ...[
            const Spacer(),
            NumberPad(
              onDigit: _type,
              onDelete: () {
                if (_code.isNotEmpty && _boxes == CodeBoxesState.typing) {
                  setState(() => _code = _code.substring(0, _code.length - 1));
                }
              },
              onPaste: _paste,
            ),
          ],
        ],
      ),
    );
  }

  Widget _pairedView(BuildContext context, Pairing p) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final over = p.isOver;
    return Padding(
      key: ValueKey('paired-$over'),
      padding: const EdgeInsets.all(CockpitSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (over)
            Icon(Icons.link_off_rounded, size: 64, color: scheme.onSurfaceVariant)
          else
            const SuccessCheck(size: 84),
          const SizedBox(height: CockpitSpacing.md),
          Text(
            over
                ? 'This pairing ${p.status == 'cancelled' ? 'was cancelled' : 'expired'}'
                : 'Paired with ${p.receiverName ?? 'your other device'}',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Text(
            over
                ? 'Ask for a new code on your other device.'
                : 'Keep this phone near the speaker. Recording starts the moment the session starts there.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: CockpitSpacing.xl),
          if (!over)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2, color: CockpitColors.brand.tertiary),
                ),
                const SizedBox(width: CockpitSpacing.sm),
                Text('Waiting for Start', style: theme.textTheme.labelLarge),
              ],
            )
          else
            FilledButton(
              onPressed: () => setState(() {
                _paired = null;
                _code = '';
                _boxes = CodeBoxesState.typing;
              }),
              child: const Text('Enter a new code'),
            ),
        ],
      ),
    );
  }
}

/// The camera inline: corner brackets close in on a code once it's seen.
class _Scanner extends StatefulWidget {
  const _Scanner({required this.onCode, required this.busy});
  final ValueChanged<String> onCode;
  final bool busy;

  @override
  State<_Scanner> createState() => _ScannerState();
}

class _ScannerState extends State<_Scanner> with SingleTickerProviderStateMixin {
  final _camera = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  late final _line = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat(reverse: true);
  bool _locked = false;

  @override
  void dispose() {
    _line.dispose();
    _camera.dispose();
    super.dispose();
  }

  void _detect(BarcodeCapture capture) {
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (_locked || widget.busy || raw == null) return;
    setState(() => _locked = true);
    // Let the brackets close in before claiming.
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      widget.onCode(raw);
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _locked = false);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final green = CockpitColors.brand.success;
    final red = Theme.of(context).colorScheme.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: Colors.black,
            child: MobileScanner(
              controller: _camera,
              onDetect: _detect,
              errorBuilder: (context, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    error.errorCode == MobileScannerErrorCode.permissionDenied
                        ? 'Allow the camera to scan the code, or type the 6 digits instead.'
                        : 'The camera is not available. Type the 6 digits instead.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
          LayoutBuilder(builder: (context, c) {
            final side = c.biggest.shortestSide * (_locked ? 0.52 : 0.78);
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutBack,
                  left: (c.maxWidth - side) / 2,
                  top: (c.maxHeight - side) / 2,
                  width: side,
                  height: side,
                  child: CustomPaint(painter: _Brackets(_locked ? green : Colors.white)),
                ),
                if (!_locked)
                  AnimatedBuilder(
                    animation: _line,
                    builder: (_, _) => Positioned(
                      left: (c.maxWidth - side) / 2 + 12,
                      width: side - 24,
                      top: (c.maxHeight - side) / 2 + 16 + (side - 32) * Curves.easeInOut.transform(_line.value),
                      height: 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [red.withValues(alpha: 0), red, red.withValues(alpha: 0)]),
                          boxShadow: [BoxShadow(color: red, blurRadius: 10)],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          }),
          Positioned(
            left: 0,
            right: 0,
            bottom: 18,
            child: Text(
              _locked ? 'Code found' : 'Point at the QR on your other device',
              textAlign: TextAlign.center,
              style: TextStyle(color: _locked ? green : Colors.white70, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Brackets extends CustomPainter {
  _Brackets(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const l = 30.0;
    const r = 14.0;
    for (final (x, y, dx, dy) in [(0.0, 0.0, 1.0, 1.0), (s.width, 0.0, -1.0, 1.0), (0.0, s.height, 1.0, -1.0), (s.width, s.height, -1.0, -1.0)]) {
      canvas.drawPath(
        Path()
          ..moveTo(x, y + dy * l)
          ..lineTo(x, y + dy * r)
          ..quadraticBezierTo(x, y, x + dx * r, y)
          ..lineTo(x + dx * l, y),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _Brackets old) => old.color != color;
}
