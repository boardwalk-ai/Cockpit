import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/session_providers.dart';
import '../../data/api/notes_api_client.dart';
import '../../data/api/octo_notes_api.dart';
import '../new_session/pairing_widgets.dart';

/// Sends a whole final note to Study Studio as material: every topic goes,
/// and Study Studio's AI decides what to build. Returns the conversion id.
Future<String> sendToStudyStudio(OctoNotesApi api, String finalNotesId) async {
  // Topics are prepared in the background right after finalizing.
  for (var i = 0; i < 20; i++) {
    try {
      final rec = await api.recommendations(finalNotesId);
      final ids = [for (final t in (rec['topics'] as List? ?? const [])) '${(t as Map)['id']}'];
      final c = await api.createConversion(finalNotesId, topicIds: ids);
      return '${c['id'] ?? c['conversionId']}';
    } on NotesApiException catch (e) {
      if (e.code != 'recommendations_pending') rethrow;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }
  throw StateError('Study Studio is still reading your notes. Try again in a moment.');
}

/// Final notes on a phone: read them, play the lecture behind a quote, get
/// the PDF, send the note to Study Studio. Typographic, no cards; a floating
/// capsule switches topics and follows the scroll.
class PhoneFinalNotes extends ConsumerStatefulWidget {
  const PhoneFinalNotes({super.key, this.finalNotesId});

  /// Null plays the offline demo.
  final String? finalNotesId;

  @override
  ConsumerState<PhoneFinalNotes> createState() => _PhoneFinalNotesState();
}

class _Section {
  _Section(this.title, this.color);
  final String? title; // null: the part before the first heading
  final Color color;
  final List<Map<String, dynamic>> blocks = [];
  final key = GlobalKey();
}

const _colors = [Color(0xFFE11D2E), Color(0xFFE8B84B), Color(0xFF5B8DEF), Color(0xFF3FB27F), Color(0xFFF04E3E)];

class _PhoneFinalNotesState extends ConsumerState<PhoneFinalNotes> {
  final _scroll = ScrollController();
  final _studyKey = GlobalKey();
  bool _loading = true;
  String? _error;

  String _title = '';
  String _meta = '';
  int _version = 1;
  String? _sessionId;
  int _durationMs = 0;
  int _photos = 0;
  List<_Section> _sections = [];
  int _active = 0;
  double _read = 0;

  // Audio behind the quotes.
  /// Made on the first play (no audio plugin needed until then).
  AudioPlayer? _player;
  String? _audioUrl;
  Map<String, dynamic>? _playing;
  int _startMs = 0;
  Duration _pos = Duration.zero;
  bool _isPlaying = false;
  double _speed = 1;
  final _subs = <StreamSubscription<Object?>>[];

  OctoNotesApi? get _api => ref.read(octoNotesApiProvider);
  bool get _demo => _api == null || widget.finalNotesId == null;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    unawaited(_player?.dispose());
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      if (_demo) {
        _demoNotes();
      } else {
        final f = await _api!.finalNotes(widget.finalNotesId!);
        final content = (f['content'] as Map?) ?? const {};
        _title = f['title'] as String? ?? 'Final notes';
        _version = (f['version'] as num?)?.toInt() ?? 1;
        _sessionId = f['sessionId'] as String?;
        _durationMs = (content['durationMs'] as num?)?.toInt() ?? 0;
        _split((content['blocks'] as List? ?? const []).cast<Map<String, dynamic>>());
        final when = DateTime.tryParse('${f['finalizedAt']}')?.toLocal();
        _meta = [
          if (when != null) '${_month(when.month)} ${when.day}',
          if (_durationMs > 0) '${(_durationMs / 60000).round()} min lecture',
          '${_sections.where((s) => s.title != null).length} topics',
          if (f['deckRef'] != null) 'in The Deck',
        ].join(' · ');
        if (_sessionId != null) {
          final mats = await _api!.materials(_sessionId!).catchError((_) => <dynamic>[]);
          _photos = mats.where((m) => (m as Map)['kind'] == 'whiteboardPhoto').length;
        }
      }
    } on Object catch (e) {
      _error = "Couldn't open these notes: $e";
    }
    if (mounted) setState(() => _loading = false);
  }

  void _split(List<Map<String, dynamic>> blocks) {
    _sections = [_Section(null, _colors[0])];
    for (final b in blocks) {
      final type = b['type'] as String? ?? 'paragraph';
      if (type == 'h1' || type == 'h2') {
        final n = _sections.where((s) => s.title != null).length;
        _sections.add(_Section(b['text'] as String? ?? '', _colors[n % _colors.length]));
      } else {
        _sections.last.blocks.add(b);
      }
    }
    if (_sections.first.blocks.isEmpty) _sections.removeAt(0);
  }

  static String _month(int m) => const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m - 1];

  void _demoNotes() {
    _title = 'Cellular respiration';
    _meta = 'Oct 17 · 48 min lecture · 4 topics · in The Deck';
    _durationMs = 48 * 60000;
    _photos = 2;
    Map<String, dynamic> b(String type, String text, [int? at]) => {'type': type, 'text': text, 'audioTsMs': ?at};
    _split([
      b('h2', 'Glycolysis'),
      b('paragraph', 'Glycolysis is the first stage of respiration and happens in the cytoplasm.'),
      b('bulleted', 'Glucose (6C) splits into two pyruvate (3C)'),
      b('bulleted', 'Net gain: 2 ATP and 2 NADH'),
      b('quote', 'It doesn’t need oxygen, which is why it still runs in muscle during a sprint.', 125000),
      b('definition', 'Anaerobic: a process that runs without oxygen.'),
      b('examHint', 'Expect a question on the net ATP yield, not the gross.'),
      b('h2', 'Link reaction'),
      b('paragraph', 'Pyruvate moves into the mitochondrial matrix and becomes acetyl CoA.'),
      b('bulleted', 'One CO₂ released per pyruvate'),
      b('quote', 'Think of it as the bridge between glycolysis and the Krebs cycle.', 722000),
      b('h2', 'Krebs cycle'),
      b('paragraph', 'The cycle turns twice for every glucose, loading the carriers.'),
      b('formula', 'Per glucose: 2 ATP + 6 NADH + 2 FADH₂ + 4 CO₂'),
      {'type': 'paragraph', 'text': 'Each turn starts when acetyl CoA joins oxaloacetate to make citrate.', 'origin': 'aiInsertedByStudent'},
      b('h2', 'Electron transport'),
      b('paragraph', 'Electrons from NADH and FADH₂ pass along proteins in the inner membrane.'),
      b('bulleted', 'ATP synthase uses the gradient to make about 26–28 ATP'),
      b('definition', 'Final electron acceptor: oxygen, which forms water.'),
    ]);
  }

  // ── Scroll: which topic, how far ─────────────────────────────────────────

  void _onScroll() {
    final p = _scroll.position;
    var active = 0;
    final keys = [for (final s in _sections) s.key, _studyKey];
    for (var i = 0; i < keys.length; i++) {
      final box = keys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.localToGlobal(Offset.zero).dy < 220) active = i;
    }
    final read = p.maxScrollExtent <= 0 ? 1.0 : (p.pixels / p.maxScrollExtent).clamp(0.0, 1.0);
    if (active != _active) HapticFeedback.selectionClick();
    if (active != _active || (read - _read).abs() > 0.005) {
      setState(() {
        _active = active;
        _read = read;
      });
    }
  }

  void _jump(int i) {
    HapticFeedback.selectionClick();
    final key = i < _sections.length ? _sections[i].key : _studyKey;
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic, alignment: 0.05);
    }
  }

  // ── Audio ────────────────────────────────────────────────────────────────

  Future<void> _play(Map<String, dynamic> block) async {
    final at = _at(block);
    if (at == null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _playing = block;
      _startMs = at;
    });
    if (_demo) {
      setState(() => _isPlaying = true);
      return;
    }
    try {
      _audioUrl ??= await _audio();
      final player = _player ??= _newPlayer();
      await player.setPlaybackRate(_speed);
      await player.play(UrlSource(_audioUrl!), position: Duration(milliseconds: at));
    } on Object catch (e) {
      if (mounted) _say("Couldn't play the lecture: $e");
    }
  }

  AudioPlayer _newPlayer() {
    final p = AudioPlayer();
    _subs
      ..add(p.onPositionChanged.listen((d) => setState(() => _pos = d)))
      ..add(p.onPlayerStateChanged.listen((s) => setState(() => _isPlaying = s == PlayerState.playing)));
    return p;
  }

  Future<String> _audio() async {
    final recs = (await _api!.recordings(_sessionId!)).cast<Map<String, dynamic>>();
    final r = recs.where((r) => r['state'] == 'assembled').firstOrNull ?? recs.firstOrNull;
    if (r == null) throw StateError('no recording');
    return (await _api!.audioLink(r['id'] as String))['url'] as String;
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    if (_player == null) {
      setState(() => _isPlaying = !_isPlaying);
    } else {
      _isPlaying ? _player!.pause() : _player!.resume();
    }
  }

  void _cycleSpeed() {
    HapticFeedback.selectionClick();
    setState(() => _speed = _speed == 1 ? 1.5 : (_speed == 1.5 ? 2 : 1));
    unawaited(_player?.setPlaybackRate(_speed));
  }

  void _closePlayer() {
    HapticFeedback.lightImpact();
    unawaited(_player?.stop());
    setState(() {
      _playing = null;
      _isPlaying = false;
    });
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _pdf() async {
    if (_demo) return;
    HapticFeedback.lightImpact();
    _say('Making the PDF…');
    try {
      final e = await _api!.export(widget.finalNotesId!, 'pdf');
      for (var i = 0; i < 60; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        final s = await _api!.exportStatus(e['exportId'] as String);
        if (s['status'] == 'failed') throw StateError('${s['error'] ?? 'The PDF could not be made.'}');
        final url = s['url'] as String?;
        if (url != null) {
          unawaited(PairHaptics.success());
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          return;
        }
      }
    } on Object catch (e) {
      if (mounted) _say('$e'.replaceFirst('Bad state: ', ''));
    }
  }

  Future<void> _study() async {
    if (_demo) return Future<void>.delayed(const Duration(milliseconds: 1500));
    final id = await sendToStudyStudio(_api!, widget.finalNotesId!);
    if (mounted) context.go('/notes/convert?id=$id');
  }

  void _say(String m) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final topics = _sections.where((s) => s.title != null).toList();
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Stack(
          children: [
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
            else
              _body(context),
            // Header: back, version, PDF.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: ColoredBox(
                color: scheme.surface,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 2, 8, 2),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Back',
                            icon: const Icon(Icons.chevron_left_rounded),
                            onPressed: () => context.canPop() ? context.pop() : context.go('/notes'),
                          ),
                          Icon(Icons.lock_outline_rounded, size: 13, color: CockpitColors.brand.success),
                          const SizedBox(width: 5),
                          Text('Final · version $_version', style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                          const Spacer(),
                          IconButton(tooltip: 'Download PDF', icon: const Icon(Icons.file_download_outlined), onPressed: _pdf),
                        ],
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedFractionallySizedBox(
                        duration: const Duration(milliseconds: 120),
                        widthFactor: _read,
                        child: Container(
                          height: 2,
                          decoration: BoxDecoration(gradient: LinearGradient(colors: [scheme.primary, CockpitColors.brand.tertiary])),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!_loading && _error == null && topics.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                top: 54,
                child: _TopicCapsule(
                  sections: _sections,
                  active: _active,
                  onTap: _jump,
                ),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: AnimatedSlide(
                offset: _playing == null ? const Offset(0, 1.6) : Offset.zero,
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOutBack,
                child: _Player(
                  quote: _playing?['text'] as String? ?? '',
                  at: _player == null ? Duration(milliseconds: _startMs) : _pos,
                  playing: _isPlaying,
                  speed: _speed,
                  onToggle: _toggle,
                  onSpeed: _cycleSpeed,
                  onClose: _closePlayer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    var n = 0;
    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(24, 118, 24, 150),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_title, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.12, letterSpacing: -0.6)),
          const SizedBox(height: 6),
          Text(_meta, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          for (final s in _sections)
            _SectionView(
              key: s.key,
              number: s.title == null ? null : ++n,
              section: s,
              playing: _playing,
              onPlay: _play,
            ),
          _StudySection(
            key: _studyKey,
            sections: _sections,
            durationMs: _durationMs,
            photos: _photos,
            onSend: _study,
          ),
        ],
      ),
    );
  }
}

/// Floating above the page: topic numbers; the current one fills with its
/// colour and shows its name.
class _TopicCapsule extends StatelessWidget {
  const _TopicCapsule({required this.sections, required this.active, required this.onTap});
  final List<_Section> sections;
  final int active;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    var n = 0;
    final items = <Widget>[
      for (var i = 0; i < sections.length; i++)
        if (sections[i].title != null) _pill(context, i, '${++n}', sections[i].title!, sections[i].color),
      _pill(context, sections.length, null, 'Study', scheme.onSurface),
    ];
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
          boxShadow: const [BoxShadow(color: Color(0x8C000000), blurRadius: 24, offset: Offset(0, 8))],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(mainAxisSize: MainAxisSize.min, children: items),
        ),
      ),
    );
  }

  Widget _pill(BuildContext context, int index, String? number, String name, Color color) {
    final theme = Theme.of(context);
    final on = index == active;
    final fg = on ? const Color(0xFF121313) : theme.colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: on,
      label: name,
      child: GestureDetector(
        onTap: () => onTap(index),
        child: AnimatedContainer(
          // No overshoot here: a shadow can't blur below zero.
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: on ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(99),
            boxShadow: on ? [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 14, offset: const Offset(0, 4))] : null,
          ),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutBack,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (number != null)
                  Text(number, style: theme.textTheme.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w700))
                else
                  Icon(Icons.auto_awesome_rounded, size: 15, color: fg),
                if (on) ...[
                  const SizedBox(width: 7),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionView extends StatelessWidget {
  const _SectionView({super.key, required this.number, required this.section, required this.playing, required this.onPlay});
  final int? number;
  final _Section section;
  final Map<String, dynamic>? playing;
  final ValueChanged<Map<String, dynamic>> onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = section.color;
    return Padding(
      padding: EdgeInsets.only(top: number == null ? 18 : 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (number != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('$number', style: theme.textTheme.headlineMedium?.copyWith(color: c, fontWeight: FontWeight.w300, height: 1)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(section.title!,
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.3)),
                  ),
                ],
              ),
            ),
          for (final b in section.blocks) _Block(block: b, color: c, playing: identical(b, playing), onPlay: onPlay),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.block, required this.color, required this.playing, required this.onPlay});
  final Map<String, dynamic> block;
  final Color color;
  final bool playing;
  final ValueChanged<Map<String, dynamic>> onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brand = CockpitColors.brand;
    final type = block['type'] as String? ?? 'paragraph';
    final text = block['text'] as String? ?? '';
    final body = theme.textTheme.bodyLarge?.copyWith(height: 1.6, color: scheme.onSurface.withValues(alpha: 0.88));
    final ai = block['origin'] == 'aiInsertedByStudent';

    Widget labelled(String label, IconData icon, Color c, Widget child) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 13, color: c),
                  const SizedBox(width: 6),
                  Text(label.toUpperCase(), style: theme.textTheme.labelSmall?.copyWith(color: c, letterSpacing: 1.5)),
                ],
              ),
              const SizedBox(height: 4),
              child,
            ],
          ),
        );

    switch (type) {
      case 'h3':
        return Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 2),
          child: Text(text, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        );
      case 'bulleted' || 'numbered' || 'checklist':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, right: 10),
                child: Container(width: 5, height: 5, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              ),
              Expanded(child: Text(text, style: body)),
            ],
          ),
        );
      case 'quote' || 'transcriptExcerpt':
        final at = _at(block);
        return GestureDetector(
          onTap: at == null ? null : () => onPlay(block),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(vertical: 12),
            padding: const EdgeInsets.only(left: 14, top: 2, bottom: 2),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: brand.tertiary, width: playing ? 3 : 2))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('“$text”',
                    style: body?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: playing ? scheme.onSurface : scheme.onSurfaceVariant,
                    )),
                if (at != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(playing ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded, size: 15, color: brand.tertiary),
                      const SizedBox(width: 4),
                      Text('${_clock(at)} · from the lecture', style: theme.textTheme.labelSmall?.copyWith(color: brand.tertiary)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      case 'definition' || 'keyIdea':
        final i = text.indexOf(':');
        final term = i > 0 && i < 60 ? text.substring(0, i) : null;
        return labelled(
          type == 'keyIdea' ? 'Key idea' : 'Definition',
          Icons.menu_book_outlined,
          brand.info,
          term == null
              ? Text(text, style: body)
              : Text.rich(
                  TextSpan(children: [
                    TextSpan(text: term, style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: text.substring(i)),
                  ]),
                  style: body,
                ),
        );
      case 'examHint' || 'warning':
        return labelled(type == 'warning' ? 'Watch out' : 'Exam hint', Icons.track_changes_rounded, scheme.primary, Text(text, style: body));
      case 'question':
        return labelled('Question', Icons.help_outline_rounded, brand.tertiary, Text(text, style: body));
      case 'example':
        return labelled('Example', Icons.lightbulb_outline_rounded, brand.success, Text(text, style: body));
      case 'summary':
        return labelled('Summary', Icons.short_text_rounded, scheme.onSurfaceVariant, Text(text, style: body));
      case 'formula':
        return labelled(
          'Formula',
          Icons.functions_rounded,
          brand.success,
          Text(text, style: body?.copyWith(fontFamily: 'monospace', fontSize: 14, color: const Color(0xFFE9E3CF))),
        );
      case 'divider':
        return Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Divider(height: 1, color: scheme.outlineVariant));
      default:
        if (text.trim().isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text.rich(
            TextSpan(children: [
              if (ai)
                TextSpan(
                  text: 'AI  ',
                  style: theme.textTheme.labelSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w800, letterSpacing: 0.6),
                ),
              TextSpan(text: text),
            ]),
            style: body,
          ),
        );
    }
  }
}

/// The whole note goes to Study Studio as material; its AI decides the rest.
class _StudySection extends StatefulWidget {
  const _StudySection({super.key, required this.sections, required this.durationMs, required this.photos, required this.onSend});
  final List<_Section> sections;
  final int durationMs;
  final int photos;
  final Future<void> Function() onSend;

  @override
  State<_StudySection> createState() => _StudySectionState();
}

class _StudySectionState extends State<_StudySection> {
  int _state = 0; // 0 idle, 1 sending, 2 sent
  int _pulse = -1;

  Future<void> _send() async {
    if (_state != 0) return;
    HapticFeedback.mediumImpact();
    // Each kind of material "goes in" one after another.
    for (var i = 0; i < 3; i++) {
      setState(() => _pulse = i);
      HapticFeedback.selectionClick();
      await Future<void>.delayed(const Duration(milliseconds: 160));
    }
    setState(() {
      _pulse = -1;
      _state = 1;
    });
    try {
      await widget.onSend();
      if (!mounted) return;
      unawaited(PairHaptics.success());
      setState(() => _state = 2);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _state = 0);
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text('$e'.replaceFirst('Bad state: ', '')), behavior: SnackBarBehavior.floating));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brand = CockpitColors.brand;
    final topics = widget.sections.where((s) => s.title != null).toList();
    final rows = [
      (Icons.notes_rounded, scheme.onSurface, 'Notes', '${topics.length} topics'),
      if (widget.durationMs > 0) (Icons.mic_none_rounded, brand.tertiary, 'Lecture transcript', '${(widget.durationMs / 60000).round()} min'),
      if (widget.photos > 0) (Icons.photo_outlined, brand.success, 'Board photos', '${widget.photos}'),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 44),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('STUDY STUDIO', style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.6, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text('Study from this note', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.3)),
          const SizedBox(height: 8),
          Text(
            'The whole note goes to Study Studio as material. Its AI reads it and builds what you need to study.',
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final s in topics) ...[
                Expanded(child: Container(height: 4, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(width: 3),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text('What goes in', style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          for (var i = 0; i < rows.length; i++)
            DecoratedBox(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant))),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    AnimatedScale(
                      scale: _pulse == i ? 1.35 : 1,
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutBack,
                      child: Icon(rows[i].$1, size: 19, color: rows[i].$2),
                    ),
                    const SizedBox(width: 12),
                    Text(rows[i].$3, style: theme.textTheme.bodyMedium),
                    const Spacer(),
                    Text(rows[i].$4, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w300)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: _send,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              height: 54,
              decoration: BoxDecoration(
                color: _state == 2 ? brand.success : scheme.primary,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_state == 1)
                      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    else
                      Icon(_state == 2 ? Icons.check_rounded : Icons.auto_awesome_rounded, size: 18, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      switch (_state) { 1 => 'Making your studio', 2 => 'Opening Study Studio', _ => 'Send to Study Studio' },
                      style: theme.textTheme.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text('Opens a new studio with this note as its material',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

class _Player extends StatelessWidget {
  const _Player({
    required this.quote,
    required this.at,
    required this.playing,
    required this.speed,
    required this.onToggle,
    required this.onSpeed,
    required this.onClose,
  });

  final String quote;
  final Duration at;
  final bool playing;
  final double speed;
  final VoidCallback onToggle;
  final VoidCallback onSpeed;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 30, offset: Offset(0, -6))],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onToggle,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: scheme.onSurface, shape: BoxShape.circle),
              child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: scheme.surface),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(quote.isEmpty ? 'Lecture' : '“$quote”',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                Text(_clock(at.inMilliseconds),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: CockpitColors.brand.tertiary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
              ],
            ),
          ),
          TextButton(onPressed: onSpeed, child: Text('${speed == speed.roundToDouble() ? speed.toInt() : speed}×')),
          IconButton(tooltip: 'Close', icon: const Icon(Icons.close_rounded, size: 18), onPressed: onClose),
        ],
      ),
    );
  }
}

/// A block's lecture time: final notes keep it under `provenance`.
int? _at(Map<String, dynamic> b) =>
    ((b['audioTsMs'] ?? (b['provenance'] as Map?)?['audioTsMs']) as num?)?.toInt();

String _clock(int ms) {
  final s = (ms ~/ 1000).clamp(0, 1 << 30);
  String two(int n) => n.toString().padLeft(2, '0');
  return s >= 3600 ? '${s ~/ 3600}:${two(s ~/ 60 % 60)}:${two(s % 60)}' : '${s ~/ 60}:${two(s % 60)}';
}
