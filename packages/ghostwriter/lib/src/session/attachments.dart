/// A file attached to the next message: uploading, read (with its card), or
/// failed.
class GwAttachment {
  GwAttachment({required this.id, required this.name});

  final String id;
  final String name;

  /// The server's card once read: `kind`, `title`, `pages`, `words`,
  /// `summary`, `addressedToAi`.
  Map<String, dynamic>? card;

  /// Why it could not be read.
  String? error;

  bool get uploading => card == null && error == null;
  bool get ready => card != null;

  String get title => card?['title']?.toString() ?? name;
}

/// A short label for a card: "Essay · 3 pages".
String attachmentLabel(Map<String, dynamic> card) {
  final kind = switch (card['kind']) {
    'essay' => 'Essay',
    'assignment' => 'Assignment',
    'notes' => 'Notes',
    'article' => 'Article',
    _ => 'File',
  };
  final pages = card['pages'] is num ? (card['pages'] as num).toInt() : 0;
  return pages > 1 ? '$kind · $pages pages' : kind;
}
