import 'package:flutter/material.dart';

import 'recommendations_controller.dart' show StudyActivity;

/// Panel 15 — Study Studio Conversion Preview domain (ON-P15).
///
/// A transparent, editable conversion checkpoint. Nothing is created or updated
/// until the student approves; the conversion never mutates the source note and
/// preserves any existing Study Studio mastery/history. In-memory. See
/// `docs/panel-15-conversion-preview.md`.

enum DestinationMode { createNew, updateExisting }

/// Existing-studio update mode (spec §16).
enum UpdateStrategy {
  addNew('Add New Material',
      'Adds the selected content without changing existing topics.'),
  updateMatching('Update Matching Topics',
      'Updates matching topics and adds newly detected ones.'),
  keepExisting('Keep Existing Content',
      'Only adds topic clusters that do not already exist.');

  const UpdateStrategy(this.label, this.detail);
  final String label;
  final String detail;
}

/// Generation difficulty (spec §11).
enum LearningLevel { foundation, balanced, challenging }

/// Topic coverage indicator (spec §13).
enum Coverage {
  strong('Strong coverage'),
  partial('Partial coverage'),
  needsReview('Needs review');

  const Coverage(this.label);
  final String label;
}

/// A configurable proposed activity (spec §10–11).
class PlannedActivity {
  PlannedActivity({
    required this.type,
    required this.count,
    required this.unit,
    required this.scope,
    this.enabled = true,
    this.available = true,
    this.unavailableReason,
  });

  final StudyActivity type;
  int count;
  final String unit; // "lessons", "questions", "cards"…
  String scope; // "Both topics" or a topic name
  bool enabled;
  final bool available;
  final String? unavailableReason;

  String get outputLabel => available ? '$count $unit' : (unavailableReason ?? '');
}

/// A detected topic + its subtopics and coverage (spec §8).
class ConversionTopic {
  ConversionTopic({
    required this.title,
    required this.subtopics,
    required this.coverage,
  });
  final String title;
  final List<String> subtopics;
  final Coverage coverage;
}

/// A material stat tile (spec §6).
class MaterialStat {
  const MaterialStat(this.value, this.label);
  final String value;
  final String label;
}

/// A summary metric (spec §18).
class SummaryMetric {
  const SummaryMetric(this.value, this.label);
  final String value;
  final String label;
}

class ConversionController extends ChangeNotifier {
  ConversionController({required this.sourceFinalNotesId});

  final String sourceFinalNotesId;
  final int sourceRevision = 1;

  final String sourceTitle = 'Cellular Respiration Lecture';
  final String course = 'Biology 101';
  final String week = 'Week 4';

  bool draftSaved = false;
  int step = 1; // 0 material · 1 activities · 2 destination

  // --- Selected material (spec §6) ---------------------------------------
  final List<MaterialStat> stats = const [
    MaterialStat('2', 'Topics'),
    MaterialStat('19', 'Note Blocks'),
    MaterialStat('2', 'Transcript Excerpts'),
    MaterialStat('1', 'Magic Pencil Diagram'),
    MaterialStat('3', 'Linked Slides'),
  ];

  final List<({String title, String meta})> selectedTopics = const [
    (title: '1. Glycolysis', meta: '6 concepts · 3 definitions'),
    (title: '2. Electron Transport Chain', meta: '8 concepts · 1 diagram'),
  ];

  final List<String> coverageTags = const [
    'Final Notes',
    'Transcript 18:25–19:16',
    'Slides 4–8',
    'Magic Pencil',
  ];

  final List<({IconData icon, String label, String detail})> sourceRows = const [
    (
      icon: Icons.record_voice_over_outlined,
      label: 'Transcript',
      detail: '18:32'
    ),
    (icon: Icons.slideshow_outlined, label: 'Week 4 Slides', detail: 'Slide 7'),
    (icon: Icons.gesture_rounded, label: 'Magic Pencil', detail: 'Original Ink'),
  ];

  // --- Proposed activities (spec §10–11) ---------------------------------
  final List<PlannedActivity> activities = [
    PlannedActivity(
        type: StudyActivity.teachMe, count: 2, unit: 'lessons', scope: 'Both topics'),
    PlannedActivity(
        type: StudyActivity.quizMe, count: 15, unit: 'questions', scope: 'Both topics'),
    PlannedActivity(
        type: StudyActivity.flashcards, count: 24, unit: 'cards', scope: 'Both topics'),
    PlannedActivity(
        type: StudyActivity.lightningRecall,
        count: 12,
        unit: 'prompts',
        scope: 'Both topics'),
    PlannedActivity(
        type: StudyActivity.scenarios,
        count: 4,
        unit: 'applications',
        scope: 'Electron Transport Chain'),
    PlannedActivity(
        type: StudyActivity.mockExam,
        count: 0,
        unit: '',
        scope: 'Both topics',
        enabled: false,
        available: false,
        unavailableReason: 'Not enough material'),
  ];

  LearningLevel level = LearningLevel.balanced;
  void setLevel(LearningLevel l) {
    level = l;
    notifyListeners();
  }

  void toggleActivity(StudyActivity t) {
    final a = activities.firstWhere((a) => a.type == t);
    if (!a.available) return;
    a.enabled = !a.enabled;
    notifyListeners();
  }

  void bumpActivity(StudyActivity t, int delta) {
    final a = activities.firstWhere((a) => a.type == t);
    if (!a.available) return;
    a.count = (a.count + delta).clamp(0, 200);
    notifyListeners();
  }

  // --- Detected topics (spec §8) -----------------------------------------
  final List<ConversionTopic> topics = [
    ConversionTopic(
      title: '1. Glycolysis',
      subtopics: const ['Location', 'Inputs', 'Outputs', 'ATP', 'NADH'],
      coverage: Coverage.strong,
    ),
    ConversionTopic(
      title: '2. Electron Transport Chain',
      subtopics: const ['Proton Gradient', 'ATP Synthase', 'Role of Oxygen'],
      coverage: Coverage.strong,
    ),
  ];

  // --- Destination (spec §15–16) -----------------------------------------
  DestinationMode destination = DestinationMode.updateExisting;
  UpdateStrategy strategy = UpdateStrategy.updateMatching;

  final String existingStudioName = 'Biology 101 — Cellular Respiration';
  final String existingMastery = '68%';
  final String existingLastStudied = '3 days ago';
  final int existingTopicCount = 2;

  void setDestination(DestinationMode m) {
    destination = m;
    notifyListeners();
  }

  void setStrategy(UpdateStrategy s) {
    strategy = s;
    notifyListeners();
  }

  // --- Summary (spec §18) ------------------------------------------------
  List<PlannedActivity> get enabledActivities =>
      activities.where((a) => a.enabled).toList();
  int get activityTypeCount => enabledActivities.length;
  int get learningItemsPlanned =>
      enabledActivities.fold(0, (sum, a) => sum + a.count);
  int get sourceConnections => 7;
  bool get canGenerate => activityTypeCount > 0;

  String get primaryActionLabel => destination == DestinationMode.createNew
      ? 'Create & Generate'
      : 'Update & Generate';

  List<SummaryMetric> get summary => [
        SummaryMetric('${topics.length}', 'topics'),
        SummaryMetric('$activityTypeCount', 'activity types'),
        SummaryMetric('$learningItemsPlanned', 'learning items planned'),
        SummaryMetric('$sourceConnections', 'source connections'),
      ];

  bool generated = false;
  void saveDraft() {
    draftSaved = true;
    notifyListeners();
  }

  void generate() {
    generated = true;
    notifyListeners();
  }
}
