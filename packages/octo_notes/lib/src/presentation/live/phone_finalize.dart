import 'dart:async';
import 'dart:math' as math;

import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/session_providers.dart';
import '../../application/this_device.dart';
import '../../data/api/notes_api_client.dart';
import '../../data/api/octo_notes_api.dart';
import '../new_session/pairing_widgets.dart';
import '../recommendations/phone_final_notes.dart' show sendToStudyStudio;

/// Finalize on a phone: wrap up (stop recording, wait for the transcript,
/// summarize), review the topics, hold to finalize, then export or study.
/// Typographic: lists and hairlines, no cards.
class PhoneFinalize extends ConsumerStatefulWidget {
  const PhoneFinalize({super.key, this.sessionId});

  /// The backend session; null plays the offline demo.
  final String? sessionId;

  @override
  ConsumerState<PhoneFinalize> createState() => _PhoneFinalizeState();
}

enum _Stage { wrap, review, done }

class _Topic {
  _Topic(this.title, this.gist, this.points, this.color, {this.heading});
  final String title;

  /// The notes' heading this topic is (the server matched it). Finalize leaves
  /// topics out by heading, so one without can't be left out.
  final String? heading;
  final String gist;
  final List<String> points;
  final Color color;
  bool on = true;
  int? fromMs;
  int? toMs;
}

const _topicColors = [Color(0xFFE11D2E), Color(0xFFE8B84B), Color(0xFF5B8DEF), Color(0xFF3FB27F), Color(0xFFF04E3E)];

class _PhoneFinalizeState extends ConsumerState<PhoneFinalize> with TickerProviderStateMixin {
  _Stage _stage = _Stage.wrap;
  int _step = 0; // wrap steps done (0..4)
  late final _ring = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  String _title = 'Live session';
  String _course = '';
  String? _recorder;
  int _durationMs = 0;
  int _lines = 0;
  int _notes = 0;
  List<int> _marks = [];
  List<_Topic> _topics = [];
  bool _stale = false;
  bool _refreshing = false;
  String _organized = '';
  String? _deck;
  String? _finalId;
  int _open = -1;
  int _hi = -1;
  final _keys = <GlobalKey>[];
  final _titleCtrl = TextEditingController();

  OctoNotesApi? get _api => ref.read(octoNotesApiProvider);
  String? get _id => widget.sessionId;
  bool get _demo => _api == null || _id == null;

  @override
  void initState() {
    super.initState();
    unawaited(_wrapUp());
  }

  @override
  void dispose() {
    _ring.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  void _done(int step) {
    if (!mounted) return;
    HapticFeedback.lightImpact();
    setState(() => _step = step);
    _ring.animateTo(step / 4, curve: Curves.easeOutCubic);
  }

  // ── 1. Wrap up ────────────────────────────────────────────────────────────

  Future<void> _wrapUp() async {
    _ring.animateTo(0.1, duration: const Duration(seconds: 2));
    if (_demo) {
      for (var i = 1; i <= 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
        _done(i);
      }
      _seedDemo();
    } else {
      final api = _api!, id = _id!;
      await _stopRecording(api, id);
      _done(1);
      await _waitForTranscript(api, id);
      _done(2);
      await _summarize(api, id);
      _done(3);
      await _load(api, id);
      _done(4);
    }
    if (!mounted) return;
    unawaited(PairHaptics.success());
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (mounted) setState(() => _stage = _Stage.review);
  }

  Future<void> _stopRecording(OctoNotesApi api, String id) async {
    final device = await ref.read(thisDeviceProvider.future).then<String?>((d) => d.id, onError: (_) => null);
    try {
      await api.finish(id, deviceId: device);
    } on NotesApiException catch (e) {
      // Finishing here means the lecture is over: stop the other phone too.
      if (e.code == 'other_device_recording') {
        await api.finish(id, deviceId: device, mode: 'finishAndStop').catchError((_) => <String, dynamic>{});
      }
    } on Object {
      // Offline: finalize still works on what's there.
    }
  }

  /// Until every recording is joined and transcribed (at most 90 s).
  Future<void> _waitForTranscript(OctoNotesApi api, String id) async {
    final until = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(until) && mounted) {
      try {
        final recs = (await api.recordings(id)).cast<Map<String, dynamic>>();
        _durationMs = recs.fold(0, (s, r) => s + ((r['durationMs'] as num?)?.toInt() ?? 0));
        if (recs.every((r) => r['state'] == 'assembled')) return;
      } on Object {
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  Future<void> _summarize(OctoNotesApi api, String id) async {
    try {
      final s = await api.finalizeSummary(id);
      if (s['topics'] != null && s['stale'] != true) return;
      await api.summarize(id).firstWhere((e) => e.event == 'done' || e.event == 'error');
    } on Object {
      // Shown as "notes changed since the summary" with Refresh.
    }
  }

  Future<void> _load(OctoNotesApi api, String id) async {
    try {
      final r = await Future.wait([
        api.finalizeSummary(id),
        api.sessionSnapshot(id),
        api.transcript(id),
        api.markers(id).catchError((_) => <dynamic>[]),
      ]);
      final summary = r[0] as Map<String, dynamic>;
      final snap = r[1] as Map<String, dynamic>;
      final session = (snap['session'] as Map?) ?? const {};
      _title = (session['title'] as String?) ?? _title;
      _deck = session['deckRef'] as String?;
      if (_durationMs == 0) _durationMs = (session['durationMs'] as num?)?.toInt() ?? 0;
      final blocks = (snap['blocks'] as List? ?? const []).cast<Map<String, dynamic>>();
      _notes = blocks.where((b) => !(b['type'] as String? ?? '').startsWith('h')).length;
      _lines = ((r[2] as Map)['segments'] as List? ?? const []).length;
      _marks = [for (final m in (r[3] as List).cast<Map<String, dynamic>>()) (m['atMs'] as num?)?.toInt() ?? 0];
      _recorder = (snap['devices'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .where((d) => d['role'] == 'recorder')
          .map((d) => d['name'] as String?)
          .firstOrNull;
      _apply(summary, blocks);
    } on Object {
      // Review shows what loaded.
    }
  }

  void _apply(Map<String, dynamic> summary, List<Map<String, dynamic>> blocks) {
    final topics = (summary['topics'] as List? ?? const []).cast<Map<String, dynamic>>();
    _topics = [
      for (var i = 0; i < topics.length; i++)
        _Topic(
          topics[i]['title'] as String? ?? 'Topic ${i + 1}',
          topics[i]['gist'] as String? ?? '',
          [for (final p in (topics[i]['points'] as List? ?? const [])) '$p'],
          _topicColors[i % _topicColors.length],
          heading: topics[i]['heading'] as String?,
        )
          ..fromMs = (topics[i]['fromMs'] as num?)?.toInt()
          ..toMs = (topics[i]['toMs'] as num?)?.toInt(),
    ];
    _stale = summary['stale'] == true && _topics.isNotEmpty;
    _organized = [
      for (final c in (summary['categories'] as List? ?? const []).cast<Map<String, dynamic>>())
        if (c['key'] != 'topics' && ((c['count'] as num?) ?? 0) > 0) '${c['count']} ${_catName(c['key'] as String)}',
    ].join('  ·  ');
    _titleCtrl.text = _title;
    _keys
      ..clear()
      ..addAll([for (final _ in _topics) GlobalKey()]);
  }

  static String _catName(String key) => switch (key) {
        'definitions' => 'definitions',
        'questions' => 'questions',
        'examHints' => 'exam hints',
        'formulas' => 'formulas',
        'examples' => 'examples',
        _ => key,
      };

  void _seedDemo() {
    _title = 'Cellular respiration';
    _course = 'Biology 101 · Week 4';
    _recorder = 'Pixel 8';
    _durationMs = 48 * 60000 + 12000;
    _lines = 312;
    _notes = 14;
    _marks = [230000, 490000, 1300000, 1590000, 1900000, 2430000];
    const data = [
      ('Glycolysis', 'Glucose splits into two pyruvate in the cytoplasm. No oxygen needed.', ['Net 2 ATP, 2 NADH', 'Cytoplasm, anaerobic'], 0),
      ('Link reaction', 'Pyruvate enters the mitochondria and becomes acetyl CoA.', ['Releases CO₂', 'Makes NADH'], 636000),
      ('Krebs cycle', 'Turns twice per glucose, loading NADH and FADH₂ in the matrix.', ['2 ATP, 6 NADH, 2 FADH₂', 'Mitochondrial matrix'], 1100000),
      ('Electron transport chain', 'Electrons build a proton gradient; oxygen takes them at the end.', ['ATP synthase makes ~26–28 ATP', 'O₂ is the final acceptor'], 2025000),
    ];
    _topics = [
      for (var i = 0; i < data.length; i++)
        _Topic(data[i].$1, data[i].$2, data[i].$3, _topicColors[i], heading: data[i].$1)..fromMs = data[i].$4,
    ];
    for (var i = 0; i < _topics.length; i++) {
      _topics[i].toMs = i + 1 < _topics.length ? _topics[i + 1].fromMs : _durationMs;
    }
    _stale = true;
    _organized = '4 definitions  ·  3 exam hints  ·  3 questions  ·  2 formulas';
    _titleCtrl.text = _title;
    _keys.addAll([for (final _ in _topics) GlobalKey()]);
  }

  // ── 2. Review ─────────────────────────────────────────────────────────────

  void _toggle(int i) {
    setState(() => _topics[i].on = !_topics[i].on);
    _topics[i].on ? HapticFeedback.selectionClick() : HapticFeedback.lightImpact();
  }

  void _focus(int i) {
    HapticFeedback.selectionClick();
    setState(() {
      _hi = _hi == i ? -1 : i;
      _open = _hi;
    });
    final ctx = _keys[i].currentContext;
    if (ctx != null && _hi == i) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic, alignment: 0.2);
    }
  }

  Future<void> _refresh() async {
    HapticFeedback.lightImpact();
    setState(() => _refreshing = true);
    if (!_demo) {
      try {
        await _api!.summarize(_id!).firstWhere((e) => e.event == 'done' || e.event == 'error');
        final r = await Future.wait([_api!.finalizeSummary(_id!), _api!.blocks(_id!)]);
        _apply(r[0], ((r[1])['blocks'] as List? ?? const []).cast<Map<String, dynamic>>());
      } on Object catch (e) {
        if (mounted) _say("Couldn't refresh: $e");
      }
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }
    if (!mounted) return;
    unawaited(PairHaptics.success());
    setState(() {
      _refreshing = false;
      _stale = false;
    });
  }

  Future<void> _finalize() async {
    final title = _titleCtrl.text.trim().isEmpty ? _title : _titleCtrl.text.trim();
    if (!_demo) {
      try {
        final all = _topics.every((t) => t.on);
        final res = await _api!.finalize(
          _id!,
          title: title,
          includedTopics: all ? null : [for (final t in _topics) if (t.on && t.heading != null) t.heading!],
          idempotencyKey: 'finalize-$_id-${_topics.map((t) => t.on ? 1 : 0).join()}-${title.hashCode}',
        );
        _finalId = res['id'] as String?;
      } on Object catch (e) {
        if (mounted) _say("Couldn't finalize: $e");
        rethrow;
      }
    }
    _title = title;
    if (mounted) setState(() => _stage = _Stage.done);
  }

  void _say(String m) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));

  // ── 3. Done ───────────────────────────────────────────────────────────────

  Future<void> _studySet() async {
    if (_demo || _finalId == null) return Future<void>.delayed(const Duration(milliseconds: 900));
    final id = await sendToStudyStudio(_api!, _finalId!);
    if (mounted) context.go('/notes/convert?id=$id');
  }

  Future<void> _pdf() async {
    if (_demo || _finalId == null) return Future<void>.delayed(const Duration(milliseconds: 1100));
    final api = _api!;
    final e = await api.export(_finalId!, 'pdf');
    final exportId = e['exportId'] as String;
    for (var i = 0; i < 60; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final s = await api.exportStatus(exportId);
      if (s['status'] == 'failed') throw StateError('${s['error'] ?? 'The PDF could not be made.'}');
      final url = s['url'] as String?;
      if (url != null) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        return;
      }
    }
    throw StateError('The PDF is taking long. Try again in a minute.');
  }

  Future<void> _openNotes() async {
    context.go(_finalId == null ? '/notes/final' : '/notes/final?id=$_finalId');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: Stack(
        children: [
          const Positioned(left: -120, right: -120, top: -160, height: 380, child: _Aurora()),
          SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(a), child: c),
              ),
              child: switch (_stage) {
                _Stage.wrap => _wrapView(context),
                _Stage.review => _reviewView(context),
                _Stage.done => _doneView(context),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _wrapView(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const steps = ['Recording stopped', 'Transcript finished', 'Summary by topic', 'Notes organized'];
    return Padding(
      key: const ValueKey('wrap'),
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Cap('Finishing'),
          const SizedBox(height: 4),
          Text('Wrapping up\nyour lecture', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600, height: 1.15)),
          const SizedBox(height: 26),
          Center(child: _Ring(progress: _ring)),
          const SizedBox(height: 24),
          for (var i = 0; i < steps.length; i++) _StepRow(text: steps[i], state: i < _step ? 2 : (i == _step ? 1 : 0)),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Count(value: _step >= 4 || _demo ? (_durationMs / 60000).round() : null, label: 'min'),
              _Count(value: _step >= 4 || _demo ? _lines : null, label: 'lines'),
              _Count(value: _step >= 4 || _demo ? _notes : null, label: 'notes'),
              _Count(value: _step >= 4 || _demo ? _marks.length : null, label: 'marks'),
            ],
          ),
          const Spacer(),
          Text('Keep this screen open. It takes a few seconds after the lecture.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _reviewView(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final included = _topics.where((t) => t.on).length;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final minutes = (_durationMs / 60000).round();
    return Stack(
      key: const ValueKey('review'),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 18, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: () => context.canPop() ? context.pop() : context.go('/notes'),
                  ),
                  const Spacer(),
                  Icon(Icons.verified_user_outlined, size: 14, color: CockpitColors.brand.success),
                  const SizedBox(width: 4),
                  Text('Originals kept', style: muted),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 140),
                children: [
                  if (_course.isNotEmpty) _Cap(_course),
                  TextField(
                    controller: _titleCtrl,
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600, height: 1.15, letterSpacing: -0.4),
                    cursorColor: scheme.primary,
                    decoration: const InputDecoration.collapsed(hintText: 'Title', filled: false)
                        .copyWith(fillColor: Colors.transparent),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (minutes > 0) '$minutes min',
                      if (_recorder != null) 'recorded on $_recorder',
                    ].join(' · '),
                    style: muted,
                  ),
                  if (_durationMs > 0) ...[
                    const SizedBox(height: 16),
                    _Timeline(topics: _topics, marks: _marks, durationMs: _durationMs, highlight: _hi, onTap: _focus),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [Text('0:00', style: muted), Text(_clock(_durationMs), style: muted)],
                    ),
                  ],
                  AnimatedSize(
                    duration: const Duration(milliseconds: 350),
                    child: _stale
                        ? Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Row(
                              children: [
                                _refreshing
                                    ? SizedBox(
                                        width: 13,
                                        height: 13,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: CockpitColors.brand.tertiary),
                                      )
                                    : Icon(Icons.refresh_rounded, size: 16, color: CockpitColors.brand.tertiary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _refreshing ? 'Refreshing the summary…' : 'Your notes changed since the summary',
                                    style: theme.textTheme.bodySmall?.copyWith(color: CockpitColors.brand.tertiary),
                                  ),
                                ),
                                if (!_refreshing)
                                  GestureDetector(
                                    onTap: _refresh,
                                    child: Text('Refresh',
                                        style: theme.textTheme.labelLarge?.copyWith(
                                          color: CockpitColors.brand.tertiary,
                                          decoration: TextDecoration.underline,
                                          decorationColor: CockpitColors.brand.tertiary,
                                        )),
                                  ),
                              ],
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const _Cap('Topics'),
                      const Spacer(),
                      Text('$included of ${_topics.length} in your notes', style: muted),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_topics.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text('No topics yet. Refresh to summarize, or finalize your notes as they are.', style: muted),
                    ),
                  for (var i = 0; i < _topics.length; i++)
                    _TopicRow(
                      key: _keys[i],
                      index: i,
                      topic: _topics[i],
                      marks: _marks.where((m) => _topics[i].fromMs != null && m >= _topics[i].fromMs! && m < (_topics[i].toMs ?? 0)).length,
                      open: _open == i,
                      highlighted: _hi == i,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _open = _open == i ? -1 : i);
                      },
                      onToggle: () => _toggle(i),
                    ),
                  if (_organized.isNotEmpty) ...[
                    const SizedBox(height: 26),
                    const _Cap('Organized as'),
                    const SizedBox(height: 6),
                    Text(_organized, style: theme.textTheme.bodyMedium?.copyWith(height: 1.8)),
                  ],
                  if (_deck != null) ...[
                    const SizedBox(height: 18),
                    Divider(height: 1, color: scheme.outlineVariant),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        children: [
                          Icon(Icons.style_outlined, size: 18, color: CockpitColors.brand.tertiary),
                          const SizedBox(width: 12),
                          Expanded(child: Text('Saved in The Deck', style: theme.textTheme.bodyMedium)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [scheme.surface.withValues(alpha: 0), scheme.surface, scheme.surface],
                stops: const [0, 0.45, 1],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 34, 18, 16),
              child: _HoldButton(
                label: included == 0 && _topics.isNotEmpty ? 'Pick at least one topic' : 'Hold to finalize · $included topics',
                enabled: included > 0 || _topics.isEmpty,
                onConfirmed: _finalize,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _doneView(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final on = _topics.where((t) => t.on).toList();
    return Padding(
      key: const ValueKey('done'),
      padding: const EdgeInsets.fromLTRB(26, 30, 26, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: SuccessCheck(size: 70)),
          const SizedBox(height: 12),
          _Rise(delay: 600, child: const _Cap('Done')),
          _Rise(
            delay: 650,
            child: Text('Your notes\nare ready',
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.12, letterSpacing: -0.6)),
          ),
          const SizedBox(height: 8),
          _Rise(
            delay: 700,
            child: Text(
              [_title, '${on.length} topics', if (_deck != null) 'in The Deck'].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          if (on.isNotEmpty) ...[
            const SizedBox(height: 14),
            _Rise(
              delay: 750,
              child: Row(
                children: [
                  for (final t in _topics) ...[
                    Expanded(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: t.color.withValues(alpha: t.on ? 1 : 0.15),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          _Rise(
            delay: 800,
            child: _ActionRow(
              icon: Icons.auto_awesome_rounded,
              color: CockpitColors.brand.tertiary,
              title: 'Send to Study Studio',
              subtitle: 'The whole note becomes study material',
              run: _studySet,
            ),
          ),
          _Rise(
            delay: 870,
            child: _ActionRow(
              icon: Icons.picture_as_pdf_outlined,
              color: scheme.primary,
              title: 'Download PDF',
              subtitle: 'Ready to print or share',
              run: _pdf,
            ),
          ),
          _Rise(
            delay: 940,
            child: _ActionRow(
              icon: Icons.notes_rounded,
              color: CockpitColors.brand.info,
              title: 'Open notes',
              subtitle: 'Read and edit',
              run: _openNotes,
            ),
          ),
          const Spacer(),
          Text('Recording and original notes stay with the session',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

String _clock(int ms) {
  final s = ms ~/ 1000;
  String two(int n) => n.toString().padLeft(2, '0');
  return s >= 3600 ? '${s ~/ 3600}:${two(s ~/ 60 % 60)}:${two(s % 60)}' : '${s ~/ 60}:${two(s % 60)}';
}

class _Cap extends StatelessWidget {
  const _Cap(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.6,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
}

/// Slow red and gold light behind the top of the page.
class _Aurora extends StatefulWidget {
  const _Aurora();
  @override
  State<_Aurora> createState() => _AuroraState();
}

class _AuroraState extends State<_Aurora> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(painter: _AuroraPainter(_c.value)),
        ),
      );
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size s) {
    void blob(Offset c, double r, Color color) => canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r)),
        );
    blob(Offset(s.width * (0.32 + 0.05 * t), s.height * (0.5 + 0.04 * t)), s.width * 0.42, const Color(0x38E11D2E));
    blob(Offset(s.width * (0.74 - 0.04 * t), s.height * 0.42), s.width * 0.34, const Color(0x1FE8B84B));
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) => old.t != t;
}

/// A thin red-to-gold ring with a glowing head and the percent inside.
class _Ring extends StatelessWidget {
  const _Ring({required this.progress});
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 196,
      height: 196,
      child: AnimatedBuilder(
        animation: progress,
        builder: (_, _) => CustomPaint(
          painter: _RingPainter(progress.value, theme.colorScheme.surfaceContainerHigh),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${(progress.value * 100).round()}',
                    style: theme.textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.w300,
                      letterSpacing: -2,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
                Text('percent', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.p, this.track);
  final double p;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(4, 4, size.width - 8, size.height - 8);
    canvas.drawArc(r, 0, math.pi * 2, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = track);
    if (p <= 0) return;
    final sweep = math.pi * 2 * p;
    canvas.drawArc(
      r,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: -math.pi / 2 + math.max(sweep, 0.01),
          colors: const [Color(0xFFE11D2E), Color(0xFFE8B84B)],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(r),
    );
    final a = -math.pi / 2 + sweep;
    final head = r.center + Offset(math.cos(a), math.sin(a)) * r.width / 2;
    canvas.drawCircle(head, 12, Paint()..color = const Color(0x40E8B84B));
    canvas.drawCircle(head, 5.5, Paint()..color = const Color(0xFFE8B84B));
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.p != p;
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.text, required this.state});
  final String text;

  /// 0 waiting, 1 working, 2 done.
  final int state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = switch (state) { 2 => scheme.onSurfaceVariant, 1 => scheme.onSurface, _ => scheme.outline };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (c, a) => ScaleTransition(scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack), child: c),
              child: state == 2
                  ? Icon(Icons.check_rounded, key: const ValueKey(2), size: 16, color: CockpitColors.brand.success)
                  : state == 1
                      ? const _PulseDot(key: ValueKey(1))
                      : Container(key: const ValueKey(0), width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            ),
          ),
          const SizedBox(width: 12),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 300),
            style: theme.textTheme.bodyMedium!.copyWith(color: color),
            child: Text(text),
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({super.key});
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final red = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: red,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: red.withValues(alpha: 0.35 * (1 - _c.value)), spreadRadius: 7 * _c.value)],
        ),
      ),
    );
  }
}

/// A number that counts up once it's known.
class _Count extends StatelessWidget {
  const _Count({required this.value, required this.label});
  final int? value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: (value ?? 0).toDouble()),
          duration: const Duration(milliseconds: 1100),
          curve: Curves.easeOutCubic,
          builder: (_, v, _) => Text(value == null ? '–' : '${v.round()}',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w300,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ),
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

/// The lecture as a thin line: topic spans in their colours, marks as gold
/// pins. Tap a span to jump to its topic.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.topics, required this.marks, required this.durationMs, required this.highlight, required this.onTap});
  final List<_Topic> topics;
  final List<int> marks;
  final int durationMs;
  final int highlight;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.surfaceContainerHigh;
    final gold = CockpitColors.brand.tertiary;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      double x(int ms) => (ms / durationMs).clamp(0.0, 1.0) * w;
      return SizedBox(
        height: 30,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(left: 0, right: 0, top: 13, height: 4, child: DecoratedBox(decoration: BoxDecoration(color: track, borderRadius: BorderRadius.circular(2)))),
            for (var i = 0; i < topics.length; i++)
              if (topics[i].fromMs != null)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutBack,
                  left: x(topics[i].fromMs!),
                  width: math.max(4, x(topics[i].toMs ?? durationMs) - x(topics[i].fromMs!) - 3),
                  top: highlight == i ? 9 : 12,
                  height: highlight == i ? 12 : 6,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTap(i),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 300),
                      opacity: topics[i].on ? 1 : 0.18,
                      child: DecoratedBox(decoration: BoxDecoration(color: topics[i].color, borderRadius: BorderRadius.circular(3))),
                    ),
                  ),
                ),
            for (var k = 0; k < marks.length; k++)
              Positioned(
                left: x(marks[k]) - 4,
                top: 0,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: Duration(milliseconds: 450 + k * 70),
                  curve: Curves.easeOutBack,
                  builder: (_, t, child) => Opacity(
                    opacity: t.clamp(0.0, 1.0),
                    child: Transform.translate(offset: Offset(0, (1 - t) * -10), child: child),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: gold,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: gold.withValues(alpha: 0.7), blurRadius: 8)],
                        ),
                      ),
                      Container(width: 2, height: 6, color: gold),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _TopicRow extends StatelessWidget {
  const _TopicRow({
    super.key,
    required this.index,
    required this.topic,
    required this.marks,
    required this.open,
    required this.highlighted,
    required this.onTap,
    required this.onToggle,
  });

  final int index;
  final _Topic topic;
  final int marks;
  final bool open;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final t = topic;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: t.on ? 1 : 0.38,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant))),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 34,
                      child: AnimatedScale(
                        scale: highlighted ? 1.18 : 1,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutBack,
                        alignment: Alignment.topLeft,
                        child: Text('${index + 1}',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: t.color,
                              fontWeight: FontWeight.w300,
                              height: 1,
                            )),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                          if (t.gist.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(t.gist, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.45)),
                          ],
                          if (marks > 0) ...[
                            const SizedBox(height: 6),
                            Text('★ $marks marked',
                                style: theme.textTheme.labelSmall?.copyWith(color: CockpitColors.brand.tertiary)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (t.heading != null) _TopicSwitch(on: t.on, color: t.color, onTap: onToggle),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topLeft,
                  child: open && t.points.isNotEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(left: 34, top: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final p in t.points)
                                Container(
                                  margin: const EdgeInsets.only(top: 6),
                                  padding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
                                  decoration: BoxDecoration(border: Border(left: BorderSide(color: t.color))),
                                  child: Text(p, style: theme.textTheme.bodyMedium),
                                ),
                            ],
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopicSwitch extends StatelessWidget {
  const _TopicSwitch({required this.on, required this.color, required this.onTap});
  final bool on;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      toggled: on,
      label: 'Include in notes',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 40,
          height: 24,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: on ? color : scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(99)),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutBack,
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(width: 18, height: 18, decoration: const BoxDecoration(color: Color(0xFFECEDED), shape: BoxShape.circle)),
          ),
        ),
      ),
    );
  }
}

/// Press and hold to confirm: the red fills, ten rising ticks, a heavy
/// thump when full. Let go early and it springs back.
class _HoldButton extends StatefulWidget {
  const _HoldButton({required this.label, required this.enabled, required this.onConfirmed});
  final String label;
  final bool enabled;
  final Future<void> Function() onConfirmed;

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> with TickerProviderStateMixin {
  late final _fill = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))
    ..addListener(_tick)
    ..addStatusListener(_status);
  late final _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
  int _ticks = 0;
  bool _busy = false;

  void _tick() {
    final n = (_fill.value * 10).floor();
    if (n > _ticks && _fill.status == AnimationStatus.forward) {
      _ticks = n;
      HapticFeedback.selectionClick();
    }
  }

  Future<void> _status(AnimationStatus s) async {
    if (s != AnimationStatus.completed) return;
    HapticFeedback.heavyImpact();
    setState(() => _busy = true);
    try {
      await widget.onConfirmed();
    } on Object {
      if (mounted) {
        setState(() => _busy = false);
        _fill.animateBack(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOutBack);
      }
    }
  }

  void _down(_) {
    if (_busy) return;
    if (!widget.enabled) {
      HapticFeedback.heavyImpact();
      _shake.forward(from: 0);
      return;
    }
    _ticks = 0;
    _fill.forward();
  }

  void _up([_]) {
    if (_busy || _fill.isCompleted) return;
    _fill.animateBack(0, duration: const Duration(milliseconds: 420), curve: Curves.easeOutBack);
  }

  @override
  void dispose() {
    _fill.dispose();
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final red = theme.colorScheme.primary;
    return Semantics(
      button: true,
      label: '${widget.label}. Press and hold.',
      child: GestureDetector(
        onTapDown: _down,
        onTapUp: _up,
        onTapCancel: _up,
        child: AnimatedBuilder(
          animation: Listenable.merge([_fill, _shake]),
          builder: (context, _) {
            final holding = _fill.value > 0 && !_busy;
            final dx = math.sin(_shake.value * math.pi * 4) * 7 * (1 - _shake.value);
            return Transform.translate(
              offset: Offset(dx, 0),
              child: Transform.scale(
                scale: holding ? 0.97 : 1,
                child: Container(
                  height: 56,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(color: red.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(99)),
                  child: Stack(
                    children: [
                      FractionallySizedBox(
                        widthFactor: Curves.easeInOut.transform(_fill.value),
                        heightFactor: 1,
                        child: ColoredBox(color: red),
                      ),
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_busy) ...[
                              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              _busy ? 'Finalizing' : (holding ? 'Keep holding' : widget.label),
                              style: theme.textTheme.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A row that runs its job: spinner while it works, a check when done.
class _ActionRow extends StatefulWidget {
  const _ActionRow({required this.icon, required this.color, required this.title, required this.subtitle, required this.run});
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Future<void> Function() run;

  @override
  State<_ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends State<_ActionRow> {
  int _state = 0; // 0 idle, 1 working, 2 done

  Future<void> _go() async {
    if (_state == 1) return;
    HapticFeedback.lightImpact();
    setState(() => _state = 1);
    try {
      await widget.run();
      if (!mounted) return;
      unawaited(PairHaptics.success());
      setState(() => _state = 2);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _state = 0);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('$e'.replaceFirst('Bad state: ', '')), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant))),
      child: InkWell(
        onTap: _go,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              Icon(widget.icon, size: 21, color: widget.color),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    Text(widget.subtitle, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (c, a) => ScaleTransition(scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack), child: c),
                child: switch (_state) {
                  1 => const SizedBox(key: ValueKey(1), width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  2 => Icon(Icons.check_rounded, key: const ValueKey(2), color: CockpitColors.brand.success),
                  _ => Icon(Icons.arrow_forward_rounded, key: const ValueKey(0), size: 18, color: scheme.onSurfaceVariant),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Rise extends StatelessWidget {
  const _Rise({required this.delay, required this.child});
  final int delay;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 500 + delay),
        builder: (_, v, c) {
          final t = Curves.easeOutBack.transform(((v * (500 + delay) - delay) / 500).clamp(0.0, 1.0));
          return Opacity(opacity: t.clamp(0.0, 1.0), child: Transform.translate(offset: Offset(0, (1 - t) * 14), child: c));
        },
        child: child,
      );
}
