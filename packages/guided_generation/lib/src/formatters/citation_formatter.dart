enum CitationStyle {
  mla('MLA'),
  apa('APA'),
  chicago('Chicago'),
  ieee('IEEE'),
  harvard('Harvard');

  const CitationStyle(this.label);

  final String label;
}

class CitationSource {
  const CitationSource({
    required this.id,
    required this.title,
    this.author,
    this.publisher,
    this.year,
    this.url,
    this.accessDate,
    this.content,
  });

  final String id;
  final String title;
  final String? author;
  final String? publisher;
  final String? year;
  final String? url;
  final String? accessDate;
  final String? content;

  factory CitationSource.fromJson(Map<String, dynamic> json) {
    return CitationSource(
      id: json['id']?.toString() ?? '',
      title: (json['title'] ?? json['Title'])?.toString() ?? 'Untitled Source',
      author: json['author']?.toString(),
      publisher: json['publisher']?.toString(),
      year: (json['year'] ?? json['publishedYear'])?.toString(),
      url: (json['url'] ?? json['website_URL'])?.toString(),
      accessDate: json['accessDate']?.toString(),
      content:
          (json['compactedContent'] ?? json['fullContent'] ?? json['abstract'])
              ?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    if (author != null) 'author': author,
    if (publisher != null) 'publisher': publisher,
    if (year != null) 'year': year,
    if (url != null) 'url': url,
    if (accessDate != null) 'accessDate': accessDate,
    if (content != null) 'compactedContent': content,
  };
}

extension CitationStyleX on CitationStyle {
  static CitationStyle fromLabel(String? value) {
    final normalized = value?.trim().toLowerCase();
    return CitationStyle.values.firstWhere(
      (style) => style.label.toLowerCase() == normalized,
      orElse: () => CitationStyle.apa,
    );
  }
}

class CitationFormatter {
  const CitationFormatter();

  String bibliographyTitle(CitationStyle style) {
    return switch (style) {
      CitationStyle.mla => 'Works Cited',
      CitationStyle.chicago => 'Bibliography',
      CitationStyle.harvard => 'Reference List',
      CitationStyle.apa || CitationStyle.ieee => 'References',
    };
  }

  String inlineCitation(
    CitationSource source,
    CitationStyle style, {
    int? index,
  }) {
    final author = _authorName(source.author);

    switch (style) {
      case CitationStyle.mla:
        return author.isEmpty ? '(${source.title})' : '($author)';
      case CitationStyle.apa:
        return author.isEmpty
            ? '(${source.title}, ${source.year ?? 'n.d.'})'
            : '($author, ${source.year ?? 'n.d.'})';
      case CitationStyle.chicago:
        return author.isEmpty ? '(${source.title})' : '($author)';
      case CitationStyle.ieee:
        return '[${index ?? 1}]';
      case CitationStyle.harvard:
        return author.isEmpty
            ? '(${source.title}, ${source.year ?? 'n.d.'})'
            : '($author ${source.year ?? 'n.d.'})';
    }
  }

  String bibliographyEntry(
    CitationSource source,
    CitationStyle style, {
    int? index,
  }) {
    final author = _clean(source.author);
    final publisher = _clean(source.publisher);
    final year = _clean(source.year);
    final url = _clean(source.url);
    final accessed = _clean(source.accessDate);

    switch (style) {
      case CitationStyle.mla:
        return _join([
          _sentence(author),
          '"${source.title}."',
          _comma(publisher),
          _comma(year),
          url,
        ]);

      case CitationStyle.apa:
        return _join([
          author,
          year.isEmpty ? '(n.d.).' : '($year).',
          '${source.title}.',
          publisher,
          url,
        ]);

      case CitationStyle.chicago:
        return _join([
          _sentence(author),
          '"${source.title}."',
          _sentence(publisher),
          year.isEmpty ? '' : '$year.',
          url,
        ]);

      case CitationStyle.ieee:
        return _join([
          '[${index ?? 1}]',
          _comma(author),
          '"${source.title},"',
          _comma(publisher),
          year,
          url,
        ]);

      case CitationStyle.harvard:
        return _join([
          _comma(author),
          year.isEmpty ? 'n.d.' : '$year.',
          '${source.title}.',
          publisher,
          url,
          accessed.isEmpty ? '' : '(Accessed: $accessed).',
        ]);
    }
  }

  List<String> bibliography(List<CitationSource> sources, CitationStyle style) {
    final entries = [
      for (var i = 0; i < sources.length; i++)
        bibliographyEntry(sources[i], style, index: i + 1),
    ];

    if (style != CitationStyle.ieee) {
      entries.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }

    return entries;
  }

  String _authorName(String? value) {
    final author = _clean(value);
    if (author.isEmpty) return '';

    if (author.contains(',')) {
      return author.split(',').first.trim();
    }

    final parts = author.split(RegExp(r'\s+'));
    return parts.last;
  }

  String _clean(String? value) => value?.trim() ?? '';

  String _sentence(String value) {
    if (value.isEmpty) return '';
    return value.endsWith('.') ? value : '$value.';
  }

  String _comma(String value) {
    if (value.isEmpty) return '';
    return value.endsWith(',') ? value : '$value,';
  }

  String _join(List<String> parts) {
    return parts.where((part) => part.trim().isNotEmpty).join(' ');
  }
}
