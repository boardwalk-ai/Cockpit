import 'package:flutter/material.dart';

import 'notes_controller.dart';
import 'notes_models.dart' show SourceRef;

/// Where research is allowed to search (spec §6). Course materials go first.
enum ResearchScope { courseFirst, external, both }

/// How deep a research pass goes (spec §8).
enum ResearchDepth { quick, standard, deep }

/// The kind of an evidence source (spec §13) — determines its label + trust.
enum SourceKind {
  lectureTranscript,
  courseSlide,
  courseHandout,
  textbook,
  academicPaper,
  officialSource,
  universitySource,
  educationalWebsite,
  generalWeb,
  studentNote,
}

extension SourceKindMeta on SourceKind {
  String get label {
    switch (this) {
      case SourceKind.lectureTranscript:
        return 'Lecture Transcript';
      case SourceKind.courseSlide:
        return 'Course Slide';
      case SourceKind.courseHandout:
        return 'Course Handout';
      case SourceKind.textbook:
        return 'Textbook';
      case SourceKind.academicPaper:
        return 'Academic Paper';
      case SourceKind.officialSource:
        return 'Official Source';
      case SourceKind.universitySource:
        return 'University Source';
      case SourceKind.educationalWebsite:
        return 'Educational Website';
      case SourceKind.generalWeb:
        return 'General Web Source';
      case SourceKind.studentNote:
        return 'Student Note';
    }
  }

  bool get isExternal {
    switch (this) {
      case SourceKind.textbook:
      case SourceKind.academicPaper:
      case SourceKind.officialSource:
      case SourceKind.universitySource:
      case SourceKind.educationalWebsite:
      case SourceKind.generalWeb:
        return true;
      default:
        return false;
    }
  }

  /// A short trust badge shown on the card.
  String get qualityBadge {
    switch (this) {
      case SourceKind.lectureTranscript:
      case SourceKind.courseSlide:
      case SourceKind.courseHandout:
        return 'Course Source';
      case SourceKind.textbook:
        return 'Trusted Textbook';
      case SourceKind.academicPaper:
        return 'Academic';
      case SourceKind.officialSource:
        return 'Official';
      case SourceKind.universitySource:
        return 'University';
      case SourceKind.educationalWebsite:
        return 'Educational';
      case SourceKind.generalWeb:
        return 'Web';
      case SourceKind.studentNote:
        return 'Your Note';
    }
  }

  IconData get icon {
    switch (this) {
      case SourceKind.lectureTranscript:
        return Icons.record_voice_over_rounded;
      case SourceKind.courseSlide:
        return Icons.slideshow_rounded;
      case SourceKind.courseHandout:
        return Icons.description_outlined;
      case SourceKind.textbook:
        return Icons.menu_book_rounded;
      case SourceKind.academicPaper:
        return Icons.article_outlined;
      case SourceKind.officialSource:
        return Icons.verified_rounded;
      case SourceKind.universitySource:
        return Icons.school_rounded;
      case SourceKind.educationalWebsite:
        return Icons.public_rounded;
      case SourceKind.generalWeb:
        return Icons.language_rounded;
      case SourceKind.studentNote:
        return Icons.edit_note_rounded;
    }
  }
}

/// An evidence card (spec §12).
@immutable
class ResearchSource {
  const ResearchSource({
    required this.kind,
    required this.title,
    required this.excerpt,
    required this.locator,
    required this.openLabel,
    this.ref,
  });
  final SourceKind kind;
  final String title;
  final String excerpt;
  final String locator; // "19:08", "Slide 7", "Cellular Respiration"
  final String openLabel; // "Open Transcript" / "Open Slide" / "Open Source"
  final SourceRef? ref;
}

/// A completed research result (spec §10).
@immutable
class ResearchResult {
  const ResearchResult({
    required this.explanation,
    required this.evidence,
    this.sourcesAgree = true,
    this.conflict,
    this.lowEvidence = false,
  });
  final String explanation;
  final List<ResearchSource> evidence;
  final bool sourcesAgree;
  final String? conflict;
  final bool lowEvidence;

  int get agreeCount => evidence.length;
}

/// Panel 10 — Research & Explanations. Course-materials-first evidence gathering
/// with provenance and student approval. Never inserts without approval; the
/// source excerpt stays visually separate from the AI explanation (spec §26).
class ResearchController extends ChangeNotifier {
  ResearchController() {
    _seedContext();
    _result = _generate(question); // opens with the question already researched
  }

  final List<String> _contexts = [];
  List<String> get contexts => List.unmodifiable(_contexts);

  ResearchScope scope = ResearchScope.courseFirst;
  ResearchDepth depth = ResearchDepth.standard;
  String question = 'Why is oxygen required indirectly?';
  bool searching = false;
  ResearchResult? _result;
  ResearchResult? get result => _result;

  final List<String> _history = [];
  List<String> get history => List.unmodifiable(_history);

  void setScope(ResearchScope s) {
    scope = s;
    notifyListeners();
  }

  void removeContext(int i) {
    if (i < 0 || i >= _contexts.length) return;
    _contexts.removeAt(i);
    notifyListeners();
  }

  void setQuestion(String q) {
    question = q;
    notifyListeners();
  }

  void run([String? q]) {
    final query = (q ?? question).trim();
    if (query.isEmpty) return;
    question = query;
    searching = true;
    _result = null;
    notifyListeners();
    Future.delayed(const Duration(milliseconds: 600), () {
      _result = _generate(query);
      searching = false;
      _history.insert(0, query);
      notifyListeners();
    });
  }

  void dismiss() {
    _result = null;
    notifyListeners();
  }

  // --- approvals (through NotesController) ---------------------------------
  void addAsExplanation(NotesController notes) {
    final r = _result;
    if (r == null) return;
    notes.insertAiBlock(r.explanation,
        source: r.evidence.isNotEmpty ? r.evidence.first.ref : null);
    _result = null;
    notifyListeners();
  }

  void insertBelow(NotesController notes) => addAsExplanation(notes);

  // -------------------------------------------------------------------------
  void _seedContext() {
    _contexts.addAll([
      'Student Question',
      'Transcript · 19:02–19:08',
      'Week 4 Slides · Slide 7',
    ]);
  }

  ResearchResult _generate(String q) {
    // Course sources are always searched first (spec §7); external support is
    // added unless the student narrowed the scope to external-only.
    final evidence = <ResearchSource>[
      if (scope != ResearchScope.external) ...const [
        ResearchSource(
          kind: SourceKind.lectureTranscript,
          title: 'Professor explanation',
          excerpt: 'Oxygen accepts electrons at the end of the transport chain.',
          locator: '19:08',
          openLabel: 'Open Transcript',
          ref: SourceRef(material: 'Transcript', location: '19:08'),
        ),
        ResearchSource(
          kind: SourceKind.courseSlide,
          title: 'Week 4 Slides',
          excerpt: 'O₂ is the terminal electron acceptor.',
          locator: 'Slide 7',
          openLabel: 'Open Slide',
          ref: SourceRef(material: 'Week 4 Slides', location: 'Slide 7'),
        ),
      ],
      const ResearchSource(
        kind: SourceKind.textbook,
        title: 'OpenStax Biology 2e',
        excerpt: 'Oxygen is the final electron acceptor in aerobic respiration.',
        locator: 'Cellular Respiration',
        openLabel: 'Open Source',
      ),
    ];
    return ResearchResult(
      explanation:
          'Oxygen is required because it acts as the final electron acceptor in '
          'the electron transport chain. Without oxygen, electron flow stops, '
          'the proton gradient collapses, and aerobic ATP production cannot '
          'continue.',
      evidence: evidence,
      sourcesAgree: true,
    );
  }
}
