import 'dart:async';
import 'dart:math' as math;

import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/open_session.dart';
import '../../application/session_providers.dart';
import '../../data/api/octo_notes_api.dart';
import '../../domain/notes_session.dart';
import '../../theme/octo_notes_theme.dart';
import '../new_session/new_session_dialog.dart';
import '../new_session/new_session_sheet.dart';

/// A course as a notebook: its pages are the lecture sessions.
class Notebook {
  const Notebook({required this.id, required this.name, this.code, required this.color});
  final String? id; // null: sessions without a course
  final String name;
  final String? code;
  final Color color;

  Color get deep => HSLColor.fromColor(color).withLightness((HSLColor.fromColor(color).lightness * 0.45).clamp(0, 1)).toColor();
}

const _palette = [Color(0xFFE11D2E), Color(0xFFE8B84B), Color(0xFF5B8DEF), Color(0xFF3FB27F), Color(0xFFF04E3E), Color(0xFF9B6BE8)];
const _topicColors = [Color(0xFFE11D2E), Color(0xFFE8B84B), Color(0xFF5B8DEF), Color(0xFF3FB27F), Color(0xFFF04E3E)];

/// A course's colour, or one from the palette when it has none.
Color notebookColor(String? v, int i) {
  final h = v?.replaceFirst('#', '');
  final n = h == null || h.length != 6 ? null : int.tryParse(h, radix: 16);
  return n == null ? _palette[i % _palette.length] : Color(0xFF000000 | n);
}

String _hexOf(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

enum _Filter { all, live, toFinalize, finalNotes }

bool _passes(_Filter f, NotesSession s) => switch (f) {
      _Filter.all => true,
      _Filter.live => const ['draft', 'live', 'paused'].contains(s.status),
      _Filter.toFinalize => const ['ended', 'reviewing'].contains(s.status),
      _Filter.finalNotes => const ['finalized', 'archived'].contains(s.status),
    };

/// Notebooks: every course as a notebook in a 3D shelf; open one and its
/// cover swings back on ruled pages, one per lecture. Search across all of
/// them, filter by where a lecture is, long-press a page to rename, move or
/// delete it.
class NotebooksPage extends ConsumerStatefulWidget {
  const NotebooksPage({super.key, this.manage});

  /// Open this notebook's lecture list (rename, move, delete) straight away.
  final String? manage;

  @override
  ConsumerState<NotebooksPage> createState() => _NotebooksPageState();
}

class _NotebooksPageState extends ConsumerState<NotebooksPage> {
  List<Notebook> _books = [];
  List<NotesSession> _sessions = [];
  bool _loading = true;
  String _query = '';
  _Filter _filter = _Filter.all;
  int _shelf = 0;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  OctoNotesApi? get _api => ref.read(octoNotesApiProvider);

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() => setState(() {}));
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = _api;
    if (api == null) {
      _demo();
    } else {
      try {
        final r = await Future.wait([api.courses(), api.sessions(limit: 100)]);
        final courses = (r[0] as List).cast<Map<String, dynamic>>();
        _books = [
          for (var i = 0; i < courses.length; i++)
            Notebook(
              id: courses[i]['id'] as String,
              name: courses[i]['name'] as String? ?? 'Course',
              code: courses[i]['code'] as String?,
              color: notebookColor(courses[i]['color'] as String?, i),
            ),
        ];
        _sessions = (r[1] as SessionPage).items;
        if (_sessions.any((s) => s.courseId == null)) {
          _books.add(const Notebook(id: null, name: 'Loose pages', color: Color(0xFF8A8F8F)));
        }
      } on Object catch (e) {
        if (mounted) _say("Couldn't load your notebooks: $e");
      }
    }
    if (mounted) setState(() => _loading = false);
    final m = widget.manage;
    if (m != null && mounted) {
      final b = _books.where((b) => b.id == m).firstOrNull;
      if (b != null) WidgetsBinding.instance.addPostFrameCallback((_) => _manage(b));
    }
  }

  void _demo() {
    _books = const [
      Notebook(id: 'bio', name: 'Biology 101', code: 'BIO 101', color: Color(0xFFE11D2E)),
      Notebook(id: 'chem', name: 'Organic Chemistry', code: 'CHEM 210', color: Color(0xFFE8B84B)),
      Notebook(id: 'hist', name: 'World History', code: 'HIST 120', color: Color(0xFF5B8DEF)),
      Notebook(id: 'calc', name: 'Calculus II', code: 'MATH 152', color: Color(0xFF3FB27F)),
    ];
    final now = DateTime.now();
    NotesSession s(String id, String c, String t, int daysAgo, int min, String status) => NotesSession(
          id: id,
          title: t,
          status: status,
          workspaceMode: 'both',
          updatedAt: now.subtract(Duration(days: daysAgo)),
          courseId: c,
          durationMs: min * 60000,
        );
    _sessions = [
      s('1', 'bio', 'Cellular respiration', 0, 48, 'live'),
      s('2', 'calc', 'Integration by parts', 1, 52, 'ended'),
      s('3', 'chem', 'Alkenes and addition', 2, 61, 'finalized'),
      s('4', 'bio', 'Photosynthesis, part 2', 3, 45, 'finalized'),
      s('5', 'hist', 'The Silk Road', 7, 50, 'finalized'),
      s('6', 'bio', 'Photosynthesis, part 1', 9, 47, 'ended'),
      s('7', 'calc', 'Substitution', 10, 55, 'finalized'),
      s('8', 'bio', 'Enzymes', 16, 44, 'finalized'),
    ];
  }

  Notebook _bookOf(NotesSession s) =>
      _books.where((b) => b.id == s.courseId).firstOrNull ?? const Notebook(id: null, name: 'Loose pages', color: Color(0xFF8A8F8F));

  List<NotesSession> _pagesOf(Notebook b) => _sessions.where((s) => s.courseId == b.id).toList();

  List<NotesSession> get _found {
    final q = _query.trim().toLowerCase();
    return [
      for (final s in _sessions)
        if (_passes(_filter, s) && (q.isEmpty || '${s.title} ${_bookOf(s).name}'.toLowerCase().contains(q))) s,
    ];
  }

  /// Pages per notebook that match the search (all of them when it's empty).
  Map<int, int> get _hits {
    final q = _query.trim().toLowerCase();
    return {
      for (var i = 0; i < _books.length; i++)
        i: q.isEmpty
            ? _pagesOf(_books[i]).length
            : _pagesOf(_books[i]).where((s) => s.title.toLowerCase().contains(q)).length +
                (_books[i].name.toLowerCase().contains(q) || (_books[i].code ?? '').toLowerCase().contains(q) ? 1000 : 0),
    };
  }

  /// The notebook the search points at: its name first, else the most pages.
  int? get _target {
    if (_query.trim().isEmpty) return null;
    final best = _hits.entries.where((e) => e.value > 0).fold<MapEntry<int, int>?>(null, (b, e) => b == null || e.value > b.value ? e : b);
    return best?.key;
  }

  void _say(String m, {SnackBarAction? action}) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), action: action, behavior: SnackBarBehavior.floating));

  // ── Actions ──────────────────────────────────────────────────────────────

  /// A lecture still going opens live; any other opens in the notebook.
  Future<void> _open(NotesSession s) async {
    HapticFeedback.mediumImpact();
    if (const ['live', 'paused', 'draft'].contains(s.status)) {
      await openSession(context, _api, s);
    } else {
      await context.push('/notes/notebook?course=${s.courseId ?? 'loose'}&session=${s.id}');
    }
  }

  /// The cover opens the notebook to read.
  void _openBook(Notebook b, GlobalKey coverKey) {
    HapticFeedback.heavyImpact();
    context.push('/notes/notebook?course=${b.id ?? 'loose'}', extra: b);
  }

  /// The notebook's lecture list: rename, move, delete.
  void _manage(Notebook b) {
    Navigator.of(context).push(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 650),
      reverseTransitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (_, a, _) => OctoNotesTheme.wrap(
        context: context,
        child: _NotebookPage(
          book: b,
          pages: () => _pagesOf(b),
          onOpen: _open,
          onActions: _actions,
          onNew: () => _newSession(b),
        ),
      ),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  void _newSession([Notebook? b]) {
    HapticFeedback.mediumImpact();
    MediaQuery.sizeOf(context).shortestSide < 600 ? showNewSessionSheet(context, courseId: b?.id) : showNewSessionDialog(context);
  }

  Future<void> _actions(NotesSession s) async {
    HapticFeedback.heavyImpact();
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        Widget item(IconData icon, String label, String value, {Color? color}) => ListTile(
              leading: Icon(icon, color: color),
              title: Text(label, style: TextStyle(color: color)),
              onTap: () => Navigator.pop(context, value),
            );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    Text('${_bookOf(s).name} · ${_date(s.updatedAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(color: _bookOf(s).color)),
                  ],
                ),
              ),
              item(Icons.edit_outlined, 'Rename', 'rename'),
              item(Icons.auto_stories_outlined, 'Move to another notebook', 'move'),
              item(Icons.delete_outline_rounded, 'Delete', 'delete', color: theme.colorScheme.error),
            ],
          ),
        );
      },
    );
    if (!mounted || choice == null) return;
    HapticFeedback.selectionClick();
    switch (choice) {
      case 'rename':
        final name = await _ask('Rename', s.title);
        if (name == null || name.trim().isEmpty) return;
        await _patch(s, {'title': name.trim()}, (x) => _copy(x, title: name.trim()));
      case 'move':
        final to = await _pickBook(s);
        if (to == null) return;
        await _patch(s, {'courseId': to.id}, (x) => _copy(x, courseId: to.id, clearCourse: to.id == null));
      case 'delete':
        _delete(s);
    }
  }

  NotesSession _copy(NotesSession s, {String? title, String? courseId, bool clearCourse = false}) => NotesSession(
        id: s.id,
        title: title ?? s.title,
        status: s.status,
        workspaceMode: s.workspaceMode,
        updatedAt: s.updatedAt,
        courseId: clearCourse ? null : (courseId ?? s.courseId),
        deckRef: s.deckRef,
        durationMs: s.durationMs,
      );

  Future<void> _patch(NotesSession s, Map<String, dynamic> patch, NotesSession Function(NotesSession) local) async {
    final i = _sessions.indexOf(s);
    setState(() => _sessions[i] = local(s));
    try {
      await _api?.updateSession(s.id, patch);
      HapticFeedback.lightImpact();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _sessions[i] = s);
      _say("Couldn't save that: $e");
    }
  }

  /// Gone at once; really deleted only if Undo isn't tapped.
  void _delete(NotesSession s) {
    final i = _sessions.indexOf(s);
    setState(() => _sessions.removeAt(i));
    var undone = false;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Deleted “${s.title}”'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            undone = true;
            HapticFeedback.selectionClick();
            setState(() => _sessions.insert(i.clamp(0, _sessions.length), s));
          },
        ),
      ));
    unawaited(Future<void>.delayed(const Duration(seconds: 5), () async {
      if (undone) return;
      try {
        await _api?.deleteSession(s.id);
      } on Object {
        if (mounted) setState(() => _sessions.insert(i.clamp(0, _sessions.length), s));
      }
    }));
  }

  Future<String?> _ask(String title, String initial) => showDialog<String>(
        context: context,
        builder: (context) {
          final c = TextEditingController(text: initial);
          return AlertDialog(
            title: Text(title),
            content: _LineField(controller: c, autofocus: true, hint: 'Name'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Save')),
            ],
          );
        },
      );

  Future<Notebook?> _pickBook(NotesSession s) => showModalBottomSheet<Notebook>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final b in _books)
                ListTile(
                  leading: Container(width: 10, height: 28, decoration: BoxDecoration(color: b.color, borderRadius: BorderRadius.circular(5))),
                  title: Text(b.name),
                  trailing: b.id == s.courseId ? const Icon(Icons.check_rounded) : null,
                  onTap: () => Navigator.pop(context, b),
                ),
            ],
          ),
        ),
      );

  Future<void> _newNotebook() async {
    HapticFeedback.mediumImpact();
    final made = await showModalBottomSheet<(String, Color)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _NewNotebookSheet(),
    );
    if (made == null || !mounted) return;
    final api = _api;
    try {
      final c = api == null ? <String, dynamic>{'id': 'local-${made.$1}'} : await api.createCourse(made.$1, color: _hexOf(made.$2));
      if (!mounted) return;
      unawaited(HapticFeedback.mediumImpact());
      setState(() => _books.insert(0, Notebook(id: c['id'] as String?, name: made.$1, color: made.$2)));
      _shelf = 0;
    } on Object catch (e) {
      if (mounted) _say("Couldn't make the notebook: $e");
    }
  }

  @override
  Widget build(BuildContext context) => OctoNotesTheme.wrap(context: context, child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final searching = _query.trim().isNotEmpty;
    final focus = _books.isEmpty ? scheme.primary : _books[_shelf.clamp(0, _books.length - 1)].color;
    final found = _found;
    return Scaffold(
      backgroundColor: const Color(0xFF0F1010),
      body: Stack(
        children: [
          Positioned(left: -140, right: -140, top: -180, height: 460, child: _Aurora(color: focus)),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : CustomScrollView(
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(10, 4, 22, 0),
                              child: Row(
                                children: [
                                  IconButton(
                                    tooltip: 'Back',
                                    icon: const Icon(Icons.chevron_left_rounded),
                                    onPressed: () => context.canPop() ? context.pop() : context.go('/notes'),
                                  ),
                                  const Spacer(),
                                ],
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 22),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _Cap('OctoNotes'),
                                  const SizedBox(height: 4),
                                  Text('Notebooks',
                                      style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -1, height: 1)),
                                  const SizedBox(height: 14),
                                  _SearchLine(
                                    controller: _search,
                                    focus: _searchFocus,
                                    onChanged: (v) => setState(() => _query = v),
                                    onClear: () {
                                      HapticFeedback.lightImpact();
                                      _search.clear();
                                      setState(() => _query = '');
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: _Shelf(
                              books: _books,
                              pages: _pagesOf,
                              index: _shelf,
                              target: _target,
                              hits: searching ? _hits : null,
                              onIndex: (i) {
                                HapticFeedback.selectionClick();
                                setState(() => _shelf = i);
                              },
                              onOpen: _openBook,
                              onNew: _newNotebook,
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      _Cap(searching ? 'Pages found' : 'Recent pages'),
                                      const Spacer(),
                                      Text('${found.length} pages', style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  _FilterPill(
                                    value: _filter,
                                    color: const Color(0xFFECEDED),
                                    onChanged: (f) {
                                      HapticFeedback.selectionClick();
                                      setState(() => _filter = f);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (found.isEmpty)
                            const SliverToBoxAdapter(child: _Empty())
                          else
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(22, 4, 22, 120),
                              sliver: SliverList.builder(
                                itemCount: found.length,
                                itemBuilder: (context, i) => _Rise(
                                  key: ValueKey('${found[i].id}-$_filter-$_query'),
                                  delay: math.min(i, 8) * 45,
                                  child: _PageRow(
                                    session: found[i],
                                    book: _bookOf(found[i]),
                                    onTap: () => _open(found[i]),
                                    onLongPress: () => _actions(found[i]),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _Dock(
              child: _ShineButton(
                label: 'New session',
                icon: Icons.mic_none_rounded,
                colors: [scheme.primary, scheme.primary],
                onTap: () => _newSession(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// The shelf: a 3D carousel of covers
// ===========================================================================
class _Shelf extends StatefulWidget {
  const _Shelf({
    required this.books,
    required this.pages,
    required this.index,
    required this.onIndex,
    required this.onOpen,
    required this.onNew,
    this.target,
    this.hits,
  });
  final List<Notebook> books;
  final List<NotesSession> Function(Notebook) pages;
  final int index;

  /// While searching: the notebook to glide to, and matches per notebook
  /// (a name match counts 1000); notebooks with none dim.
  final int? target;
  final Map<int, int>? hits;
  final ValueChanged<int> onIndex;
  final void Function(Notebook, GlobalKey) onOpen;
  final VoidCallback onNew;

  @override
  State<_Shelf> createState() => _ShelfState();
}

class _ShelfState extends State<_Shelf> {
  late final _pc = PageController(viewportFraction: 0.52, initialPage: widget.index);
  final _keys = <String, GlobalKey>{};

  @override
  void didUpdateWidget(covariant _Shelf old) {
    super.didUpdateWidget(old);
    final t = widget.target;
    if (t != null && t != old.target && _pc.hasClients) {
      // The search found a notebook: glide the shelf to it.
      _pc.animateToPage(t, duration: Duration(milliseconds: 420 + 120 * (t - widget.index).abs().clamp(0, 4)), curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.books.length + 1;
    final hits = widget.hits;
    return Column(
      children: [
        SizedBox(
          height: 290,
          child: PageView.builder(
            controller: _pc,
            itemCount: count,
            onPageChanged: (i) => i < widget.books.length ? widget.onIndex(i) : HapticFeedback.selectionClick(),
            itemBuilder: (context, i) => AnimatedBuilder(
              animation: _pc,
              builder: (context, child) {
                final page = _pc.hasClients && _pc.position.haveDimensions ? _pc.page! : widget.index.toDouble();
                final a = (i - page).clamp(-1.5, 1.5);
                return Center(
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0012)
                      ..rotateY(-a * 0.66)
                      ..scaleByDouble(1 - a.abs() * 0.1, 1 - a.abs() * 0.1, 1, 1),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 300),
                      opacity: (1 - a.abs() * 0.3).clamp(0.2, 1) * (hits == null || i >= widget.books.length || (hits[i] ?? 0) > 0 ? 1 : 0.28),
                      child: i == widget.books.length
                          ? _NewCover(onTap: widget.onNew)
                          : GestureDetector(
                              onTap: () {
                                if (i != page.round()) {
                                  _pc.animateToPage(i, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
                                  return;
                                }
                                widget.onOpen(widget.books[i], _keys[widget.books[i].name]!);
                              },
                              child: Hero(
                                tag: 'notebook-${widget.books[i].id ?? 'loose'}',
                                child: _Cover(
                                  key: _keys.putIfAbsent(widget.books[i].name, GlobalKey.new),
                                  book: widget.books[i],
                                  pages: widget.pages(widget.books[i]),
                                  shine: a,
                                  // A name match finds the whole notebook.
                                  found: hits == null
                                      ? null
                                      : ((hits[i] ?? 0) >= 1000 ? widget.pages(widget.books[i]).length : hits[i] ?? 0),
                                ),
                              ),
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < count; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutBack,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == widget.index ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == widget.index && i < widget.books.length ? widget.books[i].color : const Color(0xFF3A3C3C),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// A notebook's cover: coloured board, spine, elastic band, page edges.
class _Cover extends StatelessWidget {
  const _Cover({super.key, required this.book, required this.pages, this.shine = 0, this.width = 176, this.height = 236, this.found});
  final Notebook book;
  final List<NotesSession> pages;
  final double shine;

  /// While searching: pages in here that match.
  final int? found;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final live = pages.any((s) => s.status == 'live');
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Page edges peeking out on the right.
          Positioned(
            right: -5,
            top: 7,
            bottom: 7,
            width: 8,
            child: CustomPaint(painter: _EdgesPainter()),
          ),
          Positioned.fill(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(8), right: Radius.circular(16)),
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [book.color, book.deep]),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.7), blurRadius: 32, offset: const Offset(0, 22), spreadRadius: -12)],
              ),
              child: Stack(
                children: [
                  const Positioned.fill(child: CustomPaint(painter: _ClothPainter())),
                  // A sheen that slides as the cover turns.
                  Positioned.fill(
                    child: FractionalTranslation(
                      translation: Offset(-shine * 0.8, 0),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment(-1, -1),
                            end: Alignment(1, 1),
                            colors: [Color(0x00FFFFFF), Color(0x2EFFFFFF), Color(0x00FFFFFF)],
                            stops: [0.38, 0.5, 0.62],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 14,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Color(0x47000000),
                        border: Border(right: BorderSide(color: Color(0x1AFFFFFF))),
                      ),
                    ),
                  ),
                  Positioned(right: 22, top: -2, bottom: -2, width: 7, child: Container(color: const Color(0x73000000))),
                  Positioned(
                    left: 28,
                    right: 38,
                    top: 28,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(book.name,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                              letterSpacing: -0.3,
                              shadows: const [Shadow(color: Color(0x59000000), offset: Offset(0, 1))],
                            )),
                        if (book.code != null) ...[
                          const SizedBox(height: 6),
                          Text(book.code!, style: theme.textTheme.labelMedium?.copyWith(color: Colors.white.withValues(alpha: 0.78))),
                        ],
                      ],
                    ),
                  ),
                  Positioned(
                    left: 28,
                    bottom: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(color: const Color(0x47000000), borderRadius: BorderRadius.circular(99)),
                      child: Row(
                        children: [
                          const Icon(Icons.sticky_note_2_outlined, size: 13, color: Colors.white),
                          const SizedBox(width: 5),
                          Text('${pages.length} pages', style: theme.textTheme.labelSmall?.copyWith(color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                  if (live) const Positioned(right: 38, bottom: 26, child: _Ping()),
                  // "3 found" pops onto the cover while searching.
                  Positioned(
                    right: 30,
                    top: 14,
                    child: AnimatedScale(
                      scale: (found ?? 0) > 0 ? 1 : 0,
                      duration: const Duration(milliseconds: 380),
                      curve: Curves.easeOutBack,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(99),
                          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 3))],
                        ),
                        child: Text('${found ?? 0} found',
                            style: theme.textTheme.labelSmall?.copyWith(color: book.deep, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClothPainter extends CustomPainter {
  const _ClothPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x09FFFFFF)
      ..strokeWidth = 2;
    for (var x = -size.height; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height * 0.55, 0), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _EdgesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndCorners(Offset.zero & size, topRight: const Radius.circular(3), bottomRight: const Radius.circular(3));
    canvas.drawRRect(r, Paint()..color = const Color(0xFFD9D6CC));
    final line = Paint()..color = const Color(0xFFB4AFA2);
    for (var y = 1.0; y < size.height; y += 2) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _Ping extends StatefulWidget {
  const _Ping();
  @override
  State<_Ping> createState() => _PingState();
}

class _PingState extends State<_Ping> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Live now',
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: 0.7 * (1 - _c.value)), spreadRadius: 10 * _c.value)],
            ),
          ),
        ),
      );
}

class _NewCover extends StatelessWidget {
  const _NewCover({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedPainter(muted.withValues(alpha: 0.45)),
        child: SizedBox(
          width: 176,
          height: 236,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, size: 26, color: muted),
              const SizedBox(height: 8),
              Text('New notebook', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: muted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedPainter extends CustomPainter {
  _DashedPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndCorners(Offset.zero & size,
          topLeft: const Radius.circular(8), bottomLeft: const Radius.circular(8), topRight: const Radius.circular(16), bottomRight: const Radius.circular(16)));
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 10) {
        canvas.drawPath(m.extractPath(d, d + 5), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPainter old) => old.color != color;
}

// ===========================================================================
// An open notebook: the cover swings back on ruled pages
// ===========================================================================
class _NotebookPage extends StatefulWidget {
  const _NotebookPage({required this.book, required this.pages, required this.onOpen, required this.onActions, required this.onNew});
  final Notebook book;
  final List<NotesSession> Function() pages;
  final Future<void> Function(NotesSession) onOpen;
  final Future<void> Function(NotesSession) onActions;
  final VoidCallback onNew;

  @override
  State<_NotebookPage> createState() => _NotebookPageState();
}

class _NotebookPageState extends State<_NotebookPage> with SingleTickerProviderStateMixin {
  late final _swing = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    // Once the cover has landed full screen, it swings open.
    Future<void>.delayed(const Duration(milliseconds: 620), () {
      if (!mounted) return;
      HapticFeedback.selectionClick();
      _swing.forward();
    });
  }

  @override
  void dispose() {
    _swing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final b = widget.book;
    final all = widget.pages();
    final pages = all.where((s) => _passes(_filter, s)).toList();
    final fin = all.where((s) => _passes(_Filter.finalNotes, s)).length;
    final mins = all.fold<int>(0, (a, s) => a + s.durationMs ~/ 60000);
    final weeks = <String, List<NotesSession>>{};
    for (final s in pages) {
      weeks.putIfAbsent(_week(s.updatedAt), () => []).add(s);
    }
    return Scaffold(
      backgroundColor: const Color(0xFF141515),
      body: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _RuledPainter())),
          Positioned(left: -140, right: -140, top: -200, height: 420, child: _Aurora(color: b.color, strength: 0.35)),
          SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 4, 22, 0),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Back',
                          icon: const Icon(Icons.chevron_left_rounded),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            Navigator.of(context).maybePop();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(_kMargin + 14, 0, 22, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Cap('Notebook', color: b.color),
                        const SizedBox(height: 4),
                        Text(b.name, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.6)),
                        if (b.code != null)
                          Text(b.code!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            _Stat(value: all.length, label: 'pages'),
                            const SizedBox(width: 20),
                            _Stat(text: '${mins ~/ 60}h ${mins % 60}m', label: 'recorded'),
                            const SizedBox(width: 20),
                            _Stat(value: fin, label: 'final'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _FilterPill(
                          value: _filter,
                          color: b.color,
                          onChanged: (f) {
                            HapticFeedback.selectionClick();
                            setState(() => _filter = f);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                if (pages.isEmpty) const SliverToBoxAdapter(child: _Empty(indent: _kMargin)),
                for (final w in weeks.entries) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(_kMargin + 14, 22, 22, 2),
                      child: _Cap(w.key),
                    ),
                  ),
                  SliverList.builder(
                    itemCount: w.value.length,
                    itemBuilder: (context, i) => _Rise(
                      key: ValueKey('${w.value[i].id}-$_filter'),
                      delay: 160 + math.min(i, 8) * 60,
                      child: _Entry(
                        session: w.value[i],
                        onTap: () => widget.onOpen(w.value[i]),
                        onLongPress: () async {
                          await widget.onActions(w.value[i]);
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _Dock(
              color: const Color(0xFF141515),
              child: _ShineButton(label: 'New page in ${b.name}', icon: Icons.mic_none_rounded, colors: [b.color, b.deep], onTap: widget.onNew),
            ),
          ),
          // The cover, landed by the Hero, then swinging open on its spine.
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _swing,
              builder: (context, _) {
                final t = Curves.easeInOutCubic.transform(_swing.value);
                if (t >= 1) return const SizedBox.shrink();
                return Opacity(
                  opacity: t < 0.75 ? 1 : (1 - (t - 0.75) / 0.25),
                  child: Transform(
                    alignment: Alignment.centerLeft,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0009)
                      ..rotateY(-t * 2.05),
                    child: Hero(
                      tag: 'notebook-${b.id ?? 'loose'}',
                      child: LayoutBuilder(
                        builder: (context, c) => _Cover(book: b, pages: all, width: c.maxWidth, height: c.maxHeight),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

const double _kMargin = 56;

/// Notebook paper: faint rules, a red margin, punched holes.
class _RuledPainter extends CustomPainter {
  const _RuledPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final rule = Paint()..color = const Color(0x09FFFFFF);
    for (var y = 31.0; y < size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rule);
    }
    canvas.drawLine(const Offset(_kMargin, 0), Offset(_kMargin, size.height), Paint()..color = const Color(0x59E11D2E));
    final hole = Paint()..color = const Color(0xFF0A0A0A);
    for (var y = 140.0; y < size.height; y += 120) {
      canvas.drawCircle(Offset(20, y), 6, hole);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _Entry extends StatelessWidget {
  const _Entry({required this.session, required this.onTap, required this.onLongPress});
  final NotesSession session;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = session;
    final d = s.updatedAt.toLocal();
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _kMargin + 14,
            child: Padding(
              padding: const EdgeInsets.only(top: 13, right: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_weekday(d), style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                  Text('${d.day}', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w300, height: 1.05)),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(0, 13, 22, 13),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x0BFFFFFF)))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text('${s.durationMs ~/ 60000} min · ', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      _Status(status: s.status),
                    ],
                  ),
                  if (_passes(_Filter.finalNotes, s)) ...[
                    const SizedBox(height: 7),
                    SizedBox(
                      width: 120,
                      child: Row(
                        children: [
                          for (final c in _topicColors.take(4)) ...[
                            Expanded(child: Container(height: 3, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)))),
                            const SizedBox(width: 2),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Shared pieces
// ===========================================================================
class _PageRow extends StatelessWidget {
  const _PageRow({required this.session, required this.book, required this.onTap, required this.onLongPress});
  final NotesSession session;
  final Notebook book;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)))),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [book.color, book.deep]),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(session.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text('${book.name} · ${_date(session.updatedAt)} · ',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ),
                      _Status(status: session.status),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final brand = CockpitColors.brand;
    if (const ['draft', 'live', 'paused'].contains(status)) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        _Blink(color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 4),
        Text(status == 'draft' ? 'Not started' : 'Live now', style: style?.copyWith(color: const Color(0xFFFF5A66))),
      ]);
    }
    final fin = status == 'finalized' || status == 'archived';
    return Text(fin ? 'Final notes' : 'Ready to finalize', style: style?.copyWith(color: fin ? brand.success : brand.tertiary));
  }
}

class _Blink extends StatefulWidget {
  const _Blink({required this.color});
  final Color color;
  @override
  State<_Blink> createState() => _BlinkState();
}

class _BlinkState extends State<_Blink> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 1.0, end: 0.25).animate(_c),
        child: Container(width: 6, height: 6, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
      );
}

/// All · Live · To finalize · Final, with a pill that slides.
class _FilterPill extends StatelessWidget {
  const _FilterPill({required this.value, required this.color, required this.onChanged});
  final _Filter value;
  final Color color;
  final ValueChanged<_Filter> onChanged;

  static const _labels = ['All', 'Live', 'To finalize', 'Final'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = color.computeLuminance() > 0.4;
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: const Color(0xFF1B1C1C), borderRadius: BorderRadius.circular(99)),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / 4;
        return Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutBack,
              left: w * value.index,
              width: w,
              top: 0,
              bottom: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(99)),
              ),
            ),
            Row(
              children: [
                for (final f in _Filter.values)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: f == value,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: f == value ? null : () => onChanged(f),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 250),
                            style: theme.textTheme.labelMedium!.copyWith(
                              color: f == value ? (dark ? const Color(0xFF121313) : Colors.white) : theme.colorScheme.onSurfaceVariant,
                              fontWeight: f == value ? FontWeight.w700 : FontWeight.w500,
                            ),
                            child: Text(_labels[f.index], maxLines: 1),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      }),
    );
  }
}

/// Search as a line, no box: the rule lights up red to gold when focused.
class _SearchLine extends StatelessWidget {
  const _SearchLine({required this.controller, required this.focus, required this.onChanged, required this.onClear});
  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final on = focus.hasFocus || controller.text.isNotEmpty;
    return Column(
      children: [
        Row(
          children: [
            Icon(Icons.search_rounded, size: 20, color: on ? scheme.onSurface : scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: _LineField(controller: controller, focus: focus, hint: 'Search every notebook', onChanged: onChanged),
            ),
            if (controller.text.isNotEmpty)
              GestureDetector(onTap: onClear, child: Icon(Icons.close_rounded, size: 18, color: scheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 9),
        Stack(
          children: [
            Container(height: 1, color: const Color(0xFF262828)),
            AnimatedFractionallySizedBox(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutBack,
              widthFactor: on ? 1 : 0,
              child: Container(
                height: 1.5,
                decoration: BoxDecoration(gradient: LinearGradient(colors: [scheme.primary, CockpitColors.brand.tertiary])),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A text field with no box and no fill.
class _LineField extends StatelessWidget {
  const _LineField({required this.controller, this.focus, required this.hint, this.onChanged, this.autofocus = false});
  final TextEditingController controller;
  final FocusNode? focus;
  final String hint;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      focusNode: focus,
      autofocus: autofocus,
      onChanged: onChanged,
      cursorColor: theme.colorScheme.primary,
      style: theme.textTheme.bodyLarge,
      decoration: InputDecoration.collapsed(
        hintText: hint,
        hintStyle: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
        filled: false,
      ).copyWith(fillColor: Colors.transparent),
    );
  }
}

class _NewNotebookSheet extends StatefulWidget {
  const _NewNotebookSheet();
  @override
  State<_NewNotebookSheet> createState() => _NewNotebookSheetState();
}

class _NewNotebookSheetState extends State<_NewNotebookSheet> {
  final _name = TextEditingController();
  Color _color = _palette.first;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 0, 22, 22 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New notebook', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('One notebook per course.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 18),
          _LineField(controller: _name, autofocus: true, hint: 'Biology 101'),
          const SizedBox(height: 9),
          Container(height: 1, color: const Color(0xFF262828)),
          const SizedBox(height: 18),
          Row(
            children: [
              for (final c in _palette)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _color = c);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.only(right: 12),
                    width: _color == c ? 30 : 24,
                    height: _color == c ? 30 : 24,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(color: _color == c ? Colors.white : Colors.transparent, width: 2.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _color, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () {
                if (_name.text.trim().isEmpty) {
                  HapticFeedback.heavyImpact();
                  return;
                }
                Navigator.pop(context, (_name.text.trim(), _color));
              },
              child: const Text('Make notebook'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slow coloured light behind the top of the page.
class _Aurora extends StatefulWidget {
  const _Aurora({required this.color, this.strength = 0.5});
  final Color color;
  final double strength;
  @override
  State<_Aurora> createState() => _AuroraState();
}

class _AuroraState extends State<_Aurora> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: widget.color),
          duration: const Duration(milliseconds: 900),
          builder: (_, color, _) => AnimatedBuilder(
            animation: _c,
            builder: (_, _) => CustomPaint(painter: _AuroraPainter(color ?? widget.color, _c.value, widget.strength)),
          ),
        ),
      );
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.color, this.t, this.strength);
  final Color color;
  final double t;
  final double strength;

  @override
  void paint(Canvas canvas, Size s) {
    void blob(Offset c, double r, Color col) => canvas.drawCircle(
          c,
          r,
          Paint()..shader = RadialGradient(colors: [col, col.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r)),
        );
    blob(Offset(s.width * (0.36 + 0.06 * t), s.height * (0.55 + 0.05 * t)), s.width * 0.42, color.withValues(alpha: 0.42 * strength));
    blob(Offset(s.width * (0.72 - 0.05 * t), s.height * 0.42), s.width * 0.3,
        HSLColor.fromColor(color).withHue((HSLColor.fromColor(color).hue + 30) % 360).toColor().withValues(alpha: 0.25 * strength));
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) => old.t != t || old.color != color;
}

class _Dock extends StatelessWidget {
  const _Dock({required this.child, this.color = const Color(0xFF0F1010)});
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0), color, color],
            stops: const [0, 0.45, 1],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(padding: const EdgeInsets.fromLTRB(18, 28, 18, 14), child: child),
            ),
          ),
        ),
      );
}

/// A pill button with a light that sweeps across it now and then.
class _ShineButton extends StatefulWidget {
  const _ShineButton({required this.label, required this.icon, required this.colors, required this.onTap});
  final String label;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  State<_ShineButton> createState() => _ShineButtonState();
}

class _ShineButtonState extends State<_ShineButton> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();
  bool _down = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: const Duration(milliseconds: 120),
          child: Container(
            height: 52,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              gradient: LinearGradient(colors: widget.colors),
              boxShadow: [BoxShadow(color: widget.colors.first.withValues(alpha: 0.4), blurRadius: 24, offset: const Offset(0, 8))],
            ),
            child: Stack(
              children: [
                AnimatedBuilder(
                  animation: _c,
                  builder: (_, _) {
                    final x = Curves.easeInOut.transform((_c.value / 0.6).clamp(0.0, 1.0)) * 2.4 - 1.2;
                    return Positioned.fill(
                      child: FractionalTranslation(
                        translation: Offset(x, 0),
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0x00FFFFFF), Color(0x38FFFFFF), Color(0x00FFFFFF)],
                              stops: [0.3, 0.5, 0.7],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.icon, size: 19, color: Colors.white),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({this.value, this.text, required this.label});
  final int? value;
  final String? text;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w300, fontFeatures: const [FontFeature.tabularFigures()]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (value != null)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value!.toDouble()),
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => Text('${v.round()}', style: style),
          )
        else
          Text(text!, style: style),
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _Cap extends StatelessWidget {
  const _Cap(this.text, {this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.6, color: color ?? Theme.of(context).colorScheme.onSurfaceVariant),
      );
}

class _Empty extends StatelessWidget {
  const _Empty({this.indent = 0});
  final double indent;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: EdgeInsets.fromLTRB(indent, 40, 0, 40),
      child: Column(
        children: [
          Icon(Icons.menu_book_outlined, size: 26, color: muted),
          const SizedBox(height: 8),
          Text('No pages match', style: TextStyle(color: muted)),
        ],
      ),
    );
  }
}

class _Rise extends StatelessWidget {
  const _Rise({super.key, required this.delay, required this.child});
  final int delay;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 480 + delay),
        builder: (_, v, c) {
          final t = Curves.easeOutCubic.transform(((v * (480 + delay) - delay) / 480).clamp(0.0, 1.0));
          return Opacity(opacity: t, child: Transform.translate(offset: Offset(0, (1 - t) * 12), child: c));
        },
        child: child,
      );
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _date(DateTime d) => '${_months[d.toLocal().month - 1]} ${d.toLocal().day}';
String _weekday(DateTime d) => const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];

String _week(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  final now = DateTime.now();
  final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
  if (!day.isBefore(monday)) return 'This week';
  if (!day.isBefore(monday.subtract(const Duration(days: 7)))) return 'Last week';
  final start = day.subtract(Duration(days: day.weekday - 1));
  return 'Week of ${_months[start.month - 1]} ${start.day}';
}
