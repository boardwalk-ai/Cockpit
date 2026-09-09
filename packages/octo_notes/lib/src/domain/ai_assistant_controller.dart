import 'package:flutter/foundation.dart';

import 'notes_controller.dart';
import 'notes_models.dart' show SourceRef;

/// The kind of content a context chip points at (spec §3).
enum AiContextType { block, transcript, slide, ink, section, session, selection }

/// A removable context chip — what the AI is allowed to analyze (spec §4).
@immutable
class AiContext {
  const AiContext({required this.type, required this.label, this.source});
  final AiContextType type;
  final String label;
  final SourceRef? source;
}

/// One "missing" point from a What-Did-I-Miss response (spec §9). Each links to
/// its evidence and is individually selectable.
class MissingPoint {
  MissingPoint({
    required this.text,
    required this.sourceLabel,
    this.checked = false,
    this.source,
  });
  final String text;
  final String sourceLabel;
  final SourceRef? source;
  bool checked;
}

/// A generated AI response card (spec §10). Either a structured missing-points
/// list or a plain text body. Stays a preview until the student approves.
class AiResponse {
  AiResponse({
    required this.title,
    required this.contextSummary,
    this.body,
    this.missingPoints = const [],
    this.sources = const [],
    this.sourcesAgree = true,
    this.conflict,
  });
  final String title;
  final String contextSummary;
  final String? body;
  final List<MissingPoint> missingPoints;
  final List<SourceRef> sources;
  final bool sourcesAgree;
  final String? conflict;

  bool get isMissingPoints => missingPoints.isNotEmpty;
}

/// A session-scoped AI history entry (spec §18), grouped by context.
@immutable
class AiHistoryEntry {
  const AiHistoryEntry({
    required this.command,
    required this.contextLabel,
    required this.action,
  });
  final String command;
  final String contextLabel;
  final String action; // "inserted", "dismissed", "generated"…
}

/// Panel 9 — Magic Bar & AI Assistant store. Issues natural-language commands
/// against precise context and returns **source-grounded** suggestions the
/// student controls. Never mutates student blocks directly — approved actions
/// go through [NotesController] (spec §13, §27).
class AiAssistantController extends ChangeNotifier {
  AiAssistantController() {
    _seedContext();
  }

  final List<AiContext> _contexts = [];
  AiResponse? _response;
  bool generating = false;
  final List<AiHistoryEntry> _history = [];

  List<AiContext> get contexts => List.unmodifiable(_contexts);
  AiResponse? get response => _response;
  List<AiHistoryEntry> get history => List.unmodifiable(_history);

  // --- context -------------------------------------------------------------
  void removeContext(int i) {
    if (i < 0 || i >= _contexts.length) return;
    _contexts.removeAt(i);
    notifyListeners();
  }

  void addContext(AiContext c) {
    _contexts.add(c);
    notifyListeners();
  }

  void useWholeSection() {
    _contexts
      ..clear()
      ..add(const AiContext(
          type: AiContextType.section, label: 'Whole Section'));
    notifyListeners();
  }

  void useWholeSession() {
    _contexts
      ..clear()
      ..add(const AiContext(
          type: AiContextType.session, label: 'Whole Session'));
    notifyListeners();
  }

  String get contextSummary {
    final n = _contexts.length;
    return 'Based on $n course source${n == 1 ? '' : 's'}';
  }

  // --- run a command -------------------------------------------------------
  void run(String command) {
    final cmd = command.trim();
    if (cmd.isEmpty) return;
    generating = true;
    _response = null;
    notifyListeners();
    // Simulate a short async generation (spec §28: begins within a few seconds).
    Future.delayed(const Duration(milliseconds: 500), () {
      _response = _generate(cmd);
      generating = false;
      _history.insert(
        0,
        AiHistoryEntry(
          command: cmd,
          contextLabel: _contexts.isNotEmpty ? _contexts.first.label : 'Note',
          action: 'generated',
        ),
      );
      notifyListeners();
    });
  }

  void dismiss() {
    _response = null;
    notifyListeners();
  }

  void togglePoint(MissingPoint p) {
    p.checked = !p.checked;
    notifyListeners();
  }

  // --- approvals (go through NotesController) ------------------------------
  /// Insert the checked missing points as AI-origin blocks (spec §9, §13).
  int insertSelected(NotesController notes) {
    final r = _response;
    if (r == null) return 0;
    var count = 0;
    for (final p in r.missingPoints.where((p) => p.checked)) {
      notes.insertAiBlock(p.text, source: p.source);
      count++;
    }
    if (count > 0) {
      _history.insert(
          0,
          AiHistoryEntry(
              command: r.title, contextLabel: 'Note', action: 'inserted'));
      _response = null;
      notifyListeners();
    }
    return count;
  }

  /// Insert a text response beneath the note (spec §10).
  void insertBelow(NotesController notes) {
    final r = _response;
    if (r?.body == null) return;
    notes.insertAiBlock(r!.body!,
        source: r.sources.isNotEmpty ? r.sources.first : null);
    _response = null;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // internals
  // -------------------------------------------------------------------------
  void _seedContext() {
    _contexts.addAll(const [
      AiContext(type: AiContextType.block, label: 'Typewriter Block'),
      AiContext(type: AiContextType.transcript, label: 'Transcript · 18:20–18:44'),
      AiContext(
        type: AiContextType.slide,
        label: 'Week 4 Slides · Slide 7',
        source: SourceRef(material: 'Week 4 Slides', location: 'Slide 7'),
      ),
    ]);
  }

  AiResponse _generate(String cmd) {
    final c = cmd.toLowerCase();
    if (c.contains('miss')) {
      return AiResponse(
        title: 'Missing from your notes',
        contextSummary: contextSummary,
        sourcesAgree: true,
        missingPoints: [
          MissingPoint(
            text: 'Oxygen acts as the final electron acceptor.',
            sourceLabel: 'Transcript · 19:08',
            checked: true,
            source: const SourceRef(material: 'Transcript', location: '19:08'),
          ),
          MissingPoint(
            text: 'Water is produced at the end of the transport chain.',
            sourceLabel: 'Slide 7',
            checked: true,
            source:
                const SourceRef(material: 'Week 4 Slides', location: 'Slide 7'),
          ),
          MissingPoint(
            text: 'The professor marked this process as an exam topic.',
            sourceLabel: 'Transcript · 20:14',
            source: const SourceRef(material: 'Transcript', location: '20:14'),
          ),
        ],
      );
    }
    if (c.contains('conflict') || c.contains('atp')) {
      return AiResponse(
        title: cmd,
        contextSummary: contextSummary,
        body: 'The net gain is two ATP, not four.',
        sources: const [
          SourceRef(material: 'Week 4 Slides', location: 'Slide 7'),
          SourceRef(material: 'Transcript', location: '18:32'),
        ],
        sourcesAgree: false,
        conflict:
            'Your note says "4 ATP", while the professor and Slide 7 state a net '
            'gain of "2 ATP".',
      );
    }
    // Explain / Expand / Simplify / generic → a grounded text answer.
    return AiResponse(
      title: cmd,
      contextSummary: contextSummary,
      body: 'The electron transport chain creates a proton gradient across the '
          'inner mitochondrial membrane. ATP synthase uses this gradient to '
          'produce ATP.',
      sources: const [
        SourceRef(material: 'Transcript', location: '18:32'),
        SourceRef(material: 'Week 4 Slides', location: 'Slide 7'),
      ],
      sourcesAgree: true,
    );
  }
}
