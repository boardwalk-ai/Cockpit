import '../theme/doc_tokens.dart';
import 'source.dart';

/// Deterministic per-style citation formatting — a direct Dart port of the web
/// `CitationTemplateService`. Pure functions over [Source] data, so switching
/// citation style re-renders every in-text mark and reference losslessly.
///
/// (The AI-assisted citation path in the web app runs server-side; that stays
/// on our Rust backend. These templates are the deterministic fallback and the
/// on-device renderer.)
abstract final class CitationTemplates {
  /// The in-text mark, e.g. MLA `(Smith)`, APA `(Smith, 2020)`, IEEE `[3]`.
  static String inText(FormatStyle style, Source s, int index) {
    final surname = _surname(s.author);
    final year = _year(s);
    return switch (style) {
      FormatStyle.ieee => '[$index]',
      FormatStyle.mla => '($surname)',
      FormatStyle.chicago => '($surname $year)',
      FormatStyle.harvard => '($surname, $year)',
      FormatStyle.apa => '($surname, $year)',
    };
  }

  /// A full bibliography/works-cited/references entry for [style].
  static String reference(FormatStyle style, Source s, int index) {
    final author = s.author?.trim().isNotEmpty == true ? s.author!.trim() : 'Unknown';
    final surname = _surname(s.author);
    final year = _year(s);
    final title = s.title.trim().isEmpty ? 'Untitled Source' : s.title.trim();
    final publisher =
        s.publisher?.trim().isNotEmpty == true ? s.publisher!.trim() : 'Unknown Publisher';
    final url = s.url.trim();

    return switch (style) {
      FormatStyle.ieee =>
        '[$index] $author, "$title," $publisher, $year.${url.isNotEmpty ? ' [Online]. Available: $url' : ''}'
            .trim(),
      FormatStyle.mla =>
        '$author. "$title." $publisher, $year.${url.isNotEmpty ? ' $url.' : ''}'.trim(),
      FormatStyle.chicago =>
        '$author. "$title." $publisher, $year.${url.isNotEmpty ? ' $url.' : ''}'.trim(),
      FormatStyle.harvard =>
        '$surname, $year. $title. $publisher.${url.isNotEmpty ? ' Available at: $url' : ''}'
            .trim(),
      FormatStyle.apa =>
        '$surname. ($year). $title. $publisher.${url.isNotEmpty ? ' $url' : ''}'.trim(),
    };
  }

  // ── helpers (ported) ───────────────────────────────────────────────────────
  static String _year(Source s) {
    final m = RegExp(r'\d{4}').firstMatch(s.publishedYear ?? '');
    return m?.group(0) ?? 'n.d.';
  }

  static String _firstAuthorChunk(String? author) {
    final src = (author ?? '').trim();
    if (src.isEmpty) return 'Unknown';
    final parts = src.split(RegExp(r';| and |&|,', caseSensitive: false));
    return parts.map((p) => p.trim()).firstWhere((p) => p.isNotEmpty,
        orElse: () => 'Unknown');
  }

  static String _surname(String? author) {
    final first = _firstAuthorChunk(author);
    if (first.contains(',')) {
      final s = first.split(',')[0].trim();
      return s.isEmpty ? 'Unknown' : s;
    }
    final tokens = first.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    return tokens.isEmpty ? 'Unknown' : tokens.last;
  }
}
