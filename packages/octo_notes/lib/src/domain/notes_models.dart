import 'package:flutter/material.dart';

/// The kind of a note block. Grouped into three categories (text / academic /
/// rich-content) per the Panel 5 spec (`docs/panel-05-typewriter.md` §4).
enum BlockType {
  // Text
  paragraph,
  h1,
  h2,
  h3,
  bulleted,
  numbered,
  checklist,
  quote,
  // Academic
  definition,
  keyIdea,
  formula,
  example,
  question,
  examHint,
  warning,
  assignment,
  summary,
  // Rich content
  table,
  image,
  diagram,
  slideRef,
  pdfExcerpt,
  transcriptExcerpt,
  audioTimestamp,
  divider,
}

enum BlockCategory { text, academic, rich }

extension BlockTypeMeta on BlockType {
  BlockCategory get category {
    switch (this) {
      case BlockType.paragraph:
      case BlockType.h1:
      case BlockType.h2:
      case BlockType.h3:
      case BlockType.bulleted:
      case BlockType.numbered:
      case BlockType.checklist:
      case BlockType.quote:
        return BlockCategory.text;
      case BlockType.definition:
      case BlockType.keyIdea:
      case BlockType.formula:
      case BlockType.example:
      case BlockType.question:
      case BlockType.examHint:
      case BlockType.warning:
      case BlockType.assignment:
      case BlockType.summary:
        return BlockCategory.academic;
      case BlockType.table:
      case BlockType.image:
      case BlockType.diagram:
      case BlockType.slideRef:
      case BlockType.pdfExcerpt:
      case BlockType.transcriptExcerpt:
      case BlockType.audioTimestamp:
      case BlockType.divider:
        return BlockCategory.rich;
    }
  }

  /// Human label used in menus and the block-type picker.
  String get label {
    switch (this) {
      case BlockType.paragraph:
        return 'Text';
      case BlockType.h1:
        return 'Heading 1';
      case BlockType.h2:
        return 'Heading 2';
      case BlockType.h3:
        return 'Heading 3';
      case BlockType.bulleted:
        return 'Bulleted list';
      case BlockType.numbered:
        return 'Numbered list';
      case BlockType.checklist:
        return 'Checklist';
      case BlockType.quote:
        return 'Quote';
      case BlockType.definition:
        return 'Definition';
      case BlockType.keyIdea:
        return 'Key Idea';
      case BlockType.formula:
        return 'Formula';
      case BlockType.example:
        return 'Example';
      case BlockType.question:
        return 'Question';
      case BlockType.examHint:
        return 'Exam Hint';
      case BlockType.warning:
        return 'Warning';
      case BlockType.assignment:
        return 'Assignment';
      case BlockType.summary:
        return 'Summary';
      case BlockType.table:
        return 'Table';
      case BlockType.image:
        return 'Image';
      case BlockType.diagram:
        return 'Diagram';
      case BlockType.slideRef:
        return 'Slide reference';
      case BlockType.pdfExcerpt:
        return 'PDF excerpt';
      case BlockType.transcriptExcerpt:
        return 'Transcript excerpt';
      case BlockType.audioTimestamp:
        return 'Audio timestamp';
      case BlockType.divider:
        return 'Divider';
    }
  }

  IconData get icon {
    switch (this) {
      case BlockType.paragraph:
        return Icons.notes_rounded;
      case BlockType.h1:
        return Icons.title_rounded;
      case BlockType.h2:
        return Icons.text_fields_rounded;
      case BlockType.h3:
        return Icons.short_text_rounded;
      case BlockType.bulleted:
        return Icons.format_list_bulleted_rounded;
      case BlockType.numbered:
        return Icons.format_list_numbered_rounded;
      case BlockType.checklist:
        return Icons.checklist_rounded;
      case BlockType.quote:
        return Icons.format_quote_rounded;
      case BlockType.definition:
        return Icons.menu_book_rounded;
      case BlockType.keyIdea:
        return Icons.key_rounded;
      case BlockType.formula:
        return Icons.functions_rounded;
      case BlockType.example:
        return Icons.lightbulb_outline_rounded;
      case BlockType.question:
        return Icons.help_outline_rounded;
      case BlockType.examHint:
        return Icons.star_rounded;
      case BlockType.warning:
        return Icons.warning_amber_rounded;
      case BlockType.assignment:
        return Icons.assignment_outlined;
      case BlockType.summary:
        return Icons.description_outlined;
      case BlockType.table:
        return Icons.table_chart_outlined;
      case BlockType.image:
        return Icons.image_outlined;
      case BlockType.diagram:
        return Icons.schema_rounded;
      case BlockType.slideRef:
        return Icons.slideshow_rounded;
      case BlockType.pdfExcerpt:
        return Icons.picture_as_pdf_rounded;
      case BlockType.transcriptExcerpt:
        return Icons.record_voice_over_rounded;
      case BlockType.audioTimestamp:
        return Icons.audiotrack_rounded;
      case BlockType.divider:
        return Icons.horizontal_rule_rounded;
    }
  }

  /// Whether this block holds editable rich text (vs. a placeholder embed).
  bool get isTextEditable {
    switch (this) {
      case BlockType.table:
      case BlockType.image:
      case BlockType.diagram:
      case BlockType.slideRef:
      case BlockType.pdfExcerpt:
      case BlockType.transcriptExcerpt:
      case BlockType.audioTimestamp:
      case BlockType.divider:
        return false;
      default:
        return true;
    }
  }

  String get placeholder {
    switch (this) {
      case BlockType.h1:
        return 'Heading 1';
      case BlockType.h2:
        return 'Heading 2';
      case BlockType.h3:
        return 'Heading 3';
      case BlockType.bulleted:
      case BlockType.numbered:
      case BlockType.checklist:
        return 'List item';
      case BlockType.quote:
        return 'Quote';
      case BlockType.definition:
        return 'Term — definition';
      default:
        return "Type '/' for commands";
    }
  }
}

/// Where a block's content came from. Unapproved AI never becomes a block — it
/// lives as an [AiSuggestion]. Once the student approves a suggestion, the
/// inserted block is [aiInsertedByStudent] and keeps its [AiSuggestion.sources].
enum BlockOrigin { student, aiInsertedByStudent }

/// Block-level synchronization state (spec §18).
enum SyncState { saved, saving, offline, reconnecting, conflict, synced }

extension SyncStateMeta on SyncState {
  String get label {
    switch (this) {
      case SyncState.saved:
        return 'Saved';
      case SyncState.saving:
        return 'Saving…';
      case SyncState.offline:
        return 'Offline';
      case SyncState.reconnecting:
        return 'Reconnecting…';
      case SyncState.conflict:
        return 'Conflict';
      case SyncState.synced:
        return 'Synced';
    }
  }
}

/// A link to a slide / material (spec §11). Selecting it should open the exact
/// source location.
@immutable
class SourceRef {
  const SourceRef({required this.material, required this.location});
  final String material; // e.g. "Week 4 Slides"
  final String location; // e.g. "Slide 7"

  String get chipLabel => '$material · $location';
}

/// A transcript / audio anchor (spec §9, §10).
@immutable
class TranscriptAnchor {
  const TranscriptAnchor({
    required this.time,
    required this.speaker,
    required this.excerpt,
  });
  final String time; // "18:32"
  final String speaker;
  final String excerpt;
}

/// The authoritative student note block (spec §22). Immutable; mutate via
/// [copyWith] so undo snapshots stay stable and origin is never lost.
@immutable
class TypedBlock {
  const TypedBlock({
    required this.id,
    required this.sessionId,
    required this.parentSection,
    required this.type,
    required this.text,
    required this.origin,
    required this.createdAt,
    required this.modifiedAt,
    required this.device,
    this.checked = false,
    this.indent = 0,
    this.audioTimestamp,
    this.transcriptAnchor,
    this.source,
    this.topicLinks = const [],
    this.assignmentLinks = const [],
    this.studyStudioSelected = false,
    this.revision = 1,
    this.syncState = SyncState.synced,
    this.aiSources = const [],
  });

  final String id;
  final String sessionId;
  final String parentSection;
  final BlockType type;
  final String text;
  final bool checked;
  final int indent;
  final BlockOrigin origin;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final String device;
  final String? audioTimestamp;
  final TranscriptAnchor? transcriptAnchor;
  final SourceRef? source;
  final List<String> topicLinks;
  final List<String> assignmentLinks;
  final bool studyStudioSelected;
  final int revision;
  final SyncState syncState;

  /// When [origin] is [BlockOrigin.aiInsertedByStudent], the source references
  /// carried over from the approved [AiSuggestion].
  final List<SourceRef> aiSources;

  bool get isAi => origin == BlockOrigin.aiInsertedByStudent;

  TypedBlock copyWith({
    BlockType? type,
    String? text,
    bool? checked,
    int? indent,
    BlockOrigin? origin,
    DateTime? modifiedAt,
    String? audioTimestamp,
    TranscriptAnchor? transcriptAnchor,
    SourceRef? source,
    bool clearSource = false,
    List<String>? topicLinks,
    List<String>? assignmentLinks,
    bool? studyStudioSelected,
    int? revision,
    SyncState? syncState,
    List<SourceRef>? aiSources,
    String? parentSection,
  }) {
    return TypedBlock(
      id: id,
      sessionId: sessionId,
      parentSection: parentSection ?? this.parentSection,
      type: type ?? this.type,
      text: text ?? this.text,
      checked: checked ?? this.checked,
      indent: indent ?? this.indent,
      origin: origin ?? this.origin,
      createdAt: createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      device: device,
      audioTimestamp: audioTimestamp ?? this.audioTimestamp,
      transcriptAnchor: transcriptAnchor ?? this.transcriptAnchor,
      source: clearSource ? null : (source ?? this.source),
      topicLinks: topicLinks ?? this.topicLinks,
      assignmentLinks: assignmentLinks ?? this.assignmentLinks,
      studyStudioSelected: studyStudioSelected ?? this.studyStudioSelected,
      revision: revision ?? this.revision,
      syncState: syncState ?? this.syncState,
      aiSources: aiSources ?? this.aiSources,
    );
  }
}

/// The kind of assistance an [AiSuggestion] represents (spec §12).
enum AiAction {
  expand,
  explain,
  simplify,
  define,
  example,
  research,
  compare,
  expandKeywords,
}

extension AiActionMeta on AiAction {
  String get label {
    switch (this) {
      case AiAction.expand:
        return 'Expand';
      case AiAction.explain:
        return 'Explain';
      case AiAction.simplify:
        return 'Simplify';
      case AiAction.define:
        return 'Define';
      case AiAction.example:
        return 'Example';
      case AiAction.research:
        return 'Research';
      case AiAction.compare:
        return 'Compare';
      case AiAction.expandKeywords:
        return 'Expand keywords';
    }
  }
}

/// Unapproved AI material. Stored **separately** from student blocks (spec §14,
/// §22). Rendered as a distinct tinted card; only enters the note when the
/// student approves it.
@immutable
class AiSuggestion {
  const AiSuggestion({
    required this.id,
    required this.sourceBlockId,
    required this.action,
    required this.contextLabel,
    required this.body,
    required this.sources,
    required this.createdAt,
  });

  final String id;
  final String sourceBlockId;
  final AiAction action;
  final String contextLabel; // e.g. "Based on transcript and Slide 7"
  final String body;
  final List<SourceRef> sources;
  final DateTime createdAt;
}
