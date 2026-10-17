import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../application/providers.dart';
import '../../data/api/share_api.dart';
import '../../data/api/sse_client.dart';
import '../../domain/entities/studio.dart';
import 'mobile_header.dart';
import 'mobile_motion.dart';
import 'mobile_style.dart';

/// The text that goes with a share link.
String shareMessage(Studio studio, String url) =>
    'Study "${studio.title}" with me on Octopilot Study Studio: $url';

/// Studio settings' SHARE row: turn the link on and send it; how many added
/// it; "Stop sharing" turns it off (copies already made stay theirs).
class StudioShareRow extends ConsumerStatefulWidget {
  const StudioShareRow({super.key, required this.studio});

  final Studio studio;

  @override
  ConsumerState<StudioShareRow> createState() => _StudioShareRowState();
}

class _StudioShareRowState extends ConsumerState<StudioShareRow> {
  StudioShare? _share;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(shareApiProvider);
    if (api == null) return;
    try {
      final s = await api.current(widget.studio.id);
      if (mounted) setState(() => _share = s);
    } on Object {
      // The row still works: tapping turns the link on.
    }
  }

  Future<void> _shareLink() async {
    final api = ref.read(shareApiProvider);
    if (api == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = _share?.on ?? false
          ? _share!
          : await api.turnOn(widget.studio.id);
      if (!mounted) return;
      setState(() => _share = s);
      await SharePlus.instance.share(
        ShareParams(
          text: shareMessage(widget.studio, s.url!),
          subject: widget.studio.title,
        ),
      );
    } on Object catch (e) {
      SmHaptics.error();
      if (mounted) {
        setState(
          () => _error = e is SseException
              ? e.message
              : 'Couldn’t make the link. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    final api = ref.read(shareApiProvider);
    if (api == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop sharing?'),
        content: const Text(
          'The link stops working, so no one new can add this studio. '
          'People who already added it keep their copy.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Stop sharing'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await api.turnOff(widget.studio.id);
      if (mounted) setState(() => _share = const StudioShare());
    } on Object {
      SmHaptics.error();
      if (mounted) {
        setState(() => _error = 'Couldn’t stop sharing. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final on = _share?.on ?? false;
    final copies = _share?.copies ?? 0;
    final note = !on
        ? 'Anyone with the link can add their own copy'
        : copies == 0
        ? 'Link is on · no one has added it yet'
        : 'Link is on · added by $copies ${copies == 1 ? 'person' : 'people'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SmPressable(
          semanticLabel: 'Share studio',
          haptic: SmHaptics.tap,
          onTap: _busy ? null : _shareLink,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Share link', style: t.body.copyWith(fontSize: 14)),
                      Text(note, style: t.small.copyWith(fontSize: 11.5)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (_busy)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.accent,
                    ),
                  )
                else
                  Icon(Icons.ios_share_rounded, size: 18, color: c.accentSoft),
              ],
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                _error ??
                    'Files aren’t shared, only the lessons, cards and quizzes.',
                style: t.small.copyWith(
                  fontSize: 11,
                  color: _error != null ? c.accentSoft : c.hint,
                ),
              ),
            ),
            if (on)
              SmPressable(
                semanticLabel: 'Stop sharing',
                haptic: SmHaptics.tap,
                onTap: _busy ? null : _stop,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 4,
                  ),
                  child: Text(
                    'Stop sharing',
                    style: t.small.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: c.muted,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// What a share link holds, and "Add to my studios".
class SharePreviewPage extends ConsumerStatefulWidget {
  const SharePreviewPage({super.key, required this.code});

  final String code;

  @override
  ConsumerState<SharePreviewPage> createState() => _SharePreviewPageState();
}

class _SharePreviewPageState extends ConsumerState<SharePreviewPage> {
  late Future<SharePreview> _preview = _fetch();

  /// One copy per visit, even if "Add" is tapped twice or retried.
  final _requestId = newRequestId();
  var _adding = false;
  String? _error;

  Future<SharePreview> _fetch() async {
    final api = ref.read(shareApiProvider);
    if (api == null) throw SseException('Sharing needs the online app.');
    return api.preview(widget.code);
  }

  Future<void> _add() async {
    final api = ref.read(shareApiProvider);
    if (api == null || _adding) return;
    setState(() {
      _adding = true;
      _error = null;
    });
    try {
      final studio = await api.copy(widget.code, requestId: _requestId);
      ref.invalidate(studioListProvider);
      SmHaptics.done();
      if (mounted) context.go('/study/${studio.id}');
    } on Object catch (e) {
      SmHaptics.error();
      if (mounted) {
        setState(() {
          _adding = false;
          _error = e is SseException
              ? e.message
              : 'Couldn’t add the studio. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final signedIn = ref.watch(authStateProvider).valueOrNull ?? false;
    return Scaffold(
      backgroundColor: c.background,
      body: SmHeaderPage(
        header: SmHeader(
          title: 'Shared studio',
          onBack: () => context.go('/study'),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, SmHeader.clearance + 16, 24, 24),
            child: FutureBuilder<SharePreview>(
              future: _preview,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return Center(
                    child: CircularProgressIndicator(
                      color: c.accent,
                      strokeWidth: 2.5,
                    ),
                  );
                }
                if (snap.hasError) {
                  final e = snap.error;
                  final msg = e is SseException && !e.message.startsWith('HTTP')
                      ? e.message
                      : signedIn
                      ? 'Couldn’t open the link. Try again.'
                      : 'Sign in to open this studio.';
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.link_off_rounded, size: 40, color: c.hint),
                      const SizedBox(height: 12),
                      Text(msg, style: t.body, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      // A link that is gone stays gone: offer home instead.
                      if (msg.contains('doesn’t exist') ||
                          msg.contains("doesn't exist") ||
                          msg.contains('turned off'))
                        _Button(
                          label: 'Go to my studios',
                          onTap: () => context.go('/study'),
                        )
                      else
                        _Button(
                          label: 'Try again',
                          onTap: () => setState(() => _preview = _fetch()),
                        ),
                    ],
                  );
                }
                final p = snap.data!;
                final counts = [
                  '${p.lessons} ${p.lessons == 1 ? 'lesson' : 'lessons'}',
                  '${p.cards} cards',
                  if (p.scenarios > 0) '${p.scenarios} scenarios',
                ].join(' · ');
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SmAppear(
                      index: 0,
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: c.accent.withValues(alpha: 0.16),
                            foregroundImage: p.sharedByPhoto == null
                                ? null
                                : NetworkImage(p.sharedByPhoto!),
                            child: Icon(
                              Icons.person_rounded,
                              size: 18,
                              color: c.accentSoft,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              p.sharedBy == null
                                  ? 'Someone shared a studio with you'
                                  : '${p.sharedBy} shared a studio with you',
                              style: t.small.copyWith(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    SmAppear(
                      index: 1,
                      child: Text(
                        p.title,
                        style: t.title.copyWith(fontSize: 26, height: 1.15),
                      ),
                    ),
                    if (p.subject.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(p.subject, style: t.small.copyWith(color: c.muted)),
                    ],
                    const SizedBox(height: 10),
                    SmAppear(
                      index: 2,
                      child: Text(
                        counts,
                        style: t.body.copyWith(color: c.muted),
                      ),
                    ),
                    const SizedBox(height: 22),
                    SmAppear(
                      index: 3,
                      child: Text(
                        'You get your own copy: your progress starts fresh, '
                        'and Ask AI works on its material. The original files '
                        'aren’t included.',
                        style: t.small.copyWith(fontSize: 13, height: 1.5),
                      ),
                    ),
                    const Spacer(),
                    if (_error != null) ...[
                      Text(
                        _error!,
                        style: t.small.copyWith(color: c.accentSoft),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                    ],
                    _Button(
                      label: 'Add to my studios',
                      busy: _adding,
                      primary: true,
                      onTap: _add,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    required this.onTap,
    this.busy = false,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool busy;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    return SmPressable(
      semanticLabel: label,
      haptic: SmHaptics.thud,
      onTap: busy ? null : onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          color: primary ? c.accent : null,
          border: primary ? null : Border.all(color: c.line),
        ),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  fontFamily: SmFonts.heading,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: primary ? Colors.white : c.text,
                ),
              ),
      ),
    );
  }
}
