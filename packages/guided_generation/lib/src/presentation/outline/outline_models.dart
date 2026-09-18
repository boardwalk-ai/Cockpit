enum OutlineKind {
  introduction('Introduction'),
  body('Body Paragraph'),
  conclusion('Conclusion');

  const OutlineKind(this.label);

  final String label;
}

class OutlineSection {
  const OutlineSection({
    required this.id,
    required this.kind,
    required this.title,
    required this.description,
    this.selected = false,
    this.hidden = false,
    this.isNew = false,
  });

  final String id;
  final OutlineKind kind;
  final String title;
  final String description;
  final bool selected;
  final bool hidden;
  final bool isNew;

  OutlineSection copyWith({
    String? title,
    String? description,
    bool? selected,
    bool? hidden,
    bool? isNew,
  }) {
    return OutlineSection(
      id: id,
      kind: kind,
      title: title ?? this.title,
      description: description ?? this.description,
      selected: selected ?? this.selected,
      hidden: hidden ?? this.hidden,
      isNew: isNew ?? this.isNew,
    );
  }
}
