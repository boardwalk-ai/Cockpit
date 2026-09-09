import '../theme/doc_tokens.dart';

/// A saved Doc Oct document, as shown on the Saved Projects page.
class SavedProject {
  const SavedProject({
    required this.id,
    required this.title,
    required this.style,
    required this.words,
    required this.updatedAt,
    this.snippet = '',
  });

  final String id;
  final String title;
  final FormatStyle style;
  final int words;
  final DateTime updatedAt;

  /// A short preview line from the document body.
  final String snippet;

  /// Rough page estimate (~250 words/page), matching the web heuristic.
  int get pages => words == 0 ? 1 : (words / 250).ceil();
}
