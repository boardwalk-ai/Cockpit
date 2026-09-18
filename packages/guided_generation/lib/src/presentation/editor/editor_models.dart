import '../../formatters/citation_formatter.dart';

enum EditorTextAlign { left, center, right, justify }

class GuidedDocumentSection {
  const GuidedDocumentSection({
    required this.id,
    required this.title,
    required this.content,
  });

  final String id;
  final String title;
  final String content;

  GuidedDocumentSection copyWith({String? title, String? content}) {
    return GuidedDocumentSection(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
    );
  }
}

class GuidedDocument {
  const GuidedDocument({
    required this.title,
    required this.sections,
    this.sources = const [],
    this.citationStyle = CitationStyle.mla,
  });

  final String title;
  final List<GuidedDocumentSection> sections;
  final List<CitationSource> sources;
  final CitationStyle citationStyle;

  int get wordCount {
    final text = sections.map((section) => section.content).join(' ').trim();

    if (text.isEmpty) return 0;

    return text.split(RegExp(r'\s+')).length;
  }

  GuidedDocument copyWith({
    String? title,
    List<GuidedDocumentSection>? sections,
    List<CitationSource>? sources,
    CitationStyle? citationStyle,
  }) {
    return GuidedDocument(
      title: title ?? this.title,
      sections: sections ?? this.sections,
      sources: sources ?? this.sources,
      citationStyle: citationStyle ?? this.citationStyle,
    );
  }
}

class EditorFormattingState {
  const EditorFormattingState({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.alignment = EditorTextAlign.left,
    this.fontFamily = 'Arial',
  });

  final bool bold;
  final bool italic;
  final bool underline;
  final EditorTextAlign alignment;
  final String fontFamily;

  EditorFormattingState copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    EditorTextAlign? alignment,
    String? fontFamily,
  }) {
    return EditorFormattingState(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      alignment: alignment ?? this.alignment,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }
}
