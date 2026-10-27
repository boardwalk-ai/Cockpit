import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../application/notebook_book.dart';
import '../../application/session_providers.dart';
import '../../theme/octo_notes_theme.dart';
import 'notebooks_page.dart' show Notebook, notebookColor;

/// The book's colours: cream paper by day; by night warm dark paper.
class _BookPalette {
  const _BookPalette({
    required this.paper,
    required this.desk,
    required this.ink,
    required this.muted,
    required this.pencil,
    required this.rule,
    required this.edge,
    required this.subtle,
    required this.quote,
    required this.crease,
  });
  final Color paper, desk, ink, muted, pencil, rule, edge, subtle, quote, crease;

  static const light = _BookPalette(
    paper: Color(0xFFFFFAF0),
    desk: Color(0xFFE9E2D2),
    ink: Color(0xFF2B241B),
    muted: Color(0xFF8A7A5F),
    pencil: Color(0xFF1F3B73),
    rule: Color(0xFFE3D8C2),
    edge: Color(0xFFEFE6D3),
    subtle: Color(0xFF6B5B45),
    quote: Color(0xFF5A4A33),
    crease: Color(0xFF3C280A),
  );

  static const dark = _BookPalette(
    paper: Color(0xFF221F1B),
    desk: Color(0xFF121110),
    ink: Color(0xFFEDE6D8),
    muted: Color(0xFF9C9182),
    pencil: Color(0xFF9DB8FF),
    rule: Color(0xFF3A352E),
    edge: Color(0xFF2C2924),
    subtle: Color(0xFFBDB09C),
    quote: Color(0xFFDCCBA6),
    crease: Color(0xFF000000),
  );
}

/// Set as the reader is built (only one is open at a time).
_BookPalette _pal = _BookPalette.light;
const _red = Color(0xFFE11D2E);
const _gold = Color(0xFFE8B84B);
// The app's faces (cockpit_ui): Poppins for titles, Plus Jakarta Sans for
// text, Literata for the lecturer's words, Caveat for the Magic Pencil.
const _display = 'packages/cockpit_ui/Poppins';
const _sans = 'packages/cockpit_ui/PlusJakartaSans';
const _serif = 'packages/cockpit_ui/Literata';
const _hand = 'packages/cockpit_ui/Caveat';

enum _View { mine, clean, files }

/// A page of the book: the contents, or part of a chapter.
class _Page {
  const _Page.toc() : chapter = -1, items = const [], first = false, missing = false;
  const _Page(this.chapter, this.items, {this.first = false, this.missing = false});
  final int chapter;
  final List<BookItem> items;

  /// The chapter's first page (title, date, voice note).
  final bool first;

  /// Clean copy of a lecture that isn't finalized.
  final bool missing;
}

/// A notebook read like a book: its lectures are chapters, each in the
/// order it was written (typed lines, handwriting read on the phone, board
/// photos). My notes, the finalized Clean copy, and Files (everything, by
/// kind). Pages turn like paper; a lecture's recording plays in a small
/// player and the line written at that moment glows.
class NotebookReaderPage extends ConsumerStatefulWidget {
  const NotebookReaderPage({super.key, this.courseId, this.sessionId, this.loose = false, this.cover});

  /// The notebook tapped on a shelf: its cover opens before the pages show.
  final Notebook? cover;

  /// The notebook; null with [loose] is lectures without one.
  final String? courseId;

  /// Open at this lecture's chapter.
  final String? sessionId;
  final bool loose;

  @override
  ConsumerState<NotebookReaderPage> createState() => _NotebookReaderPageState();
}

class _NotebookReaderPageState extends ConsumerState<NotebookReaderPage> with SingleTickerProviderStateMixin {
  // The cover opening: grows (0–.2), swings open (.2–.7), then the page
  // spreads to the screen (.7–1) once the notebook has loaded.
  late final AnimationController _intro;
  bool _introOn = false;
  bool _swung = false;

  NotebookBook? _book;
  String? _error;
  _View _view = _View.mine;
  int _index = 0;
  List<_Page> _pages = const [];
  Size _laidOut = Size.zero;
  _View? _laidView;
  String? _goToSession;
  String? _goToItem;

  // The player.
  AudioPlayer? _player;
  int? _playing; // chapter
  Duration _pos = Duration.zero;
  Duration _len = Duration.zero;
  bool _isPlaying = false;
  double _speed = 1;
  bool _follow = true;
  final List<StreamSubscription<Object?>> _subs = [];
  // One per view: the old book stays a moment while the views cross-fade.
  final _flips = {for (final v in _View.values) v: GlobalKey<_FlipBookState>()};

  String get _bookmarkKey => 'octonotes.reader.${widget.courseId ?? 'loose'}';

  @override
  void initState() {
    super.initState();
    _goToSession = widget.sessionId;
    _intro = AnimationController(vsync: this);
    if (widget.cover != null && !MediaQueryData.fromView(WidgetsBinding.instance.platformDispatcher.views.first).disableAnimations) {
      _introOn = true;
      _intro.addListener(() {
        if (!_swung && _intro.value > .2) {
          _swung = true;
          HapticFeedback.mediumImpact();
        }
      });
      unawaited(_intro.animateTo(.7, duration: const Duration(milliseconds: 1500), curve: Curves.linear).then((_) => _finishIntro()));
    }
    unawaited(_load());
  }

  /// Spreads the opened page to the screen once there's something to show.
  void _finishIntro() {
    if (!_introOn || _intro.isAnimating || _intro.value < .7 || (_book == null && _error == null)) return;
    unawaited(_intro.animateTo(1, duration: const Duration(milliseconds: 650), curve: Curves.linear).then((_) {
      if (mounted) setState(() => _introOn = false);
    }));
  }

  @override
  void dispose() {
    _intro.dispose();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    unawaited(_player?.dispose());
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(octoNotesApiProvider);
    if (api == null) {
      setState(() => _error = 'Notebooks need the OctoNotes server.');
      return;
    }
    try {
      var courseId = widget.courseId;
      var loose = widget.loose;
      if (courseId == null && !loose && widget.sessionId != null) {
        courseId = (await api.sessionSnapshot(widget.sessionId!))['session']?['courseId'] as String?;
        loose = courseId == null;
      }
      final book = await loadNotebook(api, courseId: courseId, looseOnly: loose, colorOf: notebookColor);
      if (_goToSession == null) {
        try {
          final saved = (await SharedPreferences.getInstance()).getString(_bookmarkKey);
          if (saved != null && book.chapters.any((c) => c.session.id == saved)) _goToSession = saved;
        } on Object {
          // No bookmark: the contents.
        }
      }
      if (mounted) setState(() => _book = book);
    } on Object catch (e) {
      if (mounted) setState(() => _error = "Couldn't open this notebook: $e");
    }
    _finishIntro();
  }

  void _bookmark() {
    final c = _pages.elementAtOrNull(_index)?.chapter ?? -1;
    if (c < 0 || _book == null) return;
    final id = _book!.chapters[c].session.id;
    unawaited(SharedPreferences.getInstance().then((p) => p.setString(_bookmarkKey, id)).catchError((Object _) => false));
  }

  bool get _spread {
    final s = MediaQuery.sizeOf(context);
    return s.width > s.height && s.width >= 560;
  }

  // ── Layout: chapters into pages that fit ────────────────────────────────

  void _paginate(Size size) {
    final book = _book!;
    final pages = <_Page>[const _Page.toc()];
    final w = size.width - 40; // page padding
    final h = size.height - 44;
    for (var c = 0; c < book.chapters.length; c++) {
      final ch = book.chapters[c];
      final items = _view == _View.clean ? ch.clean : ch.mine;
      if (items == null) {
        pages.add(_Page(c, const [], first: true, missing: true));
        continue;
      }
      var used = _headerHeight(ch, w);
      var page = <BookItem>[];
      var first = true;
      for (final it in items) {
        final ih = _itemHeight(it, w);
        if (page.isNotEmpty && used + ih > h) {
          pages.add(_Page(c, page, first: first));
          first = false;
          page = [];
          used = 0;
        }
        page.add(it);
        used += ih;
      }
      pages.add(_Page(c, page, first: first));
    }
    if (_spread && pages.length.isOdd) pages.add(const _Page(-2, []));
    _pages = pages;
    _laidOut = size;
    _laidView = _view;
    // Land on the chapter (or line) asked for, keeping a spread's left page.
    final target = _goToItem != null
        ? pages.indexWhere((p) => p.items.any((i) => i.id == _goToItem))
        : _goToSession != null
            ? pages.indexWhere((p) => p.chapter >= 0 && book.chapters[p.chapter].session.id == _goToSession)
            : -1;
    if (target >= 0) _index = target;
    _goToSession = null;
    _goToItem = null;
    _index = _index.clamp(0, pages.length - 1);
    if (_spread) _index -= _index % 2;
  }

  double _headerHeight(BookChapter c, double w) {
    final t = _measure(c.session.title, _titleStyle, w) + 22;
    final voice = c.recordingId != null ? 52.0 : 0.0;
    final cta = c.session.status != 'finalized' && c.session.status != 'archived' ? 40.0 : 0.0;
    return t + voice + cta + 8;
  }

  double _itemHeight(BookItem it, double w) => switch (it.kind) {
        'photo' => 170,
        'formula' => 56,
        'heading' => _measure(it.text, _headingStyle, w) + 16,
        'quote' => _measure(it.text, _quoteStyle, w - 16) + 20,
        'pen' => _measure(it.text, _penStyle, w) + 26,
        'bullet' || 'check' => _measure(it.text, _bodyStyle, w - 24) + 6,
        _ => _measure(it.text, _bodyStyle, w) + 6,
      };

  static double _measure(String text, TextStyle style, double w) =>
      (TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout(maxWidth: math.max(40, w))).height;

  static TextStyle get _titleStyle => TextStyle(fontFamily: _display, fontSize: 21, fontWeight: FontWeight.w600, height: 1.2, color: _pal.ink);
  static TextStyle get _headingStyle => TextStyle(fontFamily: _display, fontSize: 15.5, fontWeight: FontWeight.w600, height: 1.35, color: _pal.ink);
  static TextStyle get _bodyStyle => TextStyle(fontFamily: _sans, fontSize: 14, height: 1.55, color: _pal.ink);
  static TextStyle get _quoteStyle => TextStyle(fontFamily: _serif, fontSize: 14.5, fontStyle: FontStyle.italic, height: 1.45, color: _pal.quote);
  static TextStyle get _penStyle => TextStyle(fontFamily: _hand, fontSize: 21, fontWeight: FontWeight.w500, height: 1.2, color: _pal.pencil);

  // ── Navigation ───────────────────────────────────────────────────────────

  void _setView(_View v) {
    if (v == _view) return;
    HapticFeedback.selectionClick();
    final c = _pages.elementAtOrNull(_index)?.chapter ?? -1;
    if (c >= 0) _goToSession = _book!.chapters[c].session.id;
    setState(() {
      _view = v;
      _laidOut = Size.zero; // lay out again
    });
  }

  void _openChapter(int c, {_View? view, String? item}) {
    HapticFeedback.selectionClick();
    setState(() {
      if (view != null) _view = view;
      _goToSession = _book!.chapters[c].session.id;
      _goToItem = item;
      _laidOut = Size.zero;
    });
  }

  void _turnTo(int i) => _flips[_view]!.currentState?.turnTo(i);

  // ── Player ───────────────────────────────────────────────────────────────

  Future<void> _play(int chapter) async {
    final api = ref.read(octoNotesApiProvider);
    final rec = _book!.chapters[chapter].recordingId;
    if (api == null || rec == null) return;
    HapticFeedback.lightImpact();
    if (_playing == chapter && _player != null) {
      _isPlaying ? await _player!.pause() : await _player!.resume();
      return;
    }
    try {
      final url = (await api.audioLink(rec))['url'] as String;
      final p = _player ??= _newPlayer();
      setState(() {
        _playing = chapter;
        _pos = Duration.zero;
        _len = Duration(milliseconds: _book!.chapters[chapter].durationMs);
      });
      await p.setPlaybackRate(_speed);
      await p.play(UrlSource(url));
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text("Couldn't play this recording: $e")));
      }
    }
  }

  AudioPlayer _newPlayer() {
    final p = AudioPlayer();
    _subs
      ..add(p.onPositionChanged.listen((d) {
        if (!mounted) return;
        setState(() => _pos = d);
        _followAlong();
      }))
      ..add(p.onDurationChanged.listen((d) => mounted ? setState(() => _len = d) : null))
      ..add(p.onPlayerStateChanged.listen((s) => mounted ? setState(() => _isPlaying = s == PlayerState.playing) : null));
    return p;
  }

  /// The line written at the moment playing, in the playing chapter.
  String? get _glowing {
    final c = _playing;
    if (c == null || !_follow || _view == _View.files) return null;
    final items = (_view == _View.clean ? _book!.chapters[c].clean : _book!.chapters[c].mine) ?? const [];
    final ms = _pos.inMilliseconds;
    String? id;
    for (final i in items) {
      if (i.atMs != null && i.atMs! <= ms) id = i.id;
    }
    return id;
  }

  void _followAlong() {
    final id = _glowing;
    if (id == null) return;
    final at = _pages.indexWhere((p) => p.items.any((i) => i.id == id));
    if (at < 0) return;
    final shown = _spread ? [_index, _index + 1] : [_index];
    if (!shown.contains(at)) _turnTo(at);
  }

  Future<void> _seek(int seconds) async {
    final p = _player;
    if (p == null) return;
    HapticFeedback.selectionClick();
    final to = _pos + Duration(seconds: seconds);
    await p.seek(to < Duration.zero ? Duration.zero : to);
  }

  Future<void> _setSpeed(double s) async {
    setState(() => _speed = s);
    await _player?.setPlaybackRate(s);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    _pal = Theme.of(context).brightness == Brightness.dark ? _BookPalette.dark : _BookPalette.light;
    final book = _book;
    final c = _pages.elementAtOrNull(_index)?.chapter ?? -1;
    final title = book == null ? 'Notebook' : (c >= 0 ? book.chapters[c].session.title : book.title);
    // Every bit of text in the book uses the app's own faces.
    // Chips, snack bars and buttons take the app theme's face too.
    return OctoNotesTheme.wrap(
      context: context,
      child: DefaultTextStyle.merge(
        style: TextStyle(fontFamily: _sans, color: _pal.ink),
        child: Stack(
          children: [
            _scaffold(book, title),
            if (_introOn) Positioned.fill(child: _CoverIntro(cover: widget.cover!, t: _intro)),
          ],
        ),
      ),
    );
  }

  Widget _scaffold(NotebookBook? book, String title) {
    return Scaffold(
      backgroundColor: _pal.desk,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _TopBar(
                  title: _view == _View.files ? '${book?.title ?? ''} · Files' : title,
                  onContents: book == null || _view == _View.files ? null : () => _turnTo(0),
                ),
                _ViewSwitch(view: _view, onChanged: _setView),
                const SizedBox(height: 8),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(12, 0, 12, _playing != null ? 132 : 12),
                    child: book == null
                        ? Center(
                            child: _error != null
                                ? Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: _pal.muted)))
                                : const CircularProgressIndicator(color: _red),
                          )
                        : LayoutBuilder(
                            // Pages are laid out once here, for the size the book has.
                            builder: (context, box) {
                              if (_view != _View.files) {
                                final page = Size(_spread ? box.maxWidth / 2 : box.maxWidth, box.maxHeight - 22);
                                if (page != _laidOut || _laidView != _view) _paginate(page);
                              }
                              return AnimatedSwitcher(
                                duration: const Duration(milliseconds: 380),
                                switchInCurve: Curves.easeOutCubic,
                                transitionBuilder: (child, a) => FadeTransition(
                                  opacity: a,
                                  child: SlideTransition(position: Tween(begin: const Offset(0, .03), end: Offset.zero).animate(a), child: child),
                                ),
                                child: _view == _View.files
                                    ? _FilesView(key: const ValueKey('files'), book: book, onOpen: _openFile, playing: _playing)
                                    : Column(
                                        key: ValueKey(_view),
                                        children: [
                                          Expanded(
                                            child: _FlipBook(
                                              key: _flips[_view],
                                              count: _pages.length,
                                              index: _index,
                                              spread: _spread,
                                              page: _pageAt,
                                              onIndex: (i) {
                                                setState(() => _index = i);
                                                _bookmark();
                                              },
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(_footer, style: TextStyle(fontSize: 11, color: _pal.muted)),
                                        ],
                                      ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedSlide(
                offset: _playing == null ? const Offset(0, 2) : Offset.zero,
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOutCubic,
                child: _MiniPlayer(
                  title: _playing == null ? '' : book!.chapters[_playing!].session.title,
                  subtitle: _playing == null ? '' : '${book!.title} · ${chapterDate(book.chapters[_playing!])}',
                  color: book?.color ?? _red,
                  playing: _isPlaying,
                  position: _pos,
                  length: _len,
                  speed: _speed,
                  follow: _follow,
                  onPlay: () => _playing == null ? null : _play(_playing!),
                  onSeek: (d) => _player?.seek(d),
                  onBack: () => _seek(-15),
                  onForward: () => _seek(15),
                  onSpeed: _setSpeed,
                  onFollow: () {
                    HapticFeedback.selectionClick();
                    setState(() => _follow = !_follow);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _footer {
    if (_index == 0) return 'Contents';
    final last = _pages.lastIndexWhere((p) => p.chapter >= 0);
    return _spread ? 'pages $_index–${math.min(_index + 1, last)} of $last' : 'page $_index of $last';
  }

  Widget _pageAt(int i, {required bool left}) {
    final p = _pages.elementAtOrNull(i);
    if (p == null || p.chapter == -2) return const SizedBox.expand();
    if (p.chapter == -1) {
      return _ContentsPage(
        book: _book!,
        onChapter: (c) {
          final at = _pages.indexWhere((x) => x.chapter == c);
          if (at >= 0) _turnTo(at);
        },
        onManage: widget.courseId == null ? null : () => context.push('/notes/notebooks?manage=${widget.courseId}'),
      );
    }
    final c = _book!.chapters[p.chapter];
    return _ChapterPage(
      chapter: c,
      page: p,
      playing: _playing == p.chapter && _isPlaying,
      progress: _playing == p.chapter && _len.inMilliseconds > 0 ? _pos.inMilliseconds / _len.inMilliseconds : 0,
      glowing: _playing == p.chapter ? _glowing : null,
      onPlay: () => _play(p.chapter),
      onFinalize: () => context.push('/notes/finalize?id=${c.session.id}'),
      onLive: () => context.push('/notes/session?id=${c.session.id}&role=solo&record=0'),
    );
  }

  Future<void> _openFile(BookFile f) async {
    switch (f.kind) {
      case 'recording':
        await _play(f.chapter);
      case 'text':
        _openChapter(f.chapter, view: _View.mine);
      case 'clean':
        _openChapter(f.chapter, view: _View.clean);
      case 'handwriting' || 'formula':
        _openChapter(f.chapter, view: _View.mine, item: f.item?.id);
      case 'photo' || 'slide':
        if (f.materialId != null) await _showImage(f.materialId!, f.title);
    }
  }

  Future<void> _showImage(String materialId, String title) async {
    HapticFeedback.selectionClick();
    final api = ref.read(octoNotesApiProvider);
    if (api == null) return;
    String? url;
    try {
      url = (await api.materialImage(materialId, 1))['url'] as String?;
    } on Object {
      url = null;
    }
    if (!mounted) return;
    if (url == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(behavior: SnackBarBehavior.floating, content: Text("This file isn't ready to show yet.")));
      return;
    }
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: InteractiveViewer(maxScale: 5, child: Center(child: Image.network(url!, fit: BoxFit.contain))),
      ),
    );
  }
}

// ===========================================================================
// Chrome
// ===========================================================================

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, this.onContents});
  final String title;
  final VoidCallback? onContents;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back',
              color: _pal.ink,
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () {
                HapticFeedback.lightImpact();
                context.canPop() ? context.pop() : context.go('/notes/notebooks');
              },
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(title,
                    key: ValueKey(title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: _display, fontSize: 15, fontWeight: FontWeight.w600, color: _pal.ink)),
              ),
            ),
            if (onContents != null)
              IconButton(
                tooltip: 'Contents',
                color: _pal.ink,
                icon: const Icon(Icons.format_list_bulleted_rounded),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  onContents!();
                },
              ),
            // The bookmark ribbon.
            Container(
              width: 13,
              height: 40,
              margin: const EdgeInsets.only(right: 18, bottom: 8),
              decoration: const ShapeDecoration(color: _red, shape: _RibbonShape()),
            ),
          ],
        ),
      );
}

class _RibbonShape extends ShapeBorder {
  const _RibbonShape();
  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => getOuterPath(rect);
  @override
  Path getOuterPath(Rect r, {TextDirection? textDirection}) => Path()
    ..moveTo(r.left, r.top)
    ..lineTo(r.right, r.top)
    ..lineTo(r.right, r.bottom)
    ..lineTo(r.center.dx, r.bottom - r.height * .18)
    ..lineTo(r.left, r.bottom)
    ..close();
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}
  @override
  ShapeBorder scale(double t) => this;
}

/// My notes · Clean copy · Files, with a pill that springs between them.
class _ViewSwitch extends StatelessWidget {
  const _ViewSwitch({required this.view, required this.onChanged});
  final _View view;
  final ValueChanged<_View> onChanged;

  static const _labels = {_View.mine: 'My notes', _View.clean: 'Clean copy', _View.files: 'Files'};

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: _pal.ink.withValues(alpha: .07), borderRadius: BorderRadius.circular(99)),
        child: LayoutBuilder(
          builder: (context, _) {
            const w = 96.0;
            return SizedBox(
              width: w * 3,
              height: 30,
              child: Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeOutBack,
                    left: w * view.index,
                    top: 0,
                    bottom: 0,
                    width: w,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _pal.paper,
                        borderRadius: BorderRadius.circular(99),
                        boxShadow: [BoxShadow(color: _pal.crease.withValues(alpha: .12), blurRadius: 6, offset: Offset(0, 2))],
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (final v in _View.values)
                        Expanded(
                          child: Semantics(
                            button: true,
                            selected: v == view,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => onChanged(v),
                              child: Center(
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 250),
                                  // It replaces the inherited style, so the face is named here.
                                  style: TextStyle(
                                    fontFamily: _sans,
                                    fontSize: 12,
                                    fontWeight: v == view ? FontWeight.w600 : FontWeight.w400,
                                    color: v == view ? _pal.ink : _pal.subtle,
                                  ),
                                  child: Text(_labels[v]!),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      );
}

/// The player: a dark capsule with a turning disc in the notebook's colour,
/// the play button ringed by how far in it is, and the waveform to scrub.
/// A tap opens it into a sheet with skips, speeds and follow along.
class _MiniPlayer extends StatefulWidget {
  const _MiniPlayer({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.playing,
    required this.position,
    required this.length,
    required this.speed,
    required this.follow,
    required this.onPlay,
    required this.onSeek,
    required this.onBack,
    required this.onForward,
    required this.onSpeed,
    required this.onFollow,
  });
  final String title, subtitle;
  final Color color;
  final bool playing;
  final Duration position, length;
  final double speed;
  final bool follow;
  final VoidCallback onPlay, onBack, onForward, onFollow;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<double> onSpeed;

  @override
  State<_MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<_MiniPlayer> with SingleTickerProviderStateMixin {
  late final _disc = AnimationController(vsync: this, duration: const Duration(seconds: 6));
  bool _open = false;
  double? _scrub; // 0..1 while the finger is on the waveform

  @override
  void didUpdateWidget(_MiniPlayer old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_disc.isAnimating) _disc.repeat();
    if (!widget.playing && _disc.isAnimating) _disc.stop();
  }

  @override
  void dispose() {
    _disc.dispose();
    super.dispose();
  }

  double get _progress {
    final l = widget.length.inMilliseconds;
    return _scrub ?? (l == 0 ? 0 : (widget.position.inMilliseconds / l).clamp(0, 1).toDouble());
  }

  String _t(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  void _scrubTo(double x, double w) => setState(() => _scrub = (x / w).clamp(0.0, 1.0));

  void _endScrub() {
    final f = _scrub;
    if (f == null) return;
    HapticFeedback.selectionClick();
    widget.onSeek(Duration(milliseconds: (widget.length.inMilliseconds * f).round()));
    setState(() => _scrub = null);
  }

  @override
  Widget build(BuildContext context) {
    const muted = Color(0xFFA8A39A);
    final at = Duration(milliseconds: (widget.length.inMilliseconds * _progress).round());
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _open = !_open);
      },
      onVerticalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v.abs() > 200) setState(() => _open = v < 0);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
        margin: EdgeInsets.fromLTRB(_open ? 0 : 12, 0, _open ? 0 : 12, _open ? 0 : 12),
        padding: EdgeInsets.fromLTRB(14, _open ? 10 : 10, 14, _open ? 22 : 12),
        decoration: BoxDecoration(
          color: const Color(0xFF18191B),
          borderRadius: _open ? const BorderRadius.vertical(top: Radius.circular(26)) : BorderRadius.circular(24),
          boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 30, offset: Offset(0, 14))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedOpacity(
              opacity: _open ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: Container(
                width: 34,
                height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(color: const Color(0xFF3A3B3E), borderRadius: BorderRadius.circular(4)),
              ),
            ),
            Row(
              children: [
                RotationTransition(
                  turns: _disc,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(colors: [widget.color, _gold, widget.color]),
                    ),
                    child: Center(
                      child: Container(width: 12, height: 12, decoration: const BoxDecoration(color: Color(0xFF18191B), shape: BoxShape.circle)),
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: _display, fontSize: 13.5, fontWeight: FontWeight.w500, color: Colors.white)),
                      Text(widget.subtitle,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: _sans, fontSize: 11, color: muted)),
                    ],
                  ),
                ),
                Semantics(
                  button: true,
                  label: widget.playing ? 'Pause' : 'Play',
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      widget.onPlay();
                    },
                    child: SizedBox(
                      width: 50,
                      height: 50,
                      child: CustomPaint(
                        painter: _Ring(_progress),
                        child: Center(
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                              child: Icon(widget.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  key: ValueKey(widget.playing), color: const Color(0xFF18191B), size: 24),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, box) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _scrubTo(d.localPosition.dx, box.maxWidth),
                onTapUp: (_) => _endScrub(),
                onHorizontalDragUpdate: (d) => _scrubTo(d.localPosition.dx, box.maxWidth),
                onHorizontalDragEnd: (_) => _endScrub(),
                child: SizedBox(height: 32, width: double.infinity, child: CustomPaint(painter: _Scrub(_progress, widget.playing))),
              ),
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                Text(_t(at), style: const TextStyle(fontFamily: _sans, fontSize: 10.5, color: muted, fontFeatures: [FontFeature.tabularFigures()])),
                const Spacer(),
                Text('−${_t(widget.length - at)}',
                    style: const TextStyle(fontFamily: _sans, fontSize: 10.5, color: muted, fontFeatures: [FontFeature.tabularFigures()])),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              child: !_open
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _RoundSkip(label: '−15', onTap: widget.onBack),
                          Row(children: [
                            for (final s in const [1.0, 1.5, 2.0])
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  widget.onSpeed(s);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  margin: const EdgeInsets.symmetric(horizontal: 2),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: widget.speed == s ? _gold : const Color(0xFF26272A),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text('${s == s.roundToDouble() ? s.toInt() : s}×',
                                      style: TextStyle(
                                        fontFamily: _sans,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: widget.speed == s ? const Color(0xFF2A1C00) : const Color(0xFFCFCAC0),
                                      )),
                                ),
                              ),
                          ]),
                          GestureDetector(
                            onTap: widget.onFollow,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 250),
                              opacity: widget.follow ? 1 : .4,
                              child: const Column(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.auto_stories_rounded, size: 18, color: _gold),
                                Text('Follow', style: TextStyle(fontFamily: _sans, fontSize: 10.5, color: _gold)),
                              ]),
                            ),
                          ),
                          _RoundSkip(label: '+15', onTap: widget.onForward),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundSkip extends StatelessWidget {
  const _RoundSkip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF333436))),
          child: Text(label, style: const TextStyle(fontFamily: _sans, fontSize: 12, fontWeight: FontWeight.w600, color: _gold)),
        ),
      );
}

/// How far in, as a gold ring round the play button.
class _Ring extends CustomPainter {
  _Ring(this.p);
  final double p;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - 1.5);
    canvas.drawArc(r, 0, math.pi * 2, false, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = const Color(0xFF3A3B3E));
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * p, false,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeCap = StrokeCap.round..color = _gold);
  }

  @override
  bool shouldRepaint(_Ring old) => old.p != p;
}

/// The recording's shape: played part gold, the rest faint, a knob at the head.
class _Scrub extends CustomPainter {
  _Scrub(this.p, this.playing);
  final double p;
  final bool playing;

  @override
  void paint(Canvas canvas, Size size) {
    const step = 4.0;
    final n = (size.width / step).floor();
    for (var i = 0; i < n; i++) {
      final h = 3 + (math.sin(i * .61) * math.sin(i * .17 + 1)).abs() * (size.height - 8);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(i * step + 1.25, size.height / 2), width: 2.5, height: h), const Radius.circular(1.2)),
        Paint()..color = i / n < p ? _gold : Colors.white.withValues(alpha: .18),
      );
    }
    final x = (size.width * p).clamp(0.0, size.width);
    canvas.drawCircle(Offset(x, size.height / 2), 5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_Scrub old) => old.p != p || old.playing != playing;
}

// ===========================================================================
// Pages
// ===========================================================================

class _Paper extends StatelessWidget {
  const _Paper({required this.child, this.left = false});
  final Widget child;
  final bool left;

  @override
  Widget build(BuildContext context) {
    final r = left
        ? const BorderRadius.horizontal(left: Radius.circular(14), right: Radius.circular(3))
        : const BorderRadius.horizontal(left: Radius.circular(3), right: Radius.circular(14));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _pal.paper,
        borderRadius: r,
        boxShadow: [
          BoxShadow(color: _pal.rule, offset: Offset(1, 1)),
          BoxShadow(color: _pal.edge, offset: Offset(3, 3)),
          BoxShadow(color: Color(0x1F000000), offset: Offset(4, 5), blurRadius: 10),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: Stack(
          children: [
            Positioned.fill(child: Padding(padding: const EdgeInsets.fromLTRB(22, 16, 18, 12), child: child)),
            // The gutter's shadow on the spine side.
            Positioned(
              top: 0,
              bottom: 0,
              left: left ? null : 0,
              right: left ? 0 : null,
              width: 14,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: left ? Alignment.centerRight : Alignment.centerLeft,
                      end: left ? Alignment.centerLeft : Alignment.centerRight,
                      colors: [_pal.crease.withValues(alpha: .14), _pal.crease.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContentsPage extends StatelessWidget {
  const _ContentsPage({required this.book, required this.onChapter, this.onManage});
  final NotebookBook book;
  final ValueChanged<int> onChapter;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(book.title, style: _NotebookReaderPageState._titleStyle),
          const SizedBox(height: 2),
          Text('${book.code != null ? '${book.code} · ' : ''}${book.chapters.length} lectures', style: TextStyle(fontSize: 11, color: _pal.muted)),
          const SizedBox(height: 10),
          if (book.chapters.isEmpty)
            Text('No lectures in this notebook yet.', style: TextStyle(color: _pal.muted))
          else
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (var i = 0; i < book.chapters.length; i++)
                    InkWell(
                      onTap: () => onChapter(i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _pal.rule))),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(book.chapters[i].session.title, style: _NotebookReaderPageState._headingStyle.copyWith(fontSize: 15)),
                                  if (book.chapters[i].headings.isNotEmpty)
                                    Text(book.chapters[i].headings.join(' · '),
                                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: _pal.muted)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(chapterDate(book.chapters[i]), style: TextStyle(fontSize: 11, color: _pal.muted)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (onManage != null)
            TextButton.icon(
              onPressed: onManage,
              style: TextButton.styleFrom(foregroundColor: _pal.muted, padding: EdgeInsets.zero),
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: const Text('Manage lectures'),
            ),
        ],
      );
}

class _ChapterPage extends StatelessWidget {
  const _ChapterPage({
    required this.chapter,
    required this.page,
    required this.playing,
    required this.progress,
    required this.glowing,
    required this.onPlay,
    required this.onFinalize,
    required this.onLive,
  });
  final BookChapter chapter;
  final _Page page;
  final bool playing;
  final double progress;
  final String? glowing;
  final VoidCallback onPlay, onFinalize, onLive;

  @override
  Widget build(BuildContext context) {
    final s = chapter.session;
    final live = s.status == 'live' || s.status == 'paused' || s.status == 'draft';
    final ended = s.status == 'ended' || s.status == 'reviewing';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (page.first) ...[
          Text(s.title, style: _NotebookReaderPageState._titleStyle),
          const SizedBox(height: 2),
          Text(chapterDate(chapter), style: TextStyle(fontSize: 11, color: _pal.muted)),
          const SizedBox(height: 8),
          if (live || ended)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ActionChip(
                onPressed: live ? onLive : onFinalize,
                avatar: Icon(live ? Icons.fiber_manual_record_rounded : Icons.auto_awesome_rounded, size: 16, color: live ? _red : _gold),
                label: Text(live ? 'Back to live' : 'Finalize'),
                backgroundColor: (live ? _red : _gold).withValues(alpha: .12),
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
              ),
            ),
          if (chapter.recordingId != null) _VoiceNote(length: chapter.durationMs, playing: playing, progress: progress, onTap: onPlay),
        ],
        if (page.missing)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              live ? 'This lecture is still going.' : 'Not finalized yet. Finalize it to get a clean copy.',
              style: TextStyle(color: _pal.muted),
            ),
          ),
        for (final it in page.items) _ItemView(item: it, glow: it.id == glowing),
      ],
    );
  }
}

class _VoiceNote extends StatelessWidget {
  const _VoiceNote({required this.length, required this.playing, required this.progress, required this.onTap});
  final int length;
  final bool playing;
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Play the lecture',
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 42,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(color: _red.withValues(alpha: .07), borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(color: _red, shape: BoxShape.circle),
                  child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Expanded(child: SizedBox(height: 24, child: CustomPaint(painter: _Bars(progress)))),
                const SizedBox(width: 8),
                Text(minutes(length), style: const TextStyle(fontSize: 11, color: Color(0xFF8A5A3A))),
              ],
            ),
          ),
        ),
      );
}

class _Bars extends CustomPainter {
  _Bars(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final n = (size.width / 4).floor();
    for (var i = 0; i < n; i++) {
      final h = 4 + (math.sin(i * .7) * math.sin(i * .23)).abs() * (size.height - 6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(i * 4 + 1.25, size.height / 2), width: 2.5, height: h), const Radius.circular(1)),
        Paint()..color = i / n < progress ? _red : _red.withValues(alpha: .3),
      );
    }
  }

  @override
  bool shouldRepaint(_Bars old) => old.progress != progress;
}

class _ItemView extends StatelessWidget {
  const _ItemView({required this.item, required this.glow});
  final BookItem item;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final i = item;
    final child = switch (i.kind) {
      'heading' => Padding(padding: const EdgeInsets.only(top: 10, bottom: 2), child: Text(i.text, style: _NotebookReaderPageState._headingStyle)),
      'bullet' => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: EdgeInsets.fromLTRB(4, 9, 10, 0), child: CircleAvatar(radius: 2.5, backgroundColor: _pal.ink)),
          Expanded(child: Text(i.text, style: _NotebookReaderPageState._bodyStyle)),
        ]),
      'check' => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 3, right: 6),
            child: Icon(i.checked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, size: 17, color: i.checked ? const Color(0xFF3FB27F) : _pal.muted),
          ),
          Expanded(child: Text(i.text, style: _NotebookReaderPageState._bodyStyle)),
        ]),
      'quote' => Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.fromLTRB(10, 3, 4, 3),
          decoration: const BoxDecoration(border: Border(left: BorderSide(color: _gold, width: 3))),
          child: Text('“${i.text}”', style: _NotebookReaderPageState._quoteStyle),
        ),
      'pen' => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const _Tag(icon: Icons.edit_rounded, label: 'pencil'),
            Text(i.text, style: _NotebookReaderPageState._penStyle),
          ]),
        ),
      'formula' => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const _Tag(icon: Icons.functions_rounded, label: 'formula'),
            Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Math.tex(i.text,
                    textStyle: TextStyle(fontSize: 17, color: _pal.pencil),
                    onErrorFallback: (_) => Text(i.text, style: TextStyle(fontFamily: 'monospace', color: _pal.pencil))),
              ),
            ),
          ]),
        ),
      'photo' => _Photo(materialId: i.materialId),
      _ => Text(i.text, style: _NotebookReaderPageState._bodyStyle),
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: glow ? _gold.withValues(alpha: .28) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        boxShadow: glow ? [BoxShadow(color: _gold.withValues(alpha: .18), spreadRadius: 3)] : const [],
      ),
      child: child,
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(color: _pal.pencil.withValues(alpha: .08), borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: _pal.pencil),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 10, color: _pal.pencil)),
        ]),
      );
}

/// A board photo taped in, a little crooked.
class _Photo extends ConsumerStatefulWidget {
  const _Photo({required this.materialId});
  final String? materialId;

  @override
  ConsumerState<_Photo> createState() => _PhotoState();
}

class _PhotoState extends ConsumerState<_Photo> {
  String? _url;

  @override
  void initState() {
    super.initState();
    final api = ref.read(octoNotesApiProvider);
    if (api != null && widget.materialId != null) {
      unawaited(api.materialImage(widget.materialId!, 1).then((r) {
        if (mounted) setState(() => _url = r['url'] as String?);
      }).catchError((Object _) {}));
    }
  }

  @override
  Widget build(BuildContext context) => Center(
        child: Transform.rotate(
          angle: -.035,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 14),
            decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Color(0x2E000000), blurRadius: 14, offset: Offset(0, 6))]),
            child: SizedBox(
              width: 200,
              height: 130,
              child: _url == null
                  ? const ColoredBox(color: Color(0xFF2F4A3A), child: Icon(Icons.photo_outlined, color: Colors.white54))
                  : Image.network(_url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF2F4A3A))),
            ),
          ),
        ),
      );
}

// ===========================================================================
// Page turning
// ===========================================================================

/// Pages that turn like paper: the page's corner follows the finger and the
/// paper folds along the line between them, showing its back (the next left
/// page when the book lies open on its side). Let go past the spine and it
/// turns; before, it falls back. A tap on an edge turns with a soft arc.
class _FlipBook extends StatefulWidget {
  const _FlipBook({super.key, required this.count, required this.index, required this.spread, required this.page, required this.onIndex});
  final int count;
  final int index;
  final bool spread;
  final Widget Function(int i, {required bool left}) page;
  final ValueChanged<int> onIndex;

  @override
  State<_FlipBook> createState() => _FlipBookState();
}

class _FlipBookState extends State<_FlipBook> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this);
  }

  int _dir = 0; // 1 forward, -1 back, 0 still
  bool _top = false; // which corner turns
  Offset _p = Offset.zero; // where that corner is now
  Size _size = Size.zero; // one page
  int? _queued;
  double _dragX = 0;

  int get _step => widget.spread ? 2 : 1;
  Offset get _corner => Offset(_size.width, _top ? 0 : _size.height);
  Offset get _gone => Offset(-_size.width, _corner.dy);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Paper doesn't stretch: the corner stays within reach of the spine.
  Offset _reach(Offset p) {
    final w = _size.width, h = _size.height;
    final s = Offset(0, _corner.dy);
    var q = p;
    final d = q - s;
    if (d.distance > w) q = s + d / d.distance * w;
    final s2 = Offset(0, h - _corner.dy);
    final diag = math.sqrt(w * w + h * h);
    final d2 = q - s2;
    if (d2.distance > diag) q = s2 + d2 / d2.distance * diag;
    return q;
  }

  bool _begin(int dir, {bool top = false}) {
    final to = widget.index + dir * _step;
    if (_dir != 0 || to < 0 || to >= widget.count) return false;
    setState(() {
      _dir = dir;
      _top = top;
      _p = dir > 0 ? _corner : _gone;
    });
    return true;
  }

  /// Moves the corner to [target] along a soft arc, then settles the turn.
  Future<void> _glide(bool ok) async {
    final from = _p;
    final target = (ok ? _dir > 0 : _dir < 0) ? _gone : _corner;
    final lift = _size.height * .1 * (_top ? 1 : -1);
    final travel = (target.dx - from.dx).abs() / (2 * _size.width);
    _c.duration = Duration(milliseconds: (260 + 420 * travel).round());
    void tick() {
      final t = Curves.easeInOutCubic.transform(_c.value);
      setState(() => _p = Offset.lerp(from, target, t)! + Offset(0, math.sin(math.pi * t) * lift * travel));
    }

    _c.addListener(tick);
    await _c.forward(from: 0);
    _c.removeListener(tick);
    if (!mounted) return;
    if (ok) {
      HapticFeedback.selectionClick();
      widget.onIndex(widget.index + _dir * _step);
    }
    setState(() => _dir = 0);
    final q = _queued;
    _queued = null;
    if (q != null) WidgetsBinding.instance.addPostFrameCallback((_) => turnTo(q));
  }

  /// Turns to page [i]: one page turn, after a jump if it's further away.
  void turnTo(int i) {
    var target = i.clamp(0, widget.count - 1);
    if (widget.spread) target -= target % 2;
    if (target == widget.index) return;
    if (_dir != 0) {
      _queued = target;
      return;
    }
    final dir = target > widget.index ? 1 : -1;
    if ((target - widget.index).abs() > _step) {
      widget.onIndex(target - dir * _step);
      _queued = target;
      return;
    }
    if (_begin(dir)) unawaited(_glide(true));
  }

  @override
  void didUpdateWidget(_FlipBook old) {
    super.didUpdateWidget(old);
    final q = _queued;
    if (q != null && _dir == 0 && old.index != widget.index) {
      _queued = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => turnTo(q));
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final w = widget.spread ? box.maxWidth / 2 : box.maxWidth;
          _size = Size(w, box.maxHeight);
          final ox = widget.spread ? w : 0.0; // where the turning page starts
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              if (_dir != 0) return;
              final x = d.localPosition.dx / box.maxWidth;
              if (x > .75) turnTo(widget.index + _step);
              if (x < .25) turnTo(widget.index - _step);
            },
            onHorizontalDragStart: (d) => _dragX = d.localPosition.dx,
            onHorizontalDragUpdate: (d) {
              final dx = d.localPosition.dx - _dragX;
              if (_dir == 0 && (dx.abs() < 6 || !_begin(dx < 0 ? 1 : -1, top: d.localPosition.dy < box.maxHeight / 2))) return;
              if (_c.isAnimating) return;
              final base = _dir > 0 ? _size.width : -_size.width;
              setState(() => _p = _reach(Offset(base + 2 * dx, d.localPosition.dy)));
            },
            onHorizontalDragEnd: (d) {
              if (_dir == 0 || _c.isAnimating) return;
              final v = d.primaryVelocity ?? 0;
              final past = _dir > 0 ? _p.dx < _size.width * .2 : _p.dx > -_size.width * .2;
              unawaited(_glide(past || v * -_dir > 700));
            },
            child: widget.spread ? _spreadView(ox) : ClipRect(child: _turning(0)),
          );
        },
      );

  Widget _leaf(int i, {required bool left}) => _Paper(left: left, child: widget.page(i, left: left));

  static const _blank = _Paper(child: SizedBox.expand());

  /// The right-hand page area: the page under, the turning page cut along
  /// the fold, and the folded-over part showing the back of the paper.
  Widget _turning(double ox) {
    final i = widget.index;
    if (_dir == 0) return _leaf(widget.spread ? i + 1 : i, left: false);
    final spread = widget.spread;
    final front = _dir > 0 ? (spread ? i + 1 : i) : (spread ? i - 1 : i - 1);
    final under = _dir > 0 ? (spread ? i + 3 : i + 1) : (spread ? i + 1 : i);
    final back = spread ? (_dir > 0 ? i + 2 : i) : null;
    final f = _Fold(_corner, _p, _size);
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        _leaf(under, left: false),
        IgnorePointer(child: CustomPaint(painter: _UnderShade(f))),
        ClipPath(clipper: _PathClip(f.keep()), child: _leaf(front, left: false)),
        IgnorePointer(child: CustomPaint(painter: _FlapShadow(f))),
        ClipPath(
          clipper: _PathClip(f.flap()),
          child: Transform(transform: f.backMatrix(), child: back == null ? _blank : _leaf(back, left: true)),
        ),
        IgnorePointer(child: CustomPaint(painter: _FlapShade(f))),
      ],
    );
  }

  Widget _spreadView(double w) {
    final i = widget.index;
    // On a back turn the left page under is the one before.
    final left = _dir < 0 ? i - 2 : i;
    return Stack(
      children: [
        Positioned(left: 0, top: 0, bottom: 0, width: w, child: _leaf(left, left: true)),
        Positioned(left: w, top: 0, bottom: 0, width: w, child: _turning(w)),
      ],
    );
  }
}

/// The fold of a page whose corner [c] is held at [p]: the crease is the
/// line halfway between them, square to the line joining them.
class _Fold {
  _Fold(this.c, this.p, this.size) {
    final d = c - p;
    final len = d.distance;
    n = len < .001 ? const Offset(1, 0) : d / len;
    m = (c + p) / 2;
    lift = (len / (2 * size.width)).clamp(0.0, 1.0);
  }

  final Offset c, p;
  final Size size;
  late final Offset n; // toward the corner
  late final Offset m; // on the crease
  late final double lift; // 0 flat … 1 turned over

  double side(Offset x) => (x.dx - m.dx) * n.dx + (x.dy - m.dy) * n.dy;
  Offset reflect(Offset x) => x - n * (2 * side(x));

  List<Offset> get _rect => [Offset.zero, Offset(size.width, 0), Offset(size.width, size.height), Offset(0, size.height)];

  /// The page cut by the crease: the part kept ([folded] false) or folded.
  List<Offset> _cut(bool folded) {
    final out = <Offset>[];
    final pts = _rect;
    bool inside(Offset x) => folded ? side(x) > 0 : side(x) <= 0;
    for (var k = 0; k < pts.length; k++) {
      final a = pts[k], b = pts[(k + 1) % pts.length];
      final ia = inside(a), ib = inside(b);
      if (ia) out.add(a);
      if (ia != ib) {
        final sa = side(a), sb = side(b);
        out.add(a + (b - a) * (sa / (sa - sb)));
      }
    }
    return out;
  }

  Path _poly(List<Offset> pts) => pts.isEmpty ? Path() : (Path()..addPolygon(pts, true));
  Path keep() => _poly(_cut(false));
  Path flap() => _poly([for (final x in _cut(true)) reflect(x)]);

  /// Where the back of the paper lands: a page lying to the left of the
  /// spine (x from 0 to width, spine at the right), mirrored onto the flap.
  Matrix4 backMatrix() {
    final w = size.width;
    final a00 = 1 - 2 * n.dx * n.dx, a01 = -2 * n.dx * n.dy, a11 = 1 - 2 * n.dy * n.dy;
    final k = m.dx * n.dx + m.dy * n.dy;
    // Reflection across the crease after u → w − u (left page onto this one).
    return Matrix4(-a00, -a01, 0, 0, a01, a11, 0, 0, 0, 0, 1, 0, w * a00 + 2 * k * n.dx, w * a01 + 2 * k * n.dy, 0, 1);
  }
}

class _PathClip extends CustomClipper<Path> {
  _PathClip(this.path);
  final Path path;
  @override
  Path getClip(Size size) => path;
  @override
  bool shouldReclip(_PathClip old) => true;
}

/// The page under darkens near the crease as the paper lifts over it.
class _UnderShade extends CustomPainter {
  _UnderShade(this.f);
  final _Fold f;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.sin(math.pi * f.lift.clamp(0, 1));
    if (s <= 0) return;
    final reach = 40 + 60 * s;
    canvas
      ..save()
      ..clipPath(Path()..addPolygon(f._cut(true), true));
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          colors: [const Color(0xFF28190A).withValues(alpha: .42 * s), const Color(0x0028190A)],
        ).createShader(Rect.fromPoints(f.m, f.m + f.n * reach)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_UnderShade old) => true;
}

/// The folded flap's soft shadow on the page it lies over.
class _FlapShadow extends CustomPainter {
  _FlapShadow(this.f);
  final _Fold f;

  @override
  void paint(Canvas canvas, Size size) {
    final path = f.flap();
    final s = math.sin(math.pi * f.lift.clamp(0, 1));
    canvas.drawShadow(path, Colors.black.withValues(alpha: .5), 4 + 8 * s, false);
  }

  @override
  bool shouldRepaint(_FlapShadow old) => true;
}

/// Light on the curl: dark in the crease, a sheen, then the paper's back.
class _FlapShade extends CustomPainter {
  _FlapShade(this.f);
  final _Fold f;

  @override
  void paint(Canvas canvas, Size size) {
    final path = f.flap();
    final s = math.sin(math.pi * f.lift.clamp(0, 1));
    final depth = 30 + 120 * s;
    canvas
      ..save()
      ..clipPath(path)
      ..drawRect(
        Rect.fromLTWH(-size.width * 2, -size.height, size.width * 5, size.height * 3),
        Paint()
          ..shader = LinearGradient(
            colors: [
              const Color(0xFF503214).withValues(alpha: .28),
              Colors.white.withValues(alpha: .38 * s),
              Colors.white.withValues(alpha: 0),
              const Color(0xFF503214).withValues(alpha: .08),
            ],
            stops: const [0, .25, .6, 1],
          ).createShader(Rect.fromPoints(f.m, f.m - f.n * depth)),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_FlapShade old) => true;
}

// ===========================================================================
// Files
// ===========================================================================

class _FilesView extends StatefulWidget {
  const _FilesView({super.key, required this.book, required this.onOpen, this.playing});
  final NotebookBook book;
  final ValueChanged<BookFile> onOpen;
  final int? playing;

  @override
  State<_FilesView> createState() => _FilesViewState();
}

class _FilesViewState extends State<_FilesView> {
  String _filter = 'all';

  List<(String, String, IconData, Color)> get _kinds => [
    ('text', 'Text', Icons.description_outlined, _pal.quote),
    ('clean', 'Clean copies', Icons.auto_awesome_outlined, Color(0xFFB0841A)),
    ('recording', 'Recordings', Icons.mic_none_rounded, _red),
    ('photo', 'Photos', Icons.photo_outlined, Color(0xFF2F6B4F)),
    ('handwriting', 'Handwriting', Icons.edit_outlined, _pal.pencil),
    ('formula', 'Formulas', Icons.functions_rounded, Color(0xFF7A4FBF)),
    ('slide', 'Slides', Icons.slideshow_outlined, Color(0xFFB06A10)),
  ];

  @override
  Widget build(BuildContext context) {
    final files = widget.book.files;
    final kinds = [for (final k in _kinds) if (files.any((f) => f.kind == k.$1)) k];
    var n = 0;
    return DecoratedBox(
      decoration: BoxDecoration(color: _pal.paper, borderRadius: BorderRadius.circular(14)),
      child: files.isEmpty
          ? Center(child: Text('Nothing in this notebook yet.', style: TextStyle(color: _pal.muted)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
              children: [
                SizedBox(
                  height: 32,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _chip('all', 'All', files.length),
                      for (final k in kinds) _chip(k.$1, k.$2, files.where((f) => f.kind == k.$1).length),
                    ],
                  ),
                ),
                for (final k in kinds)
                  if (_filter == 'all' || _filter == k.$1) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 14, bottom: 2),
                      child: Row(children: [
                        Icon(k.$3, size: 17, color: k.$4),
                        const SizedBox(width: 8),
                        Text(k.$2, style: _NotebookReaderPageState._headingStyle.copyWith(fontSize: 14)),
                        const SizedBox(width: 6),
                        Text('${files.where((f) => f.kind == k.$1).length}', style: TextStyle(fontSize: 11, color: _pal.muted)),
                      ]),
                    ),
                    for (final f in files.where((f) => f.kind == k.$1)) _row(f, k.$3, k.$4, n++),
                  ],
              ],
            ),
    );
  }

  Widget _chip(String k, String label, int count) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _filter = k);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.symmetric(horizontal: 11),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: _filter == k ? _pal.ink : _pal.ink.withValues(alpha: .07), borderRadius: BorderRadius.circular(99)),
            child: Text('$label  $count', style: TextStyle(fontSize: 12, color: _filter == k ? _pal.paper : _pal.subtle)),
          ),
        ),
      );

  Widget _row(BookFile f, IconData icon, Color color, int n) => TweenAnimationBuilder<double>(
        key: ValueKey('${f.kind}${f.title}${f.chapter}$_filter'),
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 320 + 30 * math.min(n, 12)),
        curve: Curves.easeOutCubic,
        builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, (1 - t) * 10), child: child)),
        child: InkWell(
          onTap: () => widget.onOpen(f),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _pal.rule))),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: f.kind == 'recording' ? _red : color.withValues(alpha: .1),
                    shape: f.kind == 'recording' ? BoxShape.circle : BoxShape.rectangle,
                    borderRadius: f.kind == 'recording' ? null : BorderRadius.circular(9),
                  ),
                  child: Icon(
                    f.kind == 'recording' ? (widget.playing == f.chapter ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded) : icon,
                    size: 18,
                    color: f.kind == 'recording' ? Colors.white : color,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      f.kind == 'formula'
                          ? SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Math.tex(f.title,
                                  textStyle: TextStyle(fontSize: 14, color: _pal.pencil),
                                  onErrorFallback: (_) => Text(f.title, style: TextStyle(color: _pal.pencil))),
                            )
                          : Text(f.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: f.kind == 'handwriting' ? _NotebookReaderPageState._penStyle.copyWith(fontSize: 14) : TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _pal.ink)),
                      Text(f.detail, style: TextStyle(fontSize: 11, color: _pal.muted)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: _pal.muted),
              ],
            ),
          ),
        ),
      );
}


// ===========================================================================
// Opening the notebook
// ===========================================================================

/// The notebook comes forward, its cover swings open on the spine, and the
/// first page spreads to fill the screen.
class _CoverIntro extends StatelessWidget {
  const _CoverIntro({required this.cover, required this.t});
  final Notebook cover;
  final Animation<double> t;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: t,
        builder: (context, _) => LayoutBuilder(builder: (context, box) {
          final v = t.value;
          final grow = Curves.easeOutCubic.transform((v / .2).clamp(0, 1));
          final swing = Curves.easeInOutCubic.transform(((v - .2) / .5).clamp(0, 1));
          final spread = Curves.easeInOutCubic.transform(((v - .7) / .3).clamp(0, 1));
          final w = math.min(260.0, box.maxWidth * .68);
          final h = w * 1.45;
          final book = Rect.fromCenter(center: box.biggest.center(Offset.zero), width: w, height: h);
          final page = Rect.lerp(book, Offset.zero & box.biggest, spread)!;
          final scale = .55 + .45 * grow;
          final angle = -math.pi * .92 * swing;
          final showBack = angle.abs() > math.pi / 2;
          return IgnorePointer(
            child: Opacity(
              opacity: 1 - Curves.easeIn.transform(((v - .86) / .14).clamp(0, 1)),
              child: Stack(
                children: [
                  // The room behind the book, lifting away as the page spreads.
                  Positioned.fill(
                    child: Opacity(
                      opacity: 1 - spread,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(center: Alignment(0, -.6), radius: 1.2, colors: [Color(0xFF2A2016), Color(0xFF120D08)]),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fromRect(
                    rect: page,
                    child: Transform.scale(
                      scale: spread > 0 ? 1 : scale,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // The first page, under the cover.
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: _pal.paper,
                                borderRadius: BorderRadius.lerp(const BorderRadius.horizontal(left: Radius.circular(3), right: Radius.circular(12)), BorderRadius.zero, spread),
                                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .45 * (1 - spread)), blurRadius: 30, offset: const Offset(0, 16))],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(22, 20, 18, 16),
                                child: Opacity(
                                  opacity: swing,
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(cover.code ?? 'Notebook', style: TextStyle(fontFamily: _sans, fontSize: 11, color: _pal.muted)),
                                    Text(cover.name, maxLines: 2, style: _NotebookReaderPageState._titleStyle),
                                  ]),
                                ),
                              ),
                            ),
                          ),
                          // A shadow sweeps over the page as the cover lifts.
                          Positioned.fill(
                            child: Opacity(
                              opacity: math.sin(math.pi * swing) * .5,
                              child: const DecoratedBox(
                                decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF28190A), Color(0x0028190A)], stops: [0, .7])),
                              ),
                            ),
                          ),
                          if (swing < 1 && spread == 0)
                            Positioned.fill(
                              child: Transform(
                                alignment: Alignment.centerLeft,
                                transform: Matrix4.identity()
                                  ..setEntry(3, 2, .0012)
                                  ..rotateY(angle),
                                child: showBack ? _coverBack() : _coverFront(swing),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      );

  Widget _coverFront(double swing) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(3), right: Radius.circular(12)),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [cover.color, cover.deep]),
        ),
        child: Stack(
          children: [
            // The spine, and a sheen that runs across as it opens.
            Positioned(left: 0, top: 0, bottom: 0, width: 10, child: ColoredBox(color: Colors.black.withValues(alpha: .22))),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(3), right: Radius.circular(12)),
                  gradient: LinearGradient(
                    begin: Alignment(-1 + 3 * swing, -1),
                    end: Alignment(1 + 3 * swing, 1),
                    colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: .22), Colors.white.withValues(alpha: 0)],
                    stops: const [.3, .45, .6],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 22,
              right: 16,
              bottom: 22,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (cover.code != null)
                  Text(cover.code!, style: TextStyle(fontFamily: _sans, fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: .8))),
                Text(cover.name, maxLines: 3, style: const TextStyle(fontFamily: _display, fontSize: 24, height: 1.1, fontWeight: FontWeight.w600, color: Colors.white)),
              ]),
            ),
          ],
        ),
      );

  Widget _coverBack() => DecoratedBox(
        decoration: BoxDecoration(
          color: _pal.edge,
          borderRadius: BorderRadius.horizontal(left: Radius.circular(12), right: Radius.circular(3)),
        ),
      );
}
