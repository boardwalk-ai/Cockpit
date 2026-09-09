import 'package:flutter/material.dart';

/// Panel 13 — Session Review & Finalize domain (ON-P13).
///
/// In-memory, non-destructive review model. Finalization produces an *approved*
/// Final Notes document without deleting or replacing any underlying layer —
/// see `docs/panel-13-review-finalize.md`. Every original source stays
/// accessible; AI never approves its own additions or finalizes the session.

/// The six review layers that live inside this one panel.
enum ReviewLayer {
  originalSources('Original Sources', Icons.folder_outlined),
  rawTranscript('Raw Transcript', Icons.record_voice_over_outlined),
  studentNotes('Student Notes', Icons.edit_outlined),
  aiAssistance('AI Assistance', Icons.auto_awesome_outlined),
  smartNotes('Smart Notes', Icons.auto_stories_outlined),
  finalNotes('Final Notes', Icons.task_alt_outlined);

  const ReviewLayer(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Left-nav status indicator for a layer (spec §6.B).
enum LayerStatus {
  reviewed, // green check
  open, // blue dot — currently open
  pending, // yellow number
  problem, // red warning
  notProcessed, // grey
}

/// Where a block came from — drives the provenance chip (spec §7).
enum BlockOrigin {
  studentTyped('Student Typed', Icons.edit_outlined),
  magicPencil('Magic Pencil • Original Ink', Icons.gesture_rounded),
  transcript('Transcript', Icons.record_voice_over_outlined),
  slide('Week 4 Slides', Icons.slideshow_outlined),
  aiOrganized('AI Organized', Icons.auto_awesome_outlined),
  aiExplanation('AI Explanation', Icons.auto_awesome_outlined),
  externalResearch('External Research', Icons.public_outlined);

  const BlockOrigin(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Comparison change kind → the §8 colour code (Smart vs Final).
enum ChangeKind {
  added, // green
  moved, // blue
  edited, // yellow
  excluded, // red
  aiGenerated, // purple
}

/// AI decision state (spec §5 layer 4).
enum AiDecision { accepted, editedAccepted, pending, rejected }

/// A single reviewable block inside a layer.
@immutable
class ReviewBlock {
  const ReviewBlock({
    required this.id,
    required this.text,
    required this.origin,
    this.kind = ReviewBlockKind.body,
    this.provenanceDetail,
    this.audioTimestamp,
    this.change,
    this.aiDecision,
    this.includedInFinal = true,
    this.diagram = false,
  });

  final String id;
  final String text;
  final BlockOrigin origin;
  final ReviewBlockKind kind;

  /// e.g. "18:32", "Slide 7", "19:02" appended to the origin label.
  final String? provenanceDetail;
  final String? audioTimestamp;

  /// Set on Smart/Final blocks to drive change highlighting.
  final ChangeKind? change;
  final AiDecision? aiDecision;
  final bool includedInFinal;
  final bool diagram;

  String get provenanceLabel => provenanceDetail == null
      ? origin.label
      : '${origin.label} • $provenanceDetail';

  ReviewBlock copyWith({
    ChangeKind? change,
    AiDecision? aiDecision,
    bool? includedInFinal,
  }) =>
      ReviewBlock(
        id: id,
        text: text,
        origin: origin,
        kind: kind,
        provenanceDetail: provenanceDetail,
        audioTimestamp: audioTimestamp,
        change: change ?? this.change,
        aiDecision: aiDecision ?? this.aiDecision,
        includedInFinal: includedInFinal ?? this.includedInFinal,
        diagram: diagram,
      );
}

enum ReviewBlockKind { h1, section, heading, body, bullet, question, note }

/// A right-side checklist item (spec §6.E).
@immutable
class ChecklistItem {
  const ChecklistItem(this.label, this.state, {this.jumpToLayer});
  final String label;
  final ChecklistState state;
  final ReviewLayer? jumpToLayer;
}

enum ChecklistState { done, warning, info }

class ReviewController extends ChangeNotifier {
  ReviewController({required this.sessionId});

  final String sessionId;

  // --- Session metadata (spec §6.A) --------------------------------------
  final String sessionTitle = 'Cellular Respiration Lecture';
  final String course = 'Biology 101';
  final String week = 'Week 4';
  final String duration = '42:16';
  final String audioSource = "Hein's iPhone";
  final int studentBlockCount = 34;
  final int transcriptBlockCount = 126;

  // Deck destination (spec §12).
  List<String> deckPath = const ['Biology 101', 'Lectures', 'Week 4'];
  String get deckPathLabel => deckPath.join(' / ');

  // --- Audio timeline (spec §6.D) ----------------------------------------
  bool playing = false;
  Duration position = const Duration(minutes: 18, seconds: 32);
  final Duration total = const Duration(minutes: 42, seconds: 16);
  double speed = 1.0;

  String fmt(Duration d) {
    final m = d.inMinutes.toString();
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void togglePlay() {
    playing = !playing;
    notifyListeners();
  }

  void seekBy(int seconds) {
    var next = position.inSeconds + seconds;
    next = next.clamp(0, total.inSeconds);
    position = Duration(seconds: next);
    notifyListeners();
  }

  void cycleSpeed() {
    const options = [1.0, 1.25, 1.5, 2.0, 0.75];
    speed = options[(options.indexOf(speed) + 1) % options.length];
    notifyListeners();
  }

  /// Jump the timeline to a block's attached audio (spec §6.D).
  void jumpToBlockAudio(ReviewBlock b) {
    final ts = b.audioTimestamp ?? b.provenanceDetail;
    if (ts == null || !ts.contains(':')) return;
    final parts = ts.split(':');
    final m = int.tryParse(parts[0]) ?? 0;
    final s = int.tryParse(parts[1]) ?? 0;
    position = Duration(minutes: m, seconds: s);
    notifyListeners();
  }

  // --- Comparison workspace (spec §6.C) ----------------------------------
  ReviewLayer leftLayer = ReviewLayer.studentNotes;
  ReviewLayer rightLayer = ReviewLayer.smartNotes;
  bool showChanges = true;
  String? selectedBlockId;

  void setLeftLayer(ReviewLayer l) {
    leftLayer = l;
    notifyListeners();
  }

  void setRightLayer(ReviewLayer l) {
    rightLayer = l;
    notifyListeners();
  }

  void toggleShowChanges() {
    showChanges = !showChanges;
    notifyListeners();
  }

  void selectBlock(String? id) {
    selectedBlockId = selectedBlockId == id ? null : id;
    notifyListeners();
  }

  /// A related block on the other side is highlighted when its text matches.
  bool isRelated(ReviewBlock b) {
    if (selectedBlockId == null) return false;
    final sel = _blockById(selectedBlockId!);
    if (sel == null || sel.id == b.id) return false;
    return _key(sel.text) == _key(b.text);
  }

  String _key(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '').trim();

  ReviewBlock? _blockById(String id) {
    for (final layer in _layerBlocks.values) {
      for (final b in layer) {
        if (b.id == id) return b;
      }
    }
    return null;
  }

  // --- Layer navigation status (spec §6.B) -------------------------------
  ReviewLayer openLayer = ReviewLayer.smartNotes;

  final Map<ReviewLayer, LayerStatus> _status = {
    ReviewLayer.originalSources: LayerStatus.reviewed,
    ReviewLayer.rawTranscript: LayerStatus.pending,
    ReviewLayer.studentNotes: LayerStatus.reviewed,
    ReviewLayer.aiAssistance: LayerStatus.pending,
    ReviewLayer.smartNotes: LayerStatus.open,
    ReviewLayer.finalNotes: LayerStatus.notProcessed,
  };

  final Map<ReviewLayer, int> _pendingCount = {
    ReviewLayer.rawTranscript: 2,
    ReviewLayer.aiAssistance: 3,
  };

  LayerStatus statusOf(ReviewLayer l) => _status[l] ?? LayerStatus.notProcessed;
  int pendingOf(ReviewLayer l) => _pendingCount[l] ?? 0;

  /// Opening a layer both selects it in nav and loads it into the right column.
  void openLayerInNav(ReviewLayer l) {
    // Move the "currently open" blue dot.
    for (final entry in _status.entries.toList()) {
      if (entry.value == LayerStatus.open) {
        _status[entry.key] = _pendingCount.containsKey(entry.key)
            ? LayerStatus.pending
            : LayerStatus.reviewed;
      }
    }
    _status[l] = LayerStatus.open;
    openLayer = l;
    rightLayer = l;
    notifyListeners();
  }

  // --- Checklist (spec §6.E) ---------------------------------------------
  List<ChecklistItem> get checklist => const [
        ChecklistItem('All devices synchronized', ChecklistState.done),
        ChecklistItem('Audio upload complete', ChecklistState.done),
        ChecklistItem('Original ink preserved', ChecklistState.done),
        ChecklistItem('Sources linked', ChecklistState.done),
        ChecklistItem('Deck destination selected', ChecklistState.done),
        ChecklistItem('2 transcript uncertainties', ChecklistState.warning,
            jumpToLayer: ReviewLayer.rawTranscript),
        ChecklistItem('3 AI decisions pending', ChecklistState.warning,
            jumpToLayer: ReviewLayer.aiAssistance),
        ChecklistItem('1 student question', ChecklistState.info,
            jumpToLayer: ReviewLayer.studentNotes),
      ];

  int get checklistDone =>
      checklist.where((c) => c.state == ChecklistState.done).length;
  int get checklistTotal => checklist.length;

  /// Checklist items still needing attention (spec §6.A "N items remaining").
  int get openIssues => checklistTotal - checklistDone;

  bool get readyToFinalize => openIssues == 0;
  String get reviewStatus => readyToFinalize
      ? 'Ready to finalize'
      : 'Review Required — $openIssues items';

  // --- Finalization summary (spec §13) -----------------------------------
  int get aiApproved => _layerBlocks[ReviewLayer.smartNotes]!
      .where((b) => b.aiDecision == AiDecision.accepted)
      .length;
  int get aiRejected => 3;
  int get sourcesLinked => 4;

  bool draftSaved = false;
  bool finalized = false;

  void saveDraft() {
    draftSaved = true;
    notifyListeners();
  }

  void finalize() {
    finalized = true;
    _status[ReviewLayer.finalNotes] = LayerStatus.reviewed;
    notifyListeners();
  }

  // --- Block-level decisions (spec §7, §10) ------------------------------
  void acceptBlock(String id) => _mutate(id, (b) {
        if (b.origin == BlockOrigin.aiOrganized ||
            b.origin == BlockOrigin.aiExplanation) {
          return b.copyWith(aiDecision: AiDecision.accepted);
        }
        return b.copyWith(includedInFinal: true);
      });

  void excludeBlock(String id) =>
      _mutate(id, (b) => b.copyWith(includedInFinal: false, change: ChangeKind.excluded));

  void _mutate(String id, ReviewBlock Function(ReviewBlock) f) {
    for (final layer in _layerBlocks.keys) {
      final list = _layerBlocks[layer]!;
      final i = list.indexWhere((b) => b.id == id);
      if (i != -1) {
        list[i] = f(list[i]);
        notifyListeners();
        return;
      }
    }
  }

  // --- Per-layer content --------------------------------------------------
  List<ReviewBlock> blocksFor(ReviewLayer l) => _layerBlocks[l] ?? const [];

  late final Map<ReviewLayer, List<ReviewBlock>> _layerBlocks = {
    ReviewLayer.originalSources: [
      const ReviewBlock(
          id: 'os1',
          text: 'Lecture Audio — 42:16',
          origin: BlockOrigin.transcript,
          kind: ReviewBlockKind.heading,
          provenanceDetail: '00:00'),
      const ReviewBlock(
          id: 'os2',
          text: 'Week 4 Slides — Cellular Respiration (24 slides)',
          origin: BlockOrigin.slide,
          provenanceDetail: 'Slide 7'),
      const ReviewBlock(
          id: 'os3',
          text: 'Magic Pencil — Electron transport chain diagram',
          origin: BlockOrigin.magicPencil,
          diagram: true),
    ],
    ReviewLayer.rawTranscript: [
      const ReviewBlock(
          id: 'rt1',
          text: 'So today we are looking at cellular respiration…',
          origin: BlockOrigin.transcript,
          provenanceDetail: '18:20'),
      const ReviewBlock(
          id: 'rt2',
          text: 'The net result is two ATP and two NADH.',
          origin: BlockOrigin.transcript,
          provenanceDetail: '18:32',
          audioTimestamp: '18:32'),
      const ReviewBlock(
          id: 'rt3',
          text: 'The proton [grading/gradient] powers ATP synthase.',
          origin: BlockOrigin.transcript,
          kind: ReviewBlockKind.note,
          provenanceDetail: '19:08',
          audioTimestamp: '19:08'),
    ],
    ReviewLayer.studentNotes: [
      const ReviewBlock(
          id: 'sn0',
          text: 'Cellular Respiration',
          origin: BlockOrigin.studentTyped,
          kind: ReviewBlockKind.h1),
      const ReviewBlock(
          id: 'sn1',
          text: '2. Electron Transport Chain',
          origin: BlockOrigin.studentTyped,
          kind: ReviewBlockKind.heading),
      const ReviewBlock(
          id: 'sn2',
          text: 'Oxygen is the final electron acceptor',
          origin: BlockOrigin.studentTyped,
          kind: ReviewBlockKind.bullet),
      const ReviewBlock(
          id: 'sn3',
          text: 'Why is oxygen required indirectly?',
          origin: BlockOrigin.studentTyped,
          kind: ReviewBlockKind.question,
          provenanceDetail: '19:02',
          audioTimestamp: '19:02'),
      const ReviewBlock(
          id: 'sn4',
          text: 'The net result is two ATP and two NADH.',
          origin: BlockOrigin.transcript,
          provenanceDetail: '18:32',
          audioTimestamp: '18:32'),
      const ReviewBlock(
          id: 'sn5',
          text: 'NADH → e⁻ → O₂ → H₂O',
          origin: BlockOrigin.magicPencil,
          kind: ReviewBlockKind.note,
          diagram: true),
    ],
    ReviewLayer.aiAssistance: [
      const ReviewBlock(
          id: 'ai1',
          text: 'ATP synthase uses the proton gradient to phosphorylate ADP.',
          origin: BlockOrigin.aiExplanation,
          kind: ReviewBlockKind.note,
          aiDecision: AiDecision.pending),
      const ReviewBlock(
          id: 'ai2',
          text: 'Suggested heading: Role of Oxygen',
          origin: BlockOrigin.aiOrganized,
          aiDecision: AiDecision.pending),
      const ReviewBlock(
          id: 'ai3',
          text:
              'Oxygen’s high electronegativity pulls electrons through the chain.',
          origin: BlockOrigin.externalResearch,
          kind: ReviewBlockKind.note,
          provenanceDetail: 'OpenStax Biology 2e',
          aiDecision: AiDecision.pending),
    ],
    ReviewLayer.smartNotes: [
      const ReviewBlock(
          id: 'smh',
          text: 'Cellular Respiration',
          origin: BlockOrigin.aiOrganized,
          kind: ReviewBlockKind.h1),
      const ReviewBlock(
          id: 'sm1',
          text: '1. Glycolysis',
          origin: BlockOrigin.aiOrganized,
          kind: ReviewBlockKind.section,
          change: ChangeKind.added),
      const ReviewBlock(
          id: 'sm2',
          text: 'Net result: two ATP and two NADH',
          origin: BlockOrigin.aiOrganized,
          kind: ReviewBlockKind.bullet,
          provenanceDetail: '18:32',
          audioTimestamp: '18:32',
          aiDecision: AiDecision.accepted),
      const ReviewBlock(
          id: 'sm3',
          text: '2. Electron Transport Chain',
          origin: BlockOrigin.aiOrganized,
          kind: ReviewBlockKind.section,
          change: ChangeKind.added),
      const ReviewBlock(
          id: 'sm4',
          text: 'Role of Oxygen',
          origin: BlockOrigin.aiOrganized,
          kind: ReviewBlockKind.heading),
      const ReviewBlock(
          id: 'sm5',
          text: 'Oxygen acts as the final electron acceptor.',
          origin: BlockOrigin.slide,
          kind: ReviewBlockKind.bullet,
          provenanceDetail: 'Slide 7'),
      const ReviewBlock(
          id: 'sm6',
          text: 'Why is oxygen required indirectly?',
          origin: BlockOrigin.studentTyped,
          kind: ReviewBlockKind.question,
          provenanceDetail: '19:02',
          audioTimestamp: '19:02',
          change: ChangeKind.moved),
      const ReviewBlock(
          id: 'sm7',
          text: 'ATP synthase uses the proton gradient.',
          origin: BlockOrigin.aiOrganized,
          kind: ReviewBlockKind.note,
          change: ChangeKind.aiGenerated,
          aiDecision: AiDecision.pending),
    ],
    ReviewLayer.finalNotes: [],
  };
}
