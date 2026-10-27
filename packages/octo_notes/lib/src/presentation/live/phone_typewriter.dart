part of 'live_session_hub_page.dart';

// ===========================================================================
// Phone Typewriter: the session's notes as blocks, typed in portrait. Every
// edit goes through BlockSyncEngine (queued, offline-safe). A transcript line
// becomes a quote with its time; AI can expand the block you're on.
// ===========================================================================

/// An invisible mark at the start of every line's text. A soft keyboard
/// says nothing when Backspace has nothing to delete, so the mark is what it
/// deletes: when it's gone, Backspace was pressed at the start of the line.
const _mark = '\u200B';

class _TwBlock {
  _TwBlock({
    required this.id,
    required this.type,
    required String text,
    required this.position,
    this.checked = false,
    this.revision = 0,
    this.origin = 'student',
    this.atMs,
  }) : text = TextEditingController(text: '$_mark$text');

  final String id;
  String type;
  final TextEditingController text;
  final FocusNode focus = FocusNode();
  String position;
  bool checked;
  int revision;
  final String origin;
  final int? atMs;
  bool important = false;

  /// The text without the mark.
  String get value => text.text.startsWith(_mark) ? text.text.substring(1) : text.text;

  /// Sets the text, the caret [at] an offset into it.
  void setValue(String v, int at) =>
      text.value = TextEditingValue(text: '$_mark$v', selection: TextSelection.collapsed(offset: at + 1));

  /// The text last saved (the controller also fires on cursor moves).
  late String saved = value;

  /// Quotes and AI text are kept as they came.
  bool get readOnly => type == 'quote' || type == 'transcriptExcerpt' || origin == 'aiInsertedByStudent';

  factory _TwBlock.fromJson(Map<String, dynamic> j) => _TwBlock(
        id: j['id'] as String,
        type: j['type'] as String? ?? 'paragraph',
        text: j['text'] as String? ?? '',
        position: j['position'] as String,
        checked: j['checked'] == true,
        revision: (j['revision'] as num?)?.toInt() ?? 0,
        origin: j['origin'] as String? ?? 'student',
        atMs: (j['audioTsMs'] as num?)?.toInt(),
      );

  void dispose() {
    text.dispose();
    focus.dispose();
  }
}

class _PhoneTypewriter extends StatefulWidget {
  const _PhoneTypewriter({required this.state});
  final _LiveSessionHubPageState state;

  @override
  State<_PhoneTypewriter> createState() => _PhoneTypewriterState();
}

class _PhoneTypewriterState extends State<_PhoneTypewriter> {
  final List<_TwBlock> _blocks = [];
  BlockSyncEngine? _sync;
  StreamSubscription<Map<String, dynamic>>? _applied;
  _TwBlock? _focused;
  bool _loading = true;

  /// The AI's text while it streams in, under [_aiFor].
  String? _aiText;
  _TwBlock? _aiFor;

  // Undo / redo: whole-page snapshots. A typing run on one line is one step.
  final List<List<_Snap>> _undo = [];
  final List<List<_Snap>> _redo = [];
  _TwBlock? _typingIn;
  DateTime _typedAt = DateTime(0);
  bool _restoring = false;

  /// Blocks re-created by undo get new ids (the server keeps deleted ones).
  final Map<String, String> _alias = {};

  _LiveSessionHubPageState get hub => widget.state;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final api = hub.ref.read(octoNotesApiProvider);
    final id = hub.widget.sessionId;
    if (api == null || id == null) {
      _seedDemo();
    } else {
      final sync = BlockSyncEngine(api: api, sessionId: id, deviceId: hub._device?.id, store: PrefsOpStore())
        ..addListener(_changed);
      _sync = sync;
      _applied = sync.applied.listen((b) {
        for (final x in _blocks) {
          if (x.id == b['id']) x.revision = (b['revision'] as num?)?.toInt() ?? x.revision;
        }
      });
      await sync.restore();
      try {
        final res = await api.blocks(id);
        sync.rev = (res['rev'] as num?)?.toInt() ?? 0;
        for (final b in (res['blocks'] as List? ?? const []).cast<Map<String, dynamic>>()) {
          if (b['deletedAt'] == null) _add(_TwBlock.fromJson(b));
        }
      } on Object {
        // Offline: start empty; queued edits still go out later.
      }
    }
    if (_blocks.isEmpty) _add(_TwBlock(id: OctoNotesApi.newId(), type: 'paragraph', text: '', position: positionAfter(null)), save: true);
    if (mounted) setState(() => _loading = false);
  }

  void _seedDemo() {
    var p = positionAfter(null);
    _TwBlock b(String type, String text, {int? at}) {
      final x = _TwBlock(id: OctoNotesApi.newId(), type: type, text: text, position: p, atMs: at);
      p = positionAfter(p);
      return x;
    }

    for (final x in [
      b('h2', 'Cellular respiration'),
      b('bulleted', 'Glycolysis: cytoplasm, no oxygen'),
      b('quote', 'Pyruvate then enters the mitochondria.', at: 722000),
      b('paragraph', ''),
    ]) {
      _add(x);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _add(_TwBlock b, {int? at, bool save = false}) {
    b.focus.addListener(() {
      if (b.focus.hasFocus) setState(() => _focused = b);
    });
    b.text.addListener(() => _onText(b));
    at == null ? _blocks.add(b) : _blocks.insert(at, b);
    if (save) _save(b, isNew: true);
  }

  List<_Snap> _snapshot() => [for (final b in _blocks) _Snap.of(b)];

  /// Call before a change, so undo comes back to here.
  void _record() {
    if (_restoring) return;
    _undo.add(_snapshot());
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
    _typingIn = null;
  }

  void _undoRedo(bool undo) {
    final from = undo ? _undo : _redo;
    if (from.isEmpty) return;
    HapticFeedback.lightImpact();
    (undo ? _redo : _undo).add(_snapshot());
    _restore(from.removeLast());
    _typingIn = null;
  }

  String _idOf(String id) {
    var x = id;
    while (_alias[x] != null) {
      x = _alias[x]!;
    }
    return x;
  }

  void _restore(List<_Snap> snap) {
    _restoring = true;
    final byId = {for (final b in _blocks) b.id: b};
    final keep = <_TwBlock>[];
    for (final x in snap) {
      var b = byId.remove(_idOf(x.id));
      if (b == null) {
        // Deleted since: back as a new block in the same place.
        b = _TwBlock(id: OctoNotesApi.newId(), type: x.type, text: x.text, position: x.position, checked: x.checked, origin: x.origin == 'aiInsertedByStudent' ? 'student' : x.origin, atMs: x.atMs);
        _alias[_idOf(x.id)] = b.id;
        _add(b, save: true);
        _blocks.remove(b);
      } else if (b.type != x.type || b.value != x.text || b.checked != x.checked) {
        b
          ..type = x.type
          ..checked = x.checked
          ..setValue(x.text, x.text.length)
          ..saved = x.text;
        _save(b);
      }
      b.important = x.important;
      keep.add(b);
    }
    for (final gone in byId.values) {
      unawaited(_sync?.delete(gone.id, baseRevision: gone.revision));
      if (_focused == gone) _focused = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => gone.dispose());
    }
    setState(() {
      _blocks
        ..clear()
        ..addAll(keep);
    });
    _restoring = false;
  }

  /// Takes a line out; the caret goes to the end of [focus].
  void _remove(_TwBlock b, {_TwBlock? focus}) {
    setState(() => _blocks.remove(b));
    unawaited(_sync?.delete(b.id, baseRevision: b.revision));
    if (_focused == b) _focused = null;
    if (focus != null) {
      focus.focus.requestFocus();
      focus.text.selection = TextSelection.collapsed(offset: focus.text.text.length);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => b.dispose());
    if (_blocks.isEmpty) _insertAfter(null, 'paragraph', '');
  }

  /// Backspace at the start of a line: a heading or list item becomes plain
  /// text; plain text joins the line above; a quote above is taken out.
  void _backspaceAtStart(_TwBlock b) {
    if (b.type != 'paragraph') {
      _record();
      HapticFeedback.selectionClick();
      setState(() => b.type = 'paragraph');
      _save(b);
      return;
    }
    final i = _blocks.indexOf(b);
    if (i <= 0) return;
    final above = _blocks[i - 1];
    _record();
    HapticFeedback.selectionClick();
    if (above.readOnly) {
      _remove(above);
      return;
    }
    final join = above.value.length;
    final merged = above.value + b.value;
    above.setValue(merged, join);
    _remove(b);
    above.focus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) => above.text.selection = TextSelection.collapsed(offset: join + 1));
  }

  /// A tap below the last line: type there.
  void _typeAtEnd() {
    final last = _blocks.lastOrNull;
    if (last == null || last.readOnly || last.type.startsWith('h')) {
      _insertAfter(last, 'paragraph', '');
      return;
    }
    last.focus.requestFocus();
    last.text.selection = TextSelection.collapsed(offset: last.text.text.length);
  }

  void _save(_TwBlock b, {bool isNew = false}) {
    final sync = _sync;
    if (sync == null) return;
    unawaited(sync.upsert(
      b.id,
      {
        'type': b.type,
        'text': b.value,
        'checked': b.checked,
        if (isNew) ...{'position': b.position, 'origin': b.origin == 'fromTranscript' ? 'fromTranscript' : 'student'},
        if (isNew && b.atMs != null) 'audioTsMs': b.atMs,
      },
      baseRevision: b.revision,
    ));
  }

  /// Enter splits the block; the new one continues a list.
  void _onText(_TwBlock b) {
    final raw = b.text.text;
    if (!raw.startsWith(_mark)) {
      // The mark was deleted. Same text otherwise: Backspace at the start.
      final atStart = raw == b.saved;
      b.setValue(raw, atStart ? 0 : raw.length);
      if (atStart) {
        _backspaceAtStart(b);
        return;
      }
    } else if (b.text.selection.isCollapsed && b.text.selection.baseOffset == 0) {
      // The caret never sits before the mark.
      b.text.selection = const TextSelection.collapsed(offset: 1);
    }
    final t = b.value;
    if (t == b.saved) return;
    // One undo step per typing run on a line.
    final now = DateTime.now();
    if (!_restoring && (_typingIn != b || now.difference(_typedAt) > const Duration(seconds: 2))) {
      final before = _snapshot();
      final i = _blocks.indexOf(b);
      if (i >= 0) before[i] = before[i].withText(b.saved);
      _undo.add(before);
      if (_undo.length > 100) _undo.removeAt(0);
      _redo.clear();
    }
    _typingIn = b;
    _typedAt = now;
    b.saved = t;
    final nl = t.indexOf('\n');
    if (nl < 0) {
      _save(b);
      return;
    }
    final before = t.substring(0, nl);
    final after = t.substring(nl + 1);
    final list = b.type == 'bulleted' || b.type == 'checklist';
    if (list && before.isEmpty) {
      // Enter on an empty list item ends the list.
      b.type = 'paragraph';
      b.setValue(after, 0);
      b.saved = after;
      _save(b);
      setState(() {});
      return;
    }
    b.setValue(before, before.length);
    b.saved = before;
    _save(b);
    _typingIn = null;
    _insertAfter(b, list ? b.type : 'paragraph', after);
  }

  _TwBlock _insertAfter(_TwBlock? anchor, String type, String text, {String origin = 'student', int? atMs, bool focus = true}) {
    final i = anchor == null ? _blocks.length - 1 : _blocks.indexOf(anchor);
    final prev = i >= 0 ? _blocks[i].position : null;
    final next = i + 1 < _blocks.length ? _blocks[i + 1].position : null;
    final b = _TwBlock(
      id: OctoNotesApi.newId(),
      type: type,
      text: text,
      position: positionBetween(prev, next),
      origin: origin,
      atMs: atMs ?? hub._elapsedMs,
    );
    setState(() => _add(b, at: i + 1, save: true));
    if (focus && !b.readOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        b.focus.requestFocus();
        b.text.selection = const TextSelection.collapsed(offset: 1);
      });
    }
    return b;
  }

  _TwBlock? get _target => _focused ?? (_blocks.isEmpty ? null : _blocks.last);

  void _setType(String type) {
    final b = _target;
    if (b == null || b.readOnly) return;
    HapticFeedback.selectionClick();
    _record();
    setState(() => b.type = b.type == type ? 'paragraph' : type);
    _save(b);
  }

  void _quote([TranscriptLine? line]) {
    final l = line ?? hub._live.lines.lastOrNull;
    if (l == null) {
      _snack(context, 'No transcript yet.');
      return;
    }
    HapticFeedback.mediumImpact();
    _record();
    final b = _insertAfter(_target, 'quote', l.text, origin: 'fromTranscript', atMs: l.startMs, focus: false);
    // Keep typing under the quote.
    _insertAfter(b, 'paragraph', '');
  }

  Future<void> _star() async {
    final b = _target;
    if (b == null) return;
    setState(() => b.important = !b.important);
    if (!b.important) {
      HapticFeedback.selectionClick();
      return;
    }
    unawaited(PairHaptics.success());
    final api = hub.ref.read(octoNotesApiProvider);
    if (api != null && hub.widget.sessionId != null) {
      unawaited(api.addMarker(hub.widget.sessionId!, 'important', b.atMs ?? hub._elapsedMs).catchError((_) => <String, dynamic>{}));
    }
  }

  Future<void> _expand() async {
    final b = _target;
    final api = hub.ref.read(octoNotesApiProvider);
    if (b == null || b.value.trim().isEmpty) {
      _snack(context, 'Write a line first, then AI adds detail from the lecture.');
      return;
    }
    if (api == null || _sync == null) {
      _snack(context, 'Sign in to use AI on your notes.');
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _aiFor = b;
      _aiText = '';
    });
    try {
      await _sync!.flush(); // the server needs the block before it can expand it
      String? suggestion;
      await for (final e in api.suggest(hub.widget.sessionId!, b.id, 'expand')) {
        if (!mounted) return;
        switch (e.event) {
          case 'delta':
            setState(() => _aiText = '${_aiText ?? ''}${e.data['text'] ?? ''}');
          case 'result':
            suggestion = (e.data['suggestion'] as Map?)?['id'] as String?;
          case 'error':
            throw StateError('${e.data['message'] ?? 'AI could not help this time.'}');
        }
      }
      if (suggestion == null) throw StateError('AI could not help this time.');
      final block = await api.applySuggestion(suggestion, 'insertBelow');
      if (!mounted) return;
      final added = _TwBlock.fromJson(block);
      _record();
      setState(() => _add(added, at: _blocks.indexOf(b) + 1));
      unawaited(HapticFeedback.mediumImpact());
    } on NotesApiException catch (e) {
      if (mounted) _snack(context, e.isInsufficientCredits ? 'Not enough OctoCredits for AI.' : e.message);
    } on Object catch (e) {
      if (mounted) _snack(context, '$e'.replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _aiFor = null;
          _aiText = null;
        });
      }
    }
  }

  void _toggleCheck(_TwBlock b) {
    HapticFeedback.selectionClick();
    _record();
    setState(() => b.checked = !b.checked);
    _save(b);
  }

  @override
  void dispose() {
    unawaited(_sync?.flush());
    _applied?.cancel();
    _sync
      ?..removeListener(_changed)
      ..dispose();
    for (final b in _blocks) {
      b.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      backgroundColor: scheme.surface,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(CockpitSpacing.xs, CockpitSpacing.xs, CockpitSpacing.md, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      hub._open(_HubView.cards);
                    },
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(hub._live.title ?? 'Typewriter',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        _SyncLabel(sync: _sync),
                      ],
                    ),
                  ),
                  _RecordingPill(state: hub),
                  IconButton(
                    tooltip: 'Magic Pencil',
                    icon: Icon(Icons.gesture_rounded, color: scheme.onSurfaceVariant),
                    onPressed: () => hub._open(_HubView.pencil),
                  ),
                ],
              ),
            ),
            _TranscriptTicker(lines: hub._live.lines, onTap: _quote),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(CockpitSpacing.lg, CockpitSpacing.sm, CockpitSpacing.lg, 0),
                          sliver: SliverList.list(
                            children: [
                              for (final b in _blocks) ...[
                                _BlockRow(
                                  key: ValueKey(b.id),
                                  block: b,
                                  onCheck: () => _toggleCheck(b),
                                  onRemove: () {
                                    _record();
                                    HapticFeedback.selectionClick();
                                    _remove(b);
                                  },
                                ),
                                if (_aiFor == b) _AiDraft(text: _aiText ?? ''),
                              ],
                            ],
                          ),
                        ),
                        // The rest of the page: a tap anywhere types there.
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _typeAtEnd,
                            child: const SizedBox(height: 160),
                          ),
                        ),
                      ],
                    ),
            ),
            AnimatedSlide(
              offset: keyboard || _focused != null ? Offset.zero : const Offset(0, 0.2),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: _FormatBar(
                type: _target?.type,
                important: _target?.important ?? false,
                aiBusy: _aiFor != null,
                canUndo: _undo.isNotEmpty,
                canRedo: _redo.isNotEmpty,
                onUndo: () => _undoRedo(true),
                onRedo: () => _undoRedo(false),
                onType: _setType,
                onStar: _star,
                onQuote: _quote,
                onAi: _expand,
                onDone: () {
                  HapticFeedback.lightImpact();
                  FocusScope.of(context).unfocus();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockRow extends StatelessWidget {
  const _BlockRow({super.key, required this.block, required this.onCheck, required this.onRemove});
  final _TwBlock block;
  final VoidCallback onCheck;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gold = CockpitColors.brand.tertiary;
    final b = block;
    final heading = b.type.startsWith('h');
    final quote = b.type == 'quote' || b.type == 'transcriptExcerpt';
    final ai = b.origin == 'aiInsertedByStudent';
    final style = (heading ? theme.textTheme.titleLarge : theme.textTheme.bodyLarge)?.copyWith(
      fontWeight: heading ? FontWeight.w700 : FontWeight.w400,
      height: 1.45,
      color: quote ? scheme.onSurfaceVariant : scheme.onSurface,
      decoration: b.type == 'checklist' && b.checked ? TextDecoration.lineThrough : null,
    );

    Widget field = TextField(
      controller: b.text,
      focusNode: b.focus,
      readOnly: b.readOnly,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      textCapitalization: TextCapitalization.sentences,
      style: style,
      cursorColor: scheme.primary,
      // No box of any kind, focused or not (the app theme draws one).
      decoration: const InputDecoration(
        isCollapsed: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(vertical: 6),
      ),
    );
    // The hint sits over the field: the field always holds the mark.
    final hint = heading ? 'Heading' : (b.type == 'paragraph' ? 'Type your notes…' : '');
    field = Stack(
      children: [
        field,
        if (hint.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: ListenableBuilder(
                listenable: b.text,
                builder: (_, _) => b.value.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(hint, style: style?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.5))),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
      ],
    );

    Widget? lead;
    if (b.type == 'bulleted') {
      lead = Padding(
        padding: const EdgeInsets.only(top: 10, right: 10),
        child: Container(width: 6, height: 6, decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle)),
      );
    } else if (b.type == 'checklist') {
      lead = GestureDetector(
        onTap: onCheck,
        child: Padding(
          padding: const EdgeInsets.only(top: 2, right: 8),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (c, a) => ScaleTransition(scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack), child: c),
            child: Icon(
              b.checked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              key: ValueKey(b.checked),
              size: 22,
              color: b.checked ? CockpitColors.brand.success : scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    Widget row = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [?lead, Expanded(child: field)]);
    if (quote || ai) {
      row = Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
        decoration: BoxDecoration(
          color: (ai ? scheme.primary : gold).withValues(alpha: 0.07),
          border: Border(left: BorderSide(color: ai ? scheme.primary : gold, width: 3)),
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Tag(text: ai ? 'AI' : (b.atMs == null ? 'Lecture' : _clock(b.atMs!)), color: ai ? scheme.primary : gold),
                const Spacer(),
                Semantics(
                  button: true,
                  label: 'Remove',
                  child: InkResponse(
                    onTap: onRemove,
                    radius: 18,
                    child: Icon(Icons.close_rounded, size: 18, color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            row,
          ],
        ),
      );
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 12), child: child),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: EdgeInsets.symmetric(vertical: heading ? 8 : 3, horizontal: b.important ? 8 : 0),
        decoration: BoxDecoration(
          color: b.important ? gold.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: row),
            AnimatedScale(
              scale: b.important ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              child: Padding(
                padding: const EdgeInsets.only(left: 6, top: 4),
                child: Icon(Icons.star_rounded, size: 16, color: gold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
      );
}

/// The AI's words arriving, with a soft shimmer until they're done.
class _AiDraft extends StatefulWidget {
  const _AiDraft({required this.text});
  final String text;

  @override
  State<_AiDraft> createState() => _AiDraftState();
}

class _AiDraftState extends State<_AiDraft> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
      ),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) => ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (r) => LinearGradient(
            colors: [Colors.transparent, CockpitColors.brand.tertiary.withValues(alpha: 0.35), Colors.transparent],
            stops: [_c.value - 0.2, _c.value, _c.value + 0.2],
          ).createShader(r),
          child: child,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.auto_awesome_rounded, size: 16, color: CockpitColors.brand.tertiary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.text.isEmpty ? 'Adding detail from the lecture…' : widget.text,
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The newest transcript line; tap to quote it into the notes.
class _TranscriptTicker extends StatelessWidget {
  const _TranscriptTicker({required this.lines, required this.onTap});
  final List<TranscriptLine> lines;
  final ValueChanged<TranscriptLine?> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gold = CockpitColors.brand.tertiary;
    final l = lines.lastOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(CockpitSpacing.md, CockpitSpacing.xs, CockpitSpacing.md, 0),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: l == null ? null : () => onTap(l),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: gold.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.format_quote_rounded, color: gold, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 420),
                    transitionBuilder: (c, a) => ClipRect(
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0, 0.8), end: Offset.zero)
                            .animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
                        child: FadeTransition(opacity: a, child: c),
                      ),
                    ),
                    child: Column(
                      key: ValueKey(l?.id),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l == null ? 'Live transcript' : '${_clock(l.startMs)} · tap to add',
                            style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                        Text(l?.text ?? 'The lecture appears here as it is said.',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ),
                Icon(Icons.add_rounded, color: l == null ? scheme.outlineVariant : gold),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sits on top of the keyboard.
class _FormatBar extends StatelessWidget {
  const _FormatBar({
    required this.type,
    required this.important,
    required this.aiBusy,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    required this.onType,
    required this.onStar,
    required this.onQuote,
    required this.onAi,
    required this.onDone,
  });

  final String? type;
  final bool important;
  final bool aiBusy;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final ValueChanged<String> onType;
  final VoidCallback onStar;
  final VoidCallback onQuote;
  final VoidCallback onAi;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gold = CockpitColors.brand.tertiary;
    Widget b(IconData icon, String tip, VoidCallback? onTap, {bool on = false, Color? color}) => Tooltip(
          message: tip,
          child: Semantics(
            button: true,
            selected: on,
            label: tip,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 42,
                height: 38,
                decoration: BoxDecoration(
                  color: on ? scheme.primary.withValues(alpha: 0.16) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon,
                    size: 21,
                    color: onTap == null ? scheme.onSurface.withValues(alpha: 0.25) : color ?? (on ? scheme.primary : scheme.onSurface)),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            b(Icons.undo_rounded, 'Undo', canUndo ? onUndo : null),
            b(Icons.redo_rounded, 'Redo', canRedo ? onRedo : null),
            Container(width: 1, height: 22, margin: const EdgeInsets.symmetric(horizontal: 4), color: scheme.outlineVariant),
            b(Icons.title_rounded, 'Heading', () => onType('h2'), on: type == 'h2'),
            b(Icons.format_list_bulleted_rounded, 'Bullet', () => onType('bulleted'), on: type == 'bulleted'),
            b(Icons.check_box_outlined, 'Checklist', () => onType('checklist'), on: type == 'checklist'),
            b(important ? Icons.star_rounded : Icons.star_outline_rounded, 'Important', onStar, color: gold, on: important),
            b(Icons.format_quote_rounded, 'Quote the lecture', onQuote),
            const SizedBox(width: 4),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: aiBusy ? null : onAi,
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(colors: [scheme.primary.withValues(alpha: 0.32), gold.withValues(alpha: 0.26)]),
                ),
                child: Row(
                  children: [
                    aiBusy
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome_rounded, size: 18, color: Colors.white),
                    const SizedBox(width: 6),
                    const Text('Expand', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            b(Icons.keyboard_hide_rounded, 'Hide keyboard', onDone),
          ],
        ),
      ),
    );
  }
}

/// "Saved" / "Saving…" / "Offline · will send".
class _SyncLabel extends StatelessWidget {
  const _SyncLabel({required this.sync});
  final BlockSyncEngine? sync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = sync?.status;
    final (icon, text, color) = switch (s) {
      null => (Icons.edit_note_rounded, 'Typewriter', theme.colorScheme.onSurfaceVariant),
      SyncStatus.offline => (Icons.cloud_off_rounded, 'Offline · will send', CockpitColors.brand.warning),
      SyncStatus.conflict => (Icons.call_split_rounded, 'Edited elsewhere · both kept', CockpitColors.brand.warning),
      SyncStatus.saving || SyncStatus.saved => (Icons.cloud_upload_outlined, 'Saving…', theme.colorScheme.onSurfaceVariant),
      _ => (Icons.cloud_done_outlined, 'Saved', CockpitColors.brand.success),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Row(
        key: ValueKey(text),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(text, style: theme.textTheme.labelSmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// A compact "● 12:34" for headers.
class _RecordingPill extends StatelessWidget {
  const _RecordingPill({required this.state});
  final _LiveSessionHubPageState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = state._recorder;
    final recording = r?.isRecording ?? state._live.isRecording;
    final name = r != null ? 'This phone' : (state._live.recorderName ?? 'Your phone');
    return Semantics(
      button: true,
      label: 'Open the recording',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          FocusScope.of(context).unfocus();
          state._open(_HubView.cards);
        },
        child: _pill(theme, scheme, recording, name),
      ),
    );
  }

  Widget _pill(ThemeData theme, ColorScheme scheme, bool recording, String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BlinkDot(color: recording ? scheme.primary : scheme.onSurfaceVariant, blink: recording),
          const SizedBox(width: 6),
          Text(recording ? _clock(state._elapsedMs) : 'Paused',
              style: theme.textTheme.labelMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          Semantics(label: '$name recording', child: const SizedBox.shrink()),
        ],
      ),
    );
  }
}

// ===========================================================================
// Pencil on a phone held upright: ask to turn it.
// ===========================================================================
class _RotatePrompt extends StatefulWidget {
  const _RotatePrompt({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<_RotatePrompt> createState() => _RotatePromptState();
}

class _RotatePromptState extends State<_RotatePrompt> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              left: CockpitSpacing.xs,
              top: CockpitSpacing.xs,
              child: IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back_rounded), onPressed: widget.onBack),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 150,
                      height: 150,
                      child: AnimatedBuilder(
                        animation: _c,
                        builder: (_, _) => CustomPaint(painter: _RotatePainter(_c.value, scheme.onSurface, scheme.primary)),
                      ),
                    ),
                    const SizedBox(height: CockpitSpacing.xl),
                    Text('Turn your phone to draw',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: CockpitSpacing.sm),
                    Text('Magic Pencil works sideways: more page, tools on both sides.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: CockpitSpacing.xl),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.mic_rounded, size: 14, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text('Recording keeps going while you turn it',
                            style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
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

/// A phone outline turning a quarter to the left, with a red squiggle on it
/// and a gold arrow showing the way.
class _RotatePainter extends CustomPainter {
  _RotatePainter(this.t, this.ink, this.red);
  final double t;
  final Color ink;
  final Color red;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final turn = Curves.easeInOutCubic.transform(((t - 0.25) / 0.35).clamp(0.0, 1.0));
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-math.pi / 2 * turn);
    final body = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 56, height: 104), const Radius.circular(12));
    canvas.drawRRect(body, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..color = ink);
    final squiggle = Path()
      ..moveTo(-14, 14)
      ..quadraticBezierTo(-4, -18, 6, 4)
      ..quadraticBezierTo(12, 18, 16, -6);
    canvas.drawPath(squiggle, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..color = red.withValues(alpha: 0.4 + 0.6 * turn));
    canvas.restore();
    final gold = CockpitColors.brand.tertiary.withValues(alpha: 1 - turn * 0.7);
    final arc = Rect.fromCircle(center: c, radius: 66);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..color = gold;
    canvas.drawArc(arc, -math.pi / 2.6, -0.9, false, p);
    final tip = c + Offset(math.cos(-math.pi / 2.6 - 0.9), math.sin(-math.pi / 2.6 - 0.9)) * 66;
    canvas.drawLine(tip, tip + const Offset(10, -4), p);
    canvas.drawLine(tip, tip + const Offset(4, 10), p);
  }

  @override
  bool shouldRepaint(covariant _RotatePainter old) => old.t != t;
}

/// One line as it was, for undo.
class _Snap {
  const _Snap(this.id, this.type, this.text, this.position, this.checked, this.origin, this.atMs, this.important);

  factory _Snap.of(_TwBlock b) => _Snap(b.id, b.type, b.value, b.position, b.checked, b.origin, b.atMs, b.important);

  final String id;
  final String type;
  final String text;
  final String position;
  final bool checked;
  final String origin;
  final int? atMs;
  final bool important;

  _Snap withText(String t) => _Snap(id, type, t, position, checked, origin, atMs, important);
}
