/// A researched source — mirrors the web's `GoodSource` (the shape the scraper
/// yields). Citations are projected from this data, never stored as literal
/// strings, so a style change re-renders every citation.
///
/// Sources reach the app only through our own backend (frontend never calls
/// external scraper/AI APIs directly); this is the local model that backend
/// responses deserialize into.
class Source {
  const Source({
    required this.url,
    required this.title,
    this.author,
    this.publishedYear,
    this.publisher,
    this.fullContent = '',
  });

  final String url;
  final String title;
  final String? author;
  final String? publishedYear;
  final String? publisher;

  /// Scraped excerpt/body — used by AI features (via backend), not by citations.
  final String fullContent;

  factory Source.fromJson(Map<String, dynamic> j) => Source(
        url: (j['url'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        author: j['author'] as String?,
        publishedYear: j['publishedYear']?.toString(),
        publisher: j['publisher'] as String?,
        fullContent: (j['fullContent'] ?? '') as String,
      );
}
