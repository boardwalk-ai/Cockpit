import 'package:flutter/material.dart';

import 'notes_models.dart' show SourceRef;

/// Who spoke a segment (spec §9). Low-confidence detection stays [unknown].
enum Speaker { professor, student, speaker1, unknown }

extension SpeakerMeta on Speaker {
  String get label {
    switch (this) {
      case Speaker.professor:
        return 'Professor';
      case Speaker.student:
        return 'Student';
      case Speaker.speaker1:
        return 'Speaker 1';
      case Speaker.unknown:
        return 'Unknown Speaker';
    }
  }
}

/// Partial (still recognizing) vs stable (finalized) text (spec §5).
enum SegmentStatus { partial, stable }

/// Markers created in Panel 4, shown beside a segment (spec §15).
enum MarkerType { important, question, confusing, examHint, slideChange }

extension MarkerMeta on MarkerType {
  String get label {
    switch (this) {
      case MarkerType.important:
        return 'Important';
      case MarkerType.question:
        return 'Question';
      case MarkerType.confusing:
        return 'Confusing';
      case MarkerType.examHint:
        return 'Exam Hint';
      case MarkerType.slideChange:
        return 'Slide Change';
    }
  }

  IconData get icon {
    switch (this) {
      case MarkerType.important:
        return Icons.star_rounded;
      case MarkerType.question:
        return Icons.help_outline_rounded;
      case MarkerType.confusing:
        return Icons.psychology_alt_rounded;
      case MarkerType.examHint:
        return Icons.star_rounded;
      case MarkerType.slideChange:
        return Icons.slideshow_rounded;
    }
  }
}

/// A transcript segment (spec §24). Every source version is preserved; the UI
/// picks the display version but the raw ASR text is never lost.
@immutable
class TranscriptSegment {
  const TranscriptSegment({
    required this.id,
    required this.sessionId,
    required this.start,
    required this.end,
    required this.rawText,
    required this.speaker,
    required this.status,
    this.faithfulText,
    this.correctedText,
    this.speakerConfidence = 0.9,
    this.transcriptionConfidence = 0.95,
    this.language = 'en',
    this.audioChunkRef,
    this.deviceId = "Hein's iPhone",
    this.slide,
    this.markers = const [],
    this.typewriterLinked = false,
    this.magicPencilPage,
    this.revisions = const [],
    this.correctedBy,
  });

  final String id;
  final String sessionId;
  final String start; // "18:32"
  final String end;
  final String rawText;
  final String? faithfulText;
  final String? correctedText;
  final Speaker speaker;
  final SegmentStatus status;
  final double speakerConfidence;
  final double transcriptionConfidence;
  final String language;
  final String? audioChunkRef;
  final String deviceId;
  final SourceRef? slide;
  final List<MarkerType> markers;
  final bool typewriterLinked;
  final int? magicPencilPage;

  /// Prior text versions kept when a correction is made (spec §10).
  final List<String> revisions;
  final String? correctedBy;

  bool get isPartial => status == SegmentStatus.partial;
  bool get isCorrected => correctedText != null;
  bool get isLowConfidence => transcriptionConfidence < 0.6;
  bool get speakerUnsure => speakerConfidence < 0.6;

  /// The version shown to the reader: student correction wins, then the
  /// faithful post-processed text, then the raw ASR text.
  String get displayText => correctedText ?? faithfulText ?? rawText;

  TranscriptSegment copyWith({
    String? correctedText,
    bool clearCorrected = false,
    Speaker? speaker,
    List<MarkerType>? markers,
    bool? typewriterLinked,
    List<String>? revisions,
    String? correctedBy,
  }) {
    return TranscriptSegment(
      id: id,
      sessionId: sessionId,
      start: start,
      end: end,
      rawText: rawText,
      faithfulText: faithfulText,
      correctedText: clearCorrected ? null : (correctedText ?? this.correctedText),
      speaker: speaker ?? this.speaker,
      status: status,
      speakerConfidence: speakerConfidence,
      transcriptionConfidence: transcriptionConfidence,
      language: language,
      audioChunkRef: audioChunkRef,
      deviceId: deviceId,
      slide: slide,
      markers: markers ?? this.markers,
      typewriterLinked: typewriterLinked ?? this.typewriterLinked,
      magicPencilPage: magicPencilPage,
      revisions: revisions ?? this.revisions,
      correctedBy: clearCorrected ? null : (correctedBy ?? this.correctedBy),
    );
  }
}

/// Filters for transcript search (spec §16).
enum TranscriptFilter {
  all,
  professorOnly,
  questions,
  markers,
  corrections,
  linkedNotes,
  lowConfidence,
}

extension TranscriptFilterMeta on TranscriptFilter {
  String get label {
    switch (this) {
      case TranscriptFilter.all:
        return 'All Speakers';
      case TranscriptFilter.professorOnly:
        return 'Professor Only';
      case TranscriptFilter.questions:
        return 'Questions';
      case TranscriptFilter.markers:
        return 'Markers';
      case TranscriptFilter.corrections:
        return 'Corrections';
      case TranscriptFilter.linkedNotes:
        return 'Linked Notes';
      case TranscriptFilter.lowConfidence:
        return 'Low Confidence';
    }
  }
}
