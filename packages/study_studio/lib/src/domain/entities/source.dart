enum SourceFileType { pdf, docx, pptx, txt, image, audio, video }

/// An uploaded material that the AI ingested to build the studio.
class SourceFile {
  const SourceFile({
    required this.id,
    required this.name,
    required this.type,
    this.processed = true,
  });

  final String id;
  final String name;
  final SourceFileType type;
  final bool processed;
}

/// Where a Study Object's content came from — enables "View Source" grounding.
class SourceReference {
  const SourceReference({
    required this.fileName,
    required this.snippet,
    this.page,
  });

  final String fileName;
  final String snippet;
  final int? page;
}
