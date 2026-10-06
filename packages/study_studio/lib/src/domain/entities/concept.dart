/// A key idea of a lesson, on its concept map.
class Concept {
  const Concept({
    required this.id,
    required this.name,
    this.meaning = '',
    this.example = '',
  });

  final String id;
  final String name;
  final String meaning;
  final String example;
}

/// How two ideas connect, read "[from] [label] [to]"; or, with [toTopic],
/// how an idea reaches into another lesson.
class ConceptLink {
  const ConceptLink({
    required this.from,
    required this.label,
    this.to,
    this.toTopic,
  });

  final String from;
  final String label;
  final String? to;

  /// Another lesson's title.
  final String? toTopic;
}
