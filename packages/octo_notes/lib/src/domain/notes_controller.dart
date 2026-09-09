import 'dart:async';

import 'package:flutter/foundation.dart';

import 'notes_models.dart';

/// The in-memory, local-first session store for Panel 5 (Typewriter).
///
/// Design rules it enforces (spec §2, §14, §18, §23):
/// * The student's typed [TypedBlock]s are the **authoritative** layer.
/// * AI never mutates blocks — it only produces separate [AiSuggestion]s that
///   the student must explicitly approve.
/// * Every edit commits to memory **immediately** and never waits on a network
///   (there is no network here yet — sync is simulated at block level).
/// * Structural edits are undoable.
class NotesController extends ChangeNotifier {
  NotesController({required this.sessionId, this.device = 'MacBook Pro'}) {
    _seed();
  }

  final String sessionId;
  final String device;

  // --- document ------------------------------------------------------------
  String docTitle = 'Cellular Respiration';
  final List<TypedBlock> _blocks = [];
  final List<AiSuggestion> _suggestions = [];

  List<TypedBlock> get blocks => List.unmodifiable(_blocks);
  List<AiSuggestion> get suggestions => List.unmodifiable(_suggestions);

  // --- selection / focus ---------------------------------------------------
  final Set<String> _selected = {};
  String? _focused;
  Set<String> get selected => _selected;
  String? get focusedId => _focused;
  bool isSelected(String id) => _selected.contains(id);
  int get selectedCount => _selected.length;

  // --- session status ------------------------------------------------------
  bool recording = true;
  bool magicPencil = false;
  bool _offline = false;
  bool _hadOfflineEdits = false;
  SyncState _sync = SyncState.synced;
  bool get offline => _offline;
  SyncState get sync => _sync;
  Timer? _saveTimer;

  int _audioSeconds = 18 * 60 + 44; // "18:44"
  String get audioTime => _fmt(_audioSeconds);

  // --- undo / redo (structural) -------------------------------------------
  final List<_Doc> _undo = [];
  final List<_Doc> _redo = [];
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  // -------------------------------------------------------------------------
  // Selection & focus
  // -------------------------------------------------------------------------
  void setFocused(String? id) {
    if (_focused == id) return;
    _focused = id;
    notifyListeners();
  }

  void selectOnly(String id) {
    _selected
      ..clear()
      ..add(id);
    notifyListeners();
  }

  void toggleSelect(String id) {
    if (!_selected.remove(id)) _selected.add(id);
    notifyListeners();
  }

  void clearSelection() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Editing (immediate, never networked)
  // -------------------------------------------------------------------------
  void updateText(String id, String text) {
    final i = _indexOf(id);
    if (i < 0) return;
    _blocks[i] = _blocks[i].copyWith(
      text: text,
      modifiedAt: DateTime.now(),
      revision: _blocks[i].revision + 1,
      syncState: _offline ? SyncState.offline : SyncState.saving,
    );
    _markDirty(notify: false);
    notifyListeners();
  }

  void toggleChecked(String id) {
    final i = _indexOf(id);
    if (i < 0) return;
    _blocks[i] = _blocks[i].copyWith(checked: !_blocks[i].checked);
    _markDirty();
  }

  void setType(String id, BlockType type) {
    final i = _indexOf(id);
    if (i < 0) return;
    _pushUndo();
    _blocks[i] = _blocks[i].copyWith(type: type, modifiedAt: DateTime.now());
    _markDirty();
  }

  void indent(String id, int delta) {
    final i = _indexOf(id);
    if (i < 0) return;
    _pushUndo();
    final next = (_blocks[i].indent + delta).clamp(0, 4);
    _blocks[i] = _blocks[i].copyWith(indent: next);
    _markDirty();
  }

  // -------------------------------------------------------------------------
  // Structure
  // -------------------------------------------------------------------------
  String insertBlockAfter(String afterId, {BlockType type = BlockType.paragraph}) {
    _pushUndo();
    final i = _indexOf(afterId);
    final id = _newId('b');
    final block = _student(id, type: type, text: '');
    _blocks.insert(i < 0 ? _blocks.length : i + 1, block);
    _focused = id;
    _markDirty();
    return id;
  }

  /// Add a block converted from Magic Pencil ink (spec §8). Origin stays
  /// student; a backlink to the source page/time is kept as the block source.
  String addConvertedFromInk(
    String text, {
    required String backlink,
    String? audioTimestamp,
  }) {
    _pushUndo();
    final id = _newId('b');
    _blocks.add(TypedBlock(
      id: id,
      sessionId: sessionId,
      parentSection: '',
      type: BlockType.paragraph,
      text: text,
      origin: BlockOrigin.student,
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
      device: device,
      audioTimestamp: audioTimestamp,
      source: SourceRef(material: 'Magic Pencil', location: backlink),
    ));
    _markDirty();
    return id;
  }

  /// Insert an approved AI answer as a new AI-origin block (Panel 9 §10, §13).
  /// Keeps its source references; origin stays inspectable.
  String insertAiBlock(String text, {SourceRef? source}) {
    _pushUndo();
    final id = _newId('b');
    _blocks.add(TypedBlock(
      id: id,
      sessionId: sessionId,
      parentSection: '',
      type: BlockType.paragraph,
      text: text,
      origin: BlockOrigin.aiInsertedByStudent,
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
      device: device,
      source: source,
      aiSources: source != null ? [source] : const [],
    ));
    _markDirty();
    return id;
  }

  /// Add a source-linked block from a slide/material (Panel 8 §12). The block
  /// keeps a `Material · Slide N` reference that resolves even if it is moved.
  String addFromSlide(String material, String slide, {String? excerpt}) {
    _pushUndo();
    final id = _newId('b');
    _blocks.add(TypedBlock(
      id: id,
      sessionId: sessionId,
      parentSection: '',
      type: BlockType.paragraph,
      text: excerpt ?? 'From $material · $slide',
      origin: BlockOrigin.student,
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
      device: device,
      source: SourceRef(material: material, location: slide),
    ));
    _markDirty();
    return id;
  }

  /// Add a source-linked block from a transcript selection (Panel 7 §11–12).
  /// The excerpt is quoted; the block keeps a traceable transcript reference.
  String addFromTranscript(String speaker, String time, String excerpt) {
    _pushUndo();
    final id = _newId('b');
    _blocks.add(TypedBlock(
      id: id,
      sessionId: sessionId,
      parentSection: '',
      type: BlockType.quote,
      text: '"$excerpt"',
      origin: BlockOrigin.student,
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
      device: device,
      audioTimestamp: time,
      source: SourceRef(material: 'Transcript', location: '$speaker · $time'),
    ));
    _markDirty();
    return id;
  }

  String addBlockAtEnd({BlockType type = BlockType.paragraph}) {
    _pushUndo();
    final id = _newId('b');
    _blocks.add(_student(id, type: type, text: ''));
    _focused = id;
    _markDirty();
    return id;
  }

  void deleteBlock(String id) {
    final i = _indexOf(id);
    if (i < 0) return;
    _pushUndo();
    _blocks.removeAt(i);
    _suggestions.removeWhere((s) => s.sourceBlockId == id);
    _selected.remove(id);
    if (_focused == id) _focused = null;
    _markDirty();
  }

  void duplicateBlock(String id) {
    final i = _indexOf(id);
    if (i < 0) return;
    _pushUndo();
    final src = _blocks[i];
    final copy = src.copyWith(modifiedAt: DateTime.now());
    // copyWith keeps the id; build a fresh block with a new id but same content.
    _blocks.insert(
      i + 1,
      TypedBlock(
        id: _newId('b'),
        sessionId: sessionId,
        parentSection: src.parentSection,
        type: copy.type,
        text: copy.text,
        checked: copy.checked,
        indent: copy.indent,
        origin: copy.origin,
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
        device: device,
        audioTimestamp: copy.audioTimestamp,
        transcriptAnchor: copy.transcriptAnchor,
        source: copy.source,
        aiSources: copy.aiSources,
      ),
    );
    _markDirty();
  }

  void moveUp(String id) {
    final i = _indexOf(id);
    if (i <= 0) return;
    _pushUndo();
    final b = _blocks.removeAt(i);
    _blocks.insert(i - 1, b);
    _markDirty();
  }

  void moveDown(String id) {
    final i = _indexOf(id);
    if (i < 0 || i >= _blocks.length - 1) return;
    _pushUndo();
    final b = _blocks.removeAt(i);
    _blocks.insert(i + 1, b);
    _markDirty();
  }

  /// [newIndex] is already adjusted for the removed item (onReorderItem).
  void reorder(int oldIndex, int newIndex) {
    _pushUndo();
    final b = _blocks.removeAt(oldIndex);
    _blocks.insert(newIndex, b);
    _markDirty();
  }

  // -------------------------------------------------------------------------
  // Links & Study Studio
  // -------------------------------------------------------------------------
  void setSource(String id, SourceRef? source) {
    final i = _indexOf(id);
    if (i < 0) return;
    _blocks[i] =
        _blocks[i].copyWith(source: source, clearSource: source == null);
    _markDirty();
  }

  void toggleStudyStudioSelection(String id) {
    final i = _indexOf(id);
    if (i < 0) return;
    _blocks[i] =
        _blocks[i].copyWith(studyStudioSelected: !_blocks[i].studyStudioSelected);
    _markDirty();
  }

  int get studyStudioCount =>
      _blocks.where((b) => b.studyStudioSelected).length;

  // -------------------------------------------------------------------------
  // AI suggestions (separate layer — never mutate student blocks)
  // -------------------------------------------------------------------------
  AiSuggestion requestSuggestion(
    String blockId,
    AiAction action, {
    String? selectedText,
  }) {
    final i = _indexOf(blockId);
    final base = i >= 0 ? _blocks[i].text : '';
    final subject = (selectedText ?? base).trim();
    final s = AiSuggestion(
      id: _newId('s'),
      sourceBlockId: blockId,
      action: action,
      contextLabel: i >= 0 && _blocks[i].source != null
          ? 'Based on transcript and ${_blocks[i].source!.location}'
          : 'Based on transcript',
      body: _generate(action, subject),
      sources: i >= 0 && _blocks[i].source != null
          ? [_blocks[i].source!]
          : const [SourceRef(material: 'Week 4 Slides', location: 'Slide 7')],
      createdAt: DateTime.now(),
    );
    _suggestions.add(s);
    notifyListeners();
    return s;
  }

  List<AiSuggestion> suggestionsFor(String blockId) =>
      _suggestions.where((s) => s.sourceBlockId == blockId).toList();

  void dismissSuggestion(String id) {
    _suggestions.removeWhere((s) => s.id == id);
    notifyListeners();
  }

  /// Approve → insert a NEW AI-origin block below the source (spec §7, §14).
  void approveInsertBelow(AiSuggestion s, {BlockType type = BlockType.paragraph}) {
    final i = _indexOf(s.sourceBlockId);
    _pushUndo();
    final block = TypedBlock(
      id: _newId('b'),
      sessionId: sessionId,
      parentSection: i >= 0 ? _blocks[i].parentSection : '',
      type: type,
      text: s.body,
      origin: BlockOrigin.aiInsertedByStudent,
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
      device: device,
      aiSources: s.sources,
      source: s.sources.isNotEmpty ? s.sources.first : null,
    );
    _blocks.insert(i < 0 ? _blocks.length : i + 1, block);
    _suggestions.removeWhere((x) => x.id == s.id);
    _markDirty();
  }

  void approveAddAsExplanation(AiSuggestion s) =>
      approveInsertBelow(s, type: BlockType.example);

  /// Replace the source block's text with the suggestion. Allowed because the
  /// student explicitly approved — the block now carries AI origin + sources.
  void approveReplaceSelection(AiSuggestion s) {
    final i = _indexOf(s.sourceBlockId);
    if (i < 0) return;
    _pushUndo();
    _blocks[i] = _blocks[i].copyWith(
      text: s.body,
      origin: BlockOrigin.aiInsertedByStudent,
      aiSources: s.sources,
      modifiedAt: DateTime.now(),
      revision: _blocks[i].revision + 1,
    );
    _suggestions.removeWhere((x) => x.id == s.id);
    _markDirty();
  }

  /// Whether a mostly-keyword block should offer "Expand these keywords?".
  bool showsKeywordExpand(TypedBlock b) {
    if (!b.type.isTextEditable || b.isAi) return false;
    final lines = b.text.trim().split(RegExp(r'[\n,]'));
    if (lines.length < 2) return false;
    // Keyword-ish: several short fragments, none a full sentence.
    final shortish = lines.where((l) {
      final w = l.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty);
      return w.isNotEmpty && w.length <= 3;
    }).length;
    final hasSuggestion =
        _suggestions.any((s) => s.sourceBlockId == b.id && s.action == AiAction.expandKeywords);
    return shortish >= 2 && !hasSuggestion;
  }

  // -------------------------------------------------------------------------
  // AI organization preview (Panel 11) — never auto-applied while typing
  // -------------------------------------------------------------------------
  int get organizationChangesReady =>
      _blocks.length >= 4 ? 6 : 0;

  // -------------------------------------------------------------------------
  // Sync / offline (spec §18, §19)
  // -------------------------------------------------------------------------
  void goOffline() {
    _saveTimer?.cancel();
    _offline = true;
    _sync = SyncState.offline;
    notifyListeners();
  }

  void reconnect() {
    _offline = false;
    _sync = SyncState.reconnecting;
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 900), () {
      _sync = _hadOfflineEdits ? SyncState.conflict : SyncState.synced;
      notifyListeners();
    });
  }

  /// Resolve a sync conflict by keeping both versions (spec §19).
  void resolveConflictKeepBoth() {
    _hadOfflineEdits = false;
    _sync = SyncState.synced;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Undo / redo
  // -------------------------------------------------------------------------
  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_snapshot());
    _restore(_undo.removeLast());
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_snapshot());
    _restore(_redo.removeLast());
    notifyListeners();
  }

  void setMagicPencil(bool value) {
    if (magicPencil == value) return;
    magicPencil = value;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // internals
  // -------------------------------------------------------------------------
  int _indexOf(String id) => _blocks.indexWhere((b) => b.id == id);

  TypedBlock _student(String id, {required BlockType type, required String text}) {
    return TypedBlock(
      id: id,
      sessionId: sessionId,
      parentSection: '',
      type: type,
      text: text,
      origin: BlockOrigin.student,
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
      device: device,
      audioTimestamp: recording ? _nextAudioTime() : null,
      syncState: _offline ? SyncState.offline : SyncState.saving,
    );
  }

  String _nextAudioTime() {
    final t = _fmt(_audioSeconds);
    _audioSeconds += 7;
    return t;
  }

  void _markDirty({bool notify = true}) {
    if (_offline) {
      _hadOfflineEdits = true;
      _sync = SyncState.offline;
    } else {
      _sync = SyncState.saving;
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 650), () {
        _sync = SyncState.synced;
        notifyListeners();
      });
    }
    if (notify) notifyListeners();
  }

  void _pushUndo() {
    _undo.add(_snapshot());
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
  }

  _Doc _snapshot() => _Doc(List.of(_blocks), List.of(_suggestions), docTitle);

  void _restore(_Doc doc) {
    _blocks
      ..clear()
      ..addAll(doc.blocks);
    _suggestions
      ..clear()
      ..addAll(doc.suggestions);
    docTitle = doc.title;
  }

  static int _seqCounter = 0;
  String _newId(String prefix) => '$prefix${_seqCounter++}';

  static String _fmt(int total) {
    final m = (total ~/ 60).toString();
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Canned, mock "AI" text. Real expansion (transcript + materials) plugs in
  /// here later; today it is deterministic so the preview flow can be built.
  String _generate(AiAction action, String subject) {
    final s = subject.replaceAll('\n', ', ').trim();
    switch (action) {
      case AiAction.expandKeywords:
        if (s.toLowerCase().contains('glycolysis')) {
          return 'Glycolysis occurs in the cytoplasm and produces a net gain '
              'of two ATP. It does not directly require oxygen.';
        }
        return 'These keywords describe how $s connect: each step follows from '
            'the previous one to complete the process.';
      case AiAction.expand:
        return 'In more detail: $s. The electron transport chain creates a '
            'proton gradient that drives ATP synthase to produce ATP.';
      case AiAction.explain:
        return '$s — in other words, this describes the underlying mechanism '
            'the professor referenced in the transcript.';
      case AiAction.simplify:
        return 'Put simply: $s, which just means energy is released and stored.';
      case AiAction.define:
        return '$s: a defined term from this lecture, with its meaning and role '
            'in the wider process.';
      case AiAction.example:
        return 'For example, $s can be seen when a cell breaks down glucose to '
            'release usable energy.';
      case AiAction.research:
        return 'Related reading on "$s": see the linked slide and two external '
            'references gathered for this topic.';
      case AiAction.compare:
        return 'Compared with the professor\'s explanation, "$s" aligns but adds '
            'the detail about the proton gradient.';
    }
  }

  // -------------------------------------------------------------------------
  // Seed (resembles the Panel 5 mock)
  // -------------------------------------------------------------------------
  void _seed() {
    final now = DateTime.now();
    TypedBlock b(
      String id,
      BlockType type,
      String text, {
      BlockOrigin origin = BlockOrigin.student,
      String? ts,
      SourceRef? source,
      int indent = 0,
    }) {
      return TypedBlock(
        id: id,
        sessionId: sessionId,
        parentSection: 'Cellular Respiration',
        type: type,
        text: text,
        indent: indent,
        origin: origin,
        createdAt: now,
        modifiedAt: now,
        device: device,
        audioTimestamp: ts,
        source: source,
      );
    }

    _blocks.addAll([
      b('b${_seqCounter++}', BlockType.h2, '1. Glycolysis', ts: '18:20'),
      b('b${_seqCounter++}', BlockType.bulleted, 'Occurs in the cytoplasm',
          indent: 1, ts: '18:22'),
      b('b${_seqCounter++}', BlockType.bulleted,
          'Glucose splits into two pyruvate molecules',
          indent: 1, ts: '18:25'),
      b('b${_seqCounter++}', BlockType.examHint, 'Net gain: 2 ATP and 2 NADH',
          ts: '18:28'),
      b('b${_seqCounter++}', BlockType.h2, '2. Electron Transport Chain',
          ts: '18:31'),
      b('b${_seqCounter++}', BlockType.paragraph,
          'ETC — proton gradient — ATP synthase',
          ts: '18:32',
          source: const SourceRef(material: 'Week 4 Slides', location: 'Slide 7')),
    ]);

    // A pending AI suggestion attached to the ETC block (like the mock).
    final etcId = _blocks.last.id;
    _suggestions.add(AiSuggestion(
      id: _newId('s'),
      sourceBlockId: etcId,
      action: AiAction.expand,
      contextLabel: 'Based on transcript and Slide 7',
      body: 'The electron transport chain creates a proton gradient that drives '
          'ATP synthase to produce ATP.',
      sources: const [SourceRef(material: 'Week 4 Slides', location: 'Slide 7')],
      createdAt: now,
    ));
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}

class _Doc {
  _Doc(this.blocks, this.suggestions, this.title);
  final List<TypedBlock> blocks;
  final List<AiSuggestion> suggestions;
  final String title;
}
