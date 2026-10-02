import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/gw_api.dart';
import 'mobile_motion.dart';
import 'mobile_theme.dart';

/// The editor is a white page, like paper, after the dark chat.
abstract final class _Paper {
  static const background = Colors.white;
  static const ink = Color(0xFF1C1D1F);
  static const muted = Color(0xFF6B6E73);
  static const rule = Color(0xFFE8E8EA);
}

/// Opens the read-only document view over the chat.
Future<void> openGwDocumentViewer(
  BuildContext context, {
  required GwApi api,
  required String projectId,
  required String title,
}) {
  gwHaptic(GwHaptic.medium);
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, _, _) =>
          GwDocumentViewer(api: api, projectId: projectId, title: title),
      transitionsBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

/// The essay as it stands, following the document stream: while the agent
/// writes, its text arrives as it is written. Editing comes with the real
/// editor (phase 3).
class GwDocumentViewer extends StatefulWidget {
  const GwDocumentViewer({
    super.key,
    required this.api,
    required this.projectId,
    required this.title,
  });

  final GwApi api;
  final String projectId;
  final String title;

  @override
  State<GwDocumentViewer> createState() => _GwDocumentViewerState();
}

class _GwDocumentViewerState extends State<GwDocumentViewer> {
  final ScrollController _scroll = ScrollController();
  StreamSubscription<Map<String, dynamic>>? _subscription;
  Timer? _retry;

  bool _loaded = false;
  bool _locked = false;
  bool _offline = false;
  String _title = '';
  String _body = '';
  String _bibliography = '';
  int _words = 0;

  @override
  void initState() {
    super.initState();
    _title = widget.title;
    _connect();
  }

  void _connect() {
    _retry?.cancel();
    _subscription?.cancel();
    _subscription = widget.api
        .documentEvents(widget.projectId)
        .listen(_onEvent, onError: (_) => _lost(), onDone: _lost);
  }

  void _lost() {
    if (!mounted) return;
    setState(() => _offline = true);
    _retry = Timer(const Duration(seconds: 2), _connect);
  }

  void _onEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final nearBottom =
        _scroll.hasClients &&
        _scroll.position.maxScrollExtent - _scroll.position.pixels < 160;
    setState(() {
      _offline = false;
      switch (event['type']) {
        case 'snapshot':
          _loaded = true;
          _locked = event['locked'] == true;
          final title = event['title']?.toString() ?? '';
          if (title.isNotEmpty) _title = title;
          _body = event['body']?.toString() ?? '';
          _bibliography = event['bibliography']?.toString() ?? '';
          _words = (event['wordCount'] as num?)?.toInt() ?? _countWords(_body);
        case 'delta':
          _body += event['text']?.toString() ?? '';
          _words = _countWords(_body);
        case 'unlocked':
          _locked = false;
      }
    });
    // Follow the text as it is written, unless the reader scrolled up.
    if (_locked && nearBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  static int _countWords(String text) =>
      text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  @override
  void dispose() {
    _retry?.cancel();
    _subscription?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paragraphs = _body
        .split(RegExp(r'\n\s*\n'))
        .where((p) => p.trim().isNotEmpty)
        .toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: _Paper.background,
        body: SafeArea(
          child: Column(
            children: [
              _ViewerBar(
                title: _title,
                locked: _locked,
                words: _words,
                offline: _offline,
              ),
              Expanded(
                child: !_loaded
                    ? const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _Paper.muted,
                        ),
                      )
                    : Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: ListView(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(22, 12, 22, 40),
                            children: [
                              Text(
                                _title,
                                style: const TextStyle(
                                  color: _Paper.ink,
                                  fontSize: 22,
                                  height: 1.25,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (paragraphs.isEmpty)
                                Text(
                                  _locked
                                      ? 'GhostWriter is about to start writing…'
                                      : 'Nothing written yet.',
                                  style: kGwBody.copyWith(color: _Paper.muted),
                                ),
                              for (final (i, p) in paragraphs.indexed)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: _Paragraph(
                                    text: p.trim(),
                                    caret:
                                        _locked && i == paragraphs.length - 1,
                                  ),
                                ),
                              if (_bibliography.trim().isNotEmpty) ...[
                                const SizedBox(height: 18),
                                Text(
                                  'REFERENCES',
                                  style: kGwLabel.copyWith(color: _Paper.muted),
                                ),
                                const SizedBox(height: 10),
                                SelectableText(
                                  _bibliography.trim(),
                                  style: kGwBody.copyWith(
                                    fontSize: 13.5,
                                    height: 1.6,
                                    color: _Paper.ink,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
              ),
              _Footer(locked: _locked),
            ],
          ),
        ),
      ),
    );
  }
}

class _Paragraph extends StatelessWidget {
  const _Paragraph({required this.text, required this.caret});

  final String text;
  final bool caret;

  @override
  Widget build(BuildContext context) {
    final style = kGwBody.copyWith(
      fontSize: 16,
      height: 1.7,
      color: _Paper.ink,
    );
    if (!caret) return SelectableText(text, style: style);
    return Text.rich(
      TextSpan(
        text: text,
        children: const [
          WidgetSpan(alignment: PlaceholderAlignment.middle, child: _Caret()),
        ],
      ),
      style: style,
    );
  }
}

class _Caret extends StatefulWidget {
  const _Caret();

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _blink.value = 1;
    } else if (!_blink.isAnimating) {
      _blink.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _blink,
      child: Container(
        width: 8,
        height: 18,
        margin: const EdgeInsets.only(left: 3),
        decoration: BoxDecoration(
          color: GwColors.accent,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _ViewerBar extends StatelessWidget {
  const _ViewerBar({
    required this.title,
    required this.locked,
    required this.words,
    required this.offline,
  });

  final String title;
  final bool locked;
  final int words;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final (color, label) = offline
        ? (_Paper.muted, 'Reconnecting…')
        : locked
        ? (GwColors.accent, 'Writing · $words words')
        : (const Color(0xFF1E9E5A), '$words words');

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 14, 6),
      child: Row(
        children: [
          GwPressable(
            tooltip: 'Back to chat',
            onTap: () => Navigator.of(context).maybePop(),
            child: const SizedBox(
              width: kGwButton,
              height: kGwButton,
              child: Icon(
                Icons.arrow_back_rounded,
                color: _Paper.ink,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Text(
              'Editor',
              style: TextStyle(
                color: _Paper.ink,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withValues(alpha: 0.45)),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.locked});

  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      decoration: const BoxDecoration(
        color: _Paper.background,
        border: Border(top: BorderSide(color: _Paper.rule)),
      ),
      child: Row(
        children: [
          Icon(
            locked ? Icons.lock_clock_rounded : Icons.lock_outline_rounded,
            size: 16,
            color: _Paper.muted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              locked
                  ? 'Read-only while GhostWriter writes.'
                  : 'Read-only for now. Editing is coming soon.',
              style: kGwBody.copyWith(
                fontSize: 12.5,
                height: 1.3,
                color: _Paper.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
