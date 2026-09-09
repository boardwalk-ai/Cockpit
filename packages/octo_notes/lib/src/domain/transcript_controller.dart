import 'package:flutter/foundation.dart';

import 'notes_models.dart' show SourceRef;
import 'transcript_controller_playback.dart';
import 'transcript_models.dart';

/// Live Transcript store for Panel 7. Preserves three layers (raw / faithful /
/// corrected) — the raw ASR text is never overwritten (spec §2, §10). Handles
/// live vs partial segments, Follow Live, search/filter, corrections, and a
/// simulated audio player.
class TranscriptController extends ChangeNotifier {
  TranscriptController({required this.sessionId}) {
    _seed();
    playback = TranscriptPlayback(notifyListeners);
  }

  final String sessionId;
  late final TranscriptPlayback playback;

  final List<TranscriptSegment> _segments = [];
  TranscriptSegment? _partial;

  List<TranscriptSegment> get segments => List.unmodifiable(_segments);
  TranscriptSegment? get partial => _partial;

  // --- status --------------------------------------------------------------
  int delaySeconds = 3;
  bool get rawPreserved => true;

  // --- follow live ---------------------------------------------------------
  bool followLive = true;
  int newSincePause = 0;

  void setFollowLive(bool v) {
    followLive = v;
    if (v) newSincePause = 0;
    notifyListeners();
  }

  void jumpToLive() {
    followLive = true;
    newSincePause = 0;
    notifyListeners();
  }

  /// Called by the view when the student scrolls up (spec §7).
  void pauseFollowFromScroll() {
    if (!followLive) return;
    followLive = false;
    notifyListeners();
  }

  // --- selection -----------------------------------------------------------
  String? _selected;
  String? get selectedId => _selected;
  void select(String? id) {
    if (_selected == id) return;
    _selected = id;
    notifyListeners();
  }

  // --- search / filter -----------------------------------------------------
  String query = '';
  TranscriptFilter filter = TranscriptFilter.all;

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  void setFilter(TranscriptFilter f) {
    filter = f;
    notifyListeners();
  }

  List<TranscriptSegment> get visibleSegments {
    Iterable<TranscriptSegment> list = _segments;
    if (query.trim().isNotEmpty) {
      final q = query.toLowerCase();
      list = list.where((s) =>
          s.displayText.toLowerCase().contains(q) ||
          s.speaker.label.toLowerCase().contains(q) ||
          s.start.contains(q));
    }
    switch (filter) {
      case TranscriptFilter.all:
        break;
      case TranscriptFilter.professorOnly:
        list = list.where((s) => s.speaker == Speaker.professor);
      case TranscriptFilter.questions:
        list = list.where((s) =>
            s.speaker == Speaker.student ||
            s.markers.contains(MarkerType.question));
      case TranscriptFilter.markers:
        list = list.where((s) => s.markers.isNotEmpty);
      case TranscriptFilter.corrections:
        list = list.where((s) => s.isCorrected);
      case TranscriptFilter.linkedNotes:
        list = list.where((s) => s.typewriterLinked);
      case TranscriptFilter.lowConfidence:
        list = list.where((s) => s.isLowConfidence);
    }
    return list.toList();
  }

  bool get isSearching =>
      query.trim().isNotEmpty || filter != TranscriptFilter.all;

  // --- corrections (preserve raw) -----------------------------------------
  int _indexOf(String id) => _segments.indexWhere((s) => s.id == id);

  void correctText(String id, String text) {
    final i = _indexOf(id);
    if (i < 0) return;
    final s = _segments[i];
    _segments[i] = s.copyWith(
      correctedText: text,
      correctedBy: 'You',
      revisions: [...s.revisions, s.displayText],
    );
    notifyListeners();
  }

  void correctSpeaker(String id, Speaker speaker) {
    final i = _indexOf(id);
    if (i < 0) return;
    _segments[i] = _segments[i].copyWith(speaker: speaker);
    notifyListeners();
  }

  /// Restore the original raw wording (spec §10).
  void restoreOriginal(String id) {
    final i = _indexOf(id);
    if (i < 0) return;
    _segments[i] = _segments[i].copyWith(clearCorrected: true);
    notifyListeners();
  }

  void addMarker(String id, MarkerType marker) {
    final i = _indexOf(id);
    if (i < 0) return;
    final s = _segments[i];
    if (s.markers.contains(marker)) return;
    _segments[i] = s.copyWith(markers: [...s.markers, marker]);
    notifyListeners();
  }

  void markTypewriterLinked(String id) {
    final i = _indexOf(id);
    if (i < 0) return;
    _segments[i] = _segments[i].copyWith(typewriterLinked: true);
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Seed (mirrors the Panel 7 mock)
  // -------------------------------------------------------------------------
  void _seed() {
    TranscriptSegment seg(
      String id,
      String start,
      String end,
      Speaker sp,
      String text, {
      SourceRef? slide,
      List<MarkerType> markers = const [],
      bool linked = false,
      double conf = 0.96,
    }) {
      return TranscriptSegment(
        id: id,
        sessionId: sessionId,
        start: start,
        end: end,
        rawText: text,
        speaker: sp,
        status: SegmentStatus.stable,
        transcriptionConfidence: conf,
        slide: slide,
        markers: markers,
        typewriterLinked: linked,
        audioChunkRef: 'chunk-$id',
      );
    }

    _segments.addAll([
      seg('t1', '18:25', '18:31', Speaker.professor,
          'Glycolysis occurs in the cytoplasm and does not directly require oxygen.',
          slide: const SourceRef(material: 'Week 4 Slides', location: 'Slide 5')),
      seg('t2', '18:32', '18:43', Speaker.professor,
          'The net result is two ATP and two NADH.',
          slide: const SourceRef(material: 'Week 4 Slides', location: 'Slide 7'),
          markers: [MarkerType.examHint],
          linked: true),
      seg('t3', '18:44', '19:01', Speaker.professor,
          'Pyruvate then enters the mitochondria for the next stage.',
          slide: const SourceRef(material: 'Week 4 Slides', location: 'Slide 6')),
      seg('t4', '19:02', '19:07', Speaker.student,
          'Why is oxygen required indirectly?'),
      seg('t5', '19:08', '19:15', Speaker.professor,
          'Oxygen accepts electrons at the end of the transport chain.',
          slide: const SourceRef(material: 'Week 4 Slides', location: 'Slide 7')),
    ]);

    _partial = TranscriptSegment(
      id: 'partial',
      sessionId: sessionId,
      start: '19:16',
      end: '19:16',
      rawText: 'This proton gradient then powers ATP synthase',
      speaker: Speaker.professor,
      status: SegmentStatus.partial,
      transcriptionConfidence: 0.4,
    );
  }

  @override
  void dispose() {
    playback.dispose();
    super.dispose();
  }
}
