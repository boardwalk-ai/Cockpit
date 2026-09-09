import 'package:flutter/material.dart';

import 'ink_models.dart';

/// Local-first vector-ink store for Panel 6 (Magic Pencil).
///
/// Rules it enforces (spec §3): the original ink is the authoritative,
/// unchangeable Student Notes layer. Recognition and AI live in a separate
/// layer and never rewrite, flatten, move, or clean up ink without explicit
/// approval. Stroke rendering/saving is immediate and never networked.
class InkController extends ChangeNotifier {
  InkController() {
    _seed();
  }

  // --- pages ---------------------------------------------------------------
  final List<InkPage> _pages = [];
  int _current = 0;
  List<InkPage> get pages => List.unmodifiable(_pages);
  int get pageIndex => _current;
  InkPage get page => _pages[_current];
  int get pageCount => _pages.length;

  // --- tool state ----------------------------------------------------------
  InkTool tool = InkTool.pen;
  Color color = const Color(0xFF16213E); // ink navy/black
  double width = 2;

  static const List<Color> palette = [
    Color(0xFF16213E), // near-black ink
    Color(0xFF1D4ED8), // blue
    Color(0xFFE11D2E), // brand red
    Color(0xFF3FB27F), // green
    Color(0xFFE8B84B), // gold
  ];
  static const List<double> widths = [1, 2, 4, 8];

  void setTool(InkTool t) {
    tool = t;
    if (t != InkTool.lasso && t != InkTool.pointer) clearSelection();
    notifyListeners();
  }

  void setColor(Color c) {
    color = c;
    notifyListeners();
  }

  void setWidth(double w) {
    width = w;
    notifyListeners();
  }

  // --- selection (lasso) ---------------------------------------------------
  final Set<String> _selected = {};
  Set<String> get selected => _selected;
  bool get hasSelection => _selected.isNotEmpty;
  List<Stroke> get selectedStrokes =>
      page.strokes.where((s) => _selected.contains(s.id)).toList();

  Rect? get selectionBounds {
    final sel = selectedStrokes;
    if (sel.isEmpty) return null;
    var r = sel.first.bounds;
    for (final s in sel.skip(1)) {
      r = r.expandToInclude(s.bounds);
    }
    return r;
  }

  void clearSelection() {
    if (_selected.isEmpty && _recognition == null) return;
    _selected.clear();
    _recognition = null;
    notifyListeners();
  }

  // --- recognition / AI (separate layer) -----------------------------------
  RecognitionResult? _recognition;
  RecognitionResult? get recognition => _recognition;
  bool recognitionComplete = true;

  String? _aiExplanation;
  String? get aiExplanation => _aiExplanation;

  // --- audio ---------------------------------------------------------------
  bool recording = true;
  String audioTime = '18:44';

  // --- undo / redo ---------------------------------------------------------
  final List<List<Stroke>> _undo = [];
  final List<List<Stroke>> _redo = [];
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  // -------------------------------------------------------------------------
  // Drawing
  // -------------------------------------------------------------------------
  void beginEdit() => _pushUndo();

  void addStroke(Stroke stroke) {
    page.strokes.add(stroke);
    notifyListeners();
  }

  /// Erase strokes whose ink passes near [p] (stroke-level erase).
  void eraseAt(Offset p, {double radius = 12}) {
    var removed = false;
    page.strokes.removeWhere((s) {
      final hit = s.points.any((pt) => (pt - p).distance <= radius + s.width);
      if (hit) removed = true;
      return hit;
    });
    if (removed) notifyListeners();
  }

  /// Select strokes inside the lasso polygon [poly]. If the polygon is
  /// degenerate (a straight drag) or encloses nothing, fall back to a
  /// rectangular marquee over the path's bounding box.
  void applyLasso(List<Offset> poly) {
    _selected.clear();
    if (poly.isEmpty) {
      notifyListeners();
      return;
    }
    if (poly.length >= 3) {
      for (final s in page.strokes) {
        if (s.points.any((pt) => _inside(poly, pt)) ||
            _inside(poly, s.bounds.center)) {
          _selected.add(s.id);
        }
      }
    }
    if (_selected.isEmpty) {
      // Marquee fallback: bounding box of the whole gesture.
      var r = Rect.fromPoints(poly.first, poly.last);
      for (final p in poly) {
        r = r.expandToInclude(Rect.fromPoints(p, p));
      }
      for (final s in page.strokes) {
        if (s.bounds.overlaps(r)) _selected.add(s.id);
      }
    }
    if (_selected.isNotEmpty) {
      recognitionComplete = false;
      notifyListeners();
      // Simulate async recognition after a pause (spec §7).
      Future.delayed(const Duration(milliseconds: 500), () {
        _recognition = _recognize(selectedStrokes);
        _aiExplanation = null;
        recognitionComplete = true;
        notifyListeners();
      });
    } else {
      _recognition = null;
    }
    notifyListeners();
  }

  void moveSelection(Offset delta) {
    if (_selected.isEmpty) return;
    for (var i = 0; i < page.strokes.length; i++) {
      if (_selected.contains(page.strokes[i].id)) {
        page.strokes[i] = page.strokes[i].translated(delta);
      }
    }
    notifyListeners();
  }

  void deleteSelection() {
    if (_selected.isEmpty) return;
    _pushUndo();
    page.strokes.removeWhere((s) => _selected.contains(s.id));
    _selected.clear();
    _recognition = null;
    notifyListeners();
  }

  void duplicateSelection() {
    if (_selected.isEmpty) return;
    _pushUndo();
    final copies = selectedStrokes
        .map((s) => s.translated(const Offset(24, 24)))
        .map((s) => Stroke(
              id: _newId('k'),
              tool: s.tool,
              points: s.points,
              pressures: s.pressures,
              color: s.color,
              width: s.width,
              pageId: page.id,
              text: s.text,
              audioTimestamp: s.audioTimestamp,
            ))
        .toList();
    page.strokes.addAll(copies);
    notifyListeners();
  }

  void recolorSelection(Color c) {
    if (_selected.isEmpty) return;
    _pushUndo();
    for (var i = 0; i < page.strokes.length; i++) {
      if (_selected.contains(page.strokes[i].id)) {
        page.strokes[i] = page.strokes[i].copyWith(color: c);
      }
    }
    notifyListeners();
  }

  /// The recognized text for the current selection (spec §8 Convert to Text).
  /// The original ink is left untouched.
  String convertSelectionToText() => _recognition?.text ?? 'Recognized text';

  /// Ask AI to expand/explain the current selection. Produces a separate
  /// explanation; never edits ink (spec §8).
  void requestAiExplain() {
    final r = _recognition;
    _aiExplanation = r != null
        ? '${r.text} uses the proton gradient to convert ADP and phosphate '
            'into ATP.'
        : 'The electron transport chain creates a proton gradient that drives '
            'ATP synthase to produce ATP.';
    notifyListeners();
  }

  void dismissAi() {
    _aiExplanation = null;
    notifyListeners();
  }

  void confirmRecognition() {
    // High-confidence text enters the searchable semantic layer.
    recognitionComplete = true;
    notifyListeners();
  }

  // --- text tool -----------------------------------------------------------
  void addText(Offset at, String text) {
    if (text.trim().isEmpty) return;
    _pushUndo();
    page.strokes.add(Stroke(
      id: _newId('k'),
      tool: InkTool.text,
      points: [at],
      pressures: const [1],
      color: color,
      width: width,
      pageId: page.id,
      text: text,
      audioTimestamp: recording ? audioTime : null,
    ));
    notifyListeners();
  }

  // --- pages ---------------------------------------------------------------
  void setPage(int i) {
    if (i < 0 || i >= _pages.length || i == _current) return;
    _current = i;
    clearSelection();
    notifyListeners();
  }

  void addPage() {
    _pages.add(InkPage(
      id: _newId('p'),
      title: 'Page ${_pages.length + 1}',
    ));
    _current = _pages.length - 1;
    notifyListeners();
  }

  void setBackground(PaperBackground bg) {
    page.background = bg;
    notifyListeners();
  }

  // --- undo / redo ---------------------------------------------------------
  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(List.of(page.strokes));
    page.strokes
      ..clear()
      ..addAll(_undo.removeLast());
    clearSelection();
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(List.of(page.strokes));
    page.strokes
      ..clear()
      ..addAll(_redo.removeLast());
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // internals
  // -------------------------------------------------------------------------
  void _pushUndo() {
    _undo.add(List.of(page.strokes));
    if (_undo.length > 80) _undo.removeAt(0);
    _redo.clear();
  }

  static int _seq = 0;
  String _newId(String p) => '$p${_seq++}';

  String? nextAudioTime() => recording ? audioTime : null;

  RecognitionResult _recognize(List<Stroke> strokes) {
    // Mock: prefer any typed/text stroke; otherwise a canned label.
    final t = strokes.firstWhere(
      (s) => s.text != null && s.text!.trim().isNotEmpty,
      orElse: () => strokes.isNotEmpty
          ? strokes.first
          : Stroke(
              id: '',
              tool: InkTool.pen,
              points: const [],
              pressures: const [],
              color: color,
              width: width,
              pageId: page.id),
    );
    final text = t.text?.trim().isNotEmpty == true ? t.text!.trim() : 'ATP synthase';
    return RecognitionResult(text: text, confidence: 0.96);
  }

  static bool _inside(List<Offset> poly, Offset p) {
    if (poly.length < 3) return false;
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final a = poly[i], b = poly[j];
      if (((a.dy > p.dy) != (b.dy > p.dy)) &&
          (p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx)) {
        inside = !inside;
      }
    }
    return inside;
  }

  void _seed() {
    for (var i = 1; i <= 5; i++) {
      _pages.add(InkPage(id: _newId('p'), title: _pageTitles[i - 1]));
    }
    _current = 2; // "Page 3 of 5"
    // A light seed on page 3 so the recognition demo has content.
    final p = _pages[2];
    p.strokes.add(Stroke(
      id: _newId('k'),
      tool: InkTool.text,
      points: const [Offset(40, 40)],
      pressures: const [1],
      color: const Color(0xFF16213E),
      width: 2,
      pageId: p.id,
      text: 'Electron Transport Chain',
      audioTimestamp: '18:20',
    ));
    p.strokes.add(Stroke(
      id: _newId('k'),
      tool: InkTool.text,
      points: const [Offset(56, 96)],
      pressures: const [1],
      color: const Color(0xFF16213E),
      width: 2,
      pageId: p.id,
      text: '• inner mitochondrial membrane',
      audioTimestamp: '18:24',
    ));
    p.strokes.add(Stroke(
      id: _newId('k'),
      tool: InkTool.text,
      points: const [Offset(56, 132)],
      pressures: const [1],
      color: const Color(0xFF16213E),
      width: 2,
      pageId: p.id,
      text: '• H⁺ gradient   • O₂ final electron acceptor',
      audioTimestamp: '18:28',
    ));
  }

  static const _pageTitles = [
    'Glycolysis',
    'Pyruvate Oxidation',
    'Electron Transport Chain',
    'Citric Acid Cycle',
    'Summary',
  ];
}
