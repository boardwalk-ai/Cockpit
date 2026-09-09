import 'package:flutter/material.dart';

/// Panel 14 — Study Studio Recommendations domain (ON-P14).
///
/// Analyzes the *finalized* session and proposes topic clusters ready to become
/// Study Studio sessions. A recommendation + selection **gateway**, never an
/// auto-transfer: it only prepares a conversion draft; creation happens after
/// approval in Panel 15. See `docs/panel-14-study-recommendations.md`.

/// Readiness of a recommended topic (spec §8).
enum Readiness {
  ready('Ready for Study Studio', Icons.check_circle_rounded),
  needsReview('Needs Review', Icons.error_outline_rounded),
  limitedMaterial('Limited Material', Icons.remove_circle_outline_rounded),
  alreadyInStudio('Already in Study Studio', Icons.school_outlined);

  const Readiness(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// A recommended Study Studio activity (spec §10). Suggestion only — Panel 14
/// never generates the activity.
enum StudyActivity {
  teachMe('Teach Me', Icons.co_present_outlined),
  quizMe('Quiz Me', Icons.quiz_outlined),
  flashcards('Flashcards', Icons.style_outlined),
  lightningRecall('Lightning Recall', Icons.bolt_outlined),
  scenarios('Scenarios', Icons.account_tree_outlined),
  oralExam('Oral Exam', Icons.record_voice_over_outlined),
  mockExam('Mock Exam', Icons.assignment_outlined);

  const StudyActivity(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// A material-count line on a topic card ("6 concepts").
@immutable
class MaterialCount {
  const MaterialCount(this.label);
  final String label;
}

/// A traceable source behind a recommended topic (spec §14).
@immutable
class TopicSource {
  const TopicSource(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// One recommended topic cluster (spec §7).
class StudyTopic {
  StudyTopic({
    required this.id,
    required this.title,
    required this.readiness,
    required this.counts,
    required this.activities,
    required this.sources,
    this.reasonWhy,
    this.reviewReason,
    this.selected = false,
  });

  final String id;
  final String title;
  final Readiness readiness;
  final List<MaterialCount> counts;
  final List<StudyActivity> activities;
  final List<TopicSource> sources;

  /// Plain-language "Why this is ready" (spec §9).
  final String? reasonWhy;

  /// Why a topic needs review (spec §7 Role of Oxygen).
  final String? reviewReason;

  bool selected;
}

class RecommendationsController extends ChangeNotifier {
  RecommendationsController({required this.finalNotesId});

  final String finalNotesId;
  final int finalNotesRevision = 1;

  final String sourceTitle = 'Cellular Respiration Lecture';
  final String course = 'Biology 101';
  final String week = 'Week 4';

  bool drawerOpen = true;
  bool manualMode = false;

  void closeDrawer() {
    drawerOpen = false;
    notifyListeners();
  }

  void openDrawer() {
    drawerOpen = true;
    notifyListeners();
  }

  // --- Topic recommendations (spec §7) -----------------------------------
  late final List<StudyTopic> topics = [
    StudyTopic(
      id: 'glycolysis',
      title: 'Glycolysis',
      readiness: Readiness.ready,
      selected: true,
      counts: const [
        MaterialCount('6 concepts'),
        MaterialCount('3 definitions'),
        MaterialCount('2 slides'),
      ],
      activities: const [
        StudyActivity.teachMe,
        StudyActivity.quizMe,
        StudyActivity.flashcards,
        StudyActivity.lightningRecall,
      ],
      sources: const [
        TopicSource('Final Notes', Icons.task_alt_outlined),
        TopicSource('Transcript 18:25–18:44', Icons.record_voice_over_outlined),
        TopicSource('Slides 4–6', Icons.slideshow_outlined),
      ],
      reasonWhy:
          'Contains a complete explanation, six connected concepts, two source '
          'slides and one exam hint.',
    ),
    StudyTopic(
      id: 'etc',
      title: 'Electron Transport Chain',
      readiness: Readiness.ready,
      selected: true,
      counts: const [
        MaterialCount('8 concepts'),
        MaterialCount('1 diagram'),
        MaterialCount('2 questions'),
      ],
      activities: const [
        StudyActivity.teachMe,
        StudyActivity.quizMe,
        StudyActivity.scenarios,
        StudyActivity.flashcards,
      ],
      sources: const [
        TopicSource('Student Notes', Icons.edit_outlined),
        TopicSource('Magic Pencil', Icons.gesture_rounded),
        TopicSource('Slide 7', Icons.slideshow_outlined),
      ],
      reasonWhy:
          'Eight connected concepts, four definitions, an original diagram and '
          'two student questions with supporting transcript.',
    ),
    StudyTopic(
      id: 'oxygen',
      title: 'Role of Oxygen',
      readiness: Readiness.needsReview,
      counts: const [],
      activities: const [],
      sources: const [
        TopicSource('Final Notes', Icons.task_alt_outlined),
        TopicSource('Transcript 19:08', Icons.record_voice_over_outlined),
      ],
      reviewReason:
          'One unresolved question • Transcript confidence needs review',
    ),
  ];

  int get detectedCount => topics.length;
  int get readyCount =>
      topics.where((t) => t.readiness == Readiness.ready).length;
  int get needsReviewCount =>
      topics.where((t) => t.readiness == Readiness.needsReview).length;

  List<StudyTopic> get selectedTopics =>
      topics.where((t) => t.selected).toList();
  int get selectedCount => selectedTopics.length;
  bool get canContinue => selectedCount > 0 || manualBlockCount > 0;

  String get selectionSummary {
    final names = selectedTopics.map((t) => t.title).toList();
    if (names.isEmpty) return 'No topics selected';
    if (names.length == 1) return names.first;
    return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  }

  void toggleTopic(String id) {
    final t = topics.firstWhere((t) => t.id == id);
    // A "Needs Review" topic should not be selected without intent — allow it,
    // but only via its explicit checkbox (spec §7: not *auto*-selected).
    t.selected = !t.selected;
    notifyListeners();
  }

  void selectAllReady() {
    for (final t in topics) {
      if (t.readiness == Readiness.ready) t.selected = true;
    }
    notifyListeners();
  }

  void clearSelection() {
    for (final t in topics) {
      t.selected = false;
    }
    notifyListeners();
  }

  // --- Manual selection (spec §12) ---------------------------------------
  int manualBlockCount = 0;

  void enterManualMode() {
    manualMode = true;
    // A representative manual selection to mirror the spec example.
    manualBlockCount = 14;
    notifyListeners();
  }

  void exitManualMode() {
    manualMode = false;
    manualBlockCount = 0;
    notifyListeners();
  }

  static const manualBreakdown = [
    '2 transcript excerpts',
    '1 Magic Pencil diagram',
    '3 linked slides',
  ];
}
