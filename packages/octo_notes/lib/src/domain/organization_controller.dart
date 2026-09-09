import 'package:flutter/material.dart';

/// Where Smart Organization looks (spec §5).
enum OrgScope { selectedBlocks, currentSection, entireNote }

extension OrgScopeMeta on OrgScope {
  String get label {
    switch (this) {
      case OrgScope.selectedBlocks:
        return 'Selected blocks';
      case OrgScope.currentSection:
        return 'Current section';
      case OrgScope.entireNote:
        return 'Entire Note';
    }
  }
}

/// Which internal view of the organizer is showing (spec §4B).
enum OrgView { suggestions, outline, categories }

enum OrgConfidence { high, medium, low }

extension OrgConfidenceMeta on OrgConfidence {
  String get label {
    switch (this) {
      case OrgConfidence.high:
        return 'High confidence';
      case OrgConfidence.medium:
        return 'Medium confidence';
      case OrgConfidence.low:
        return 'Placement uncertain — review recommended';
    }
  }
}

/// A single proposed change (spec §4B). Stored as an operation; only approved
/// operations mutate the organized view (spec §13).
class OrgSuggestion {
  OrgSuggestion({
    required this.id,
    required this.title,
    required this.reason,
    required this.confidence,
    required this.blockLabel,
    this.checked = true,
  });
  final String id;
  final String title;
  final String reason;
  final OrgConfidence confidence;
  final String blockLabel; // "Block 3"
  bool checked;
  bool applied = false;
  bool dismissed = false;
}

/// A node in the proposed outline tree (spec §4B Outline).
class OutlineNode {
  OutlineNode(this.title, {this.icon = Icons.article_outlined, this.children = const []});
  final String title;
  final IconData icon;
  final List<OutlineNode> children;
}

/// A detected content category (spec §4B Categories).
@immutable
class OrgCategory {
  const OrgCategory(this.label, this.count, this.icon);
  final String label;
  final int count;
  final IconData icon;
}

/// Panel 11 — Smart Organization. Detects topics/categories/structure and
/// proposes an organized version **without altering the original** (spec §3).
/// Preview-based: nothing changes until the student applies, and every pass is
/// one reversible transaction (spec §13).
class OrganizationController extends ChangeNotifier {
  OrganizationController() {
    _seed();
  }

  OrgScope scope = OrgScope.entireNote;
  bool autoOrganize = false;
  bool showingOrganized = true; // Original vs Organized Preview
  OrgView view = OrgView.suggestions;

  /// Total improvements detected (header count).
  int foundCount = 12;

  final List<OrgSuggestion> _suggestions = [];
  final List<OrgCategory> _categories = [];
  late final OutlineNode outline;

  bool _appliedOnce = false;
  bool get canUndo => _appliedOnce;

  List<OrgSuggestion> get suggestions =>
      _suggestions.where((s) => !s.dismissed && !s.applied).toList();
  List<OrgCategory> get categories => List.unmodifiable(_categories);

  int get selectedCount => suggestions.where((s) => s.checked).length;
  bool get canApply => selectedCount > 0;

  // Preview summary (spec §7).
  int get sectionsCreated => 2;
  int get blocksMoved => suggestions.where((s) => s.checked).length;
  int get categoriesAssigned =>
      _categories.fold(0, (sum, c) => sum + (c.count > 0 ? 1 : 0));

  // --- controls ------------------------------------------------------------
  void setScope(OrgScope s) {
    scope = s;
    notifyListeners();
  }

  void setAutoOrganize(bool v) {
    autoOrganize = v;
    notifyListeners();
  }

  void setShowingOrganized(bool v) {
    showingOrganized = v;
    notifyListeners();
  }

  void setView(OrgView v) {
    view = v;
    notifyListeners();
  }

  void toggle(String id) {
    final s = _suggestions.firstWhere((s) => s.id == id);
    s.checked = !s.checked;
    notifyListeners();
  }

  void dismiss(String id) {
    _suggestions.firstWhere((s) => s.id == id).dismissed = true;
    notifyListeners();
  }

  void dismissAll() {
    for (final s in _suggestions) {
      s.dismissed = true;
    }
    notifyListeners();
  }

  /// Apply checked proposals as one reversible transaction (spec §13).
  int applySelected() {
    final toApply = suggestions.where((s) => s.checked).toList();
    for (final s in toApply) {
      s.applied = true;
    }
    if (toApply.isNotEmpty) _appliedOnce = true;
    notifyListeners();
    return toApply.length;
  }

  int applyAll() {
    for (final s in suggestions) {
      s.checked = true;
    }
    return applySelected();
  }

  /// Undo the whole last organization pass (spec §5, §13).
  void undoLast() {
    for (final s in _suggestions) {
      s.applied = false;
    }
    _appliedOnce = false;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  void _seed() {
    _categories.addAll(const [
      OrgCategory('Topics', 3, Icons.topic_outlined),
      OrgCategory('Definitions', 4, Icons.menu_book_rounded),
      OrgCategory('Questions', 1, Icons.help_outline_rounded),
      OrgCategory('Exam Hints', 2, Icons.star_rounded),
    ]);

    outline = OutlineNode('Cellular Respiration', icon: Icons.article_rounded, children: [
      OutlineNode('Glycolysis', icon: Icons.topic_outlined),
      OutlineNode('Electron Transport Chain', icon: Icons.topic_outlined, children: [
        OutlineNode('Role of Oxygen', icon: Icons.subdirectory_arrow_right_rounded),
        OutlineNode('ATP Synthase', icon: Icons.settings_rounded),
      ]),
      OutlineNode('Student Questions', icon: Icons.help_outline_rounded),
    ]);

    _suggestions.addAll([
      OrgSuggestion(
        id: 's1',
        title: 'Move student question under Role of Oxygen',
        reason: 'Keeps the question with its related concept',
        confidence: OrgConfidence.high,
        blockLabel: 'Block 3',
      ),
      OrgSuggestion(
        id: 's2',
        title: 'Move ATP and NADH result under Glycolysis',
        reason: 'This result belongs to the glycolysis section',
        confidence: OrgConfidence.high,
        blockLabel: 'Block 4',
      ),
      OrgSuggestion(
        id: 's3',
        title: 'Create a heading for ATP Production',
        reason: 'Groups related ETC blocks under one section',
        confidence: OrgConfidence.medium,
        blockLabel: 'Block 6',
      ),
      OrgSuggestion(
        id: 's4',
        title: 'Convert this sentence into a definition',
        reason: 'Detected a term followed by its meaning',
        confidence: OrgConfidence.medium,
        blockLabel: 'Block 2',
      ),
      OrgSuggestion(
        id: 's5',
        title: 'Collect exam hints in one section',
        reason: 'Two professor exam hints found across the note',
        confidence: OrgConfidence.low,
        blockLabel: 'Block 8',
        checked: false,
      ),
    ]);
  }
}
