import 'dart:ui' show Color;

/// One outline section — mirrors the web `OutlineData`. [type] is a free label
/// ("Introduction", "Body Paragraph", "Conclusion", …) that drives the tag hue.
class OutlineData {
  const OutlineData({
    required this.type,
    required this.title,
    required this.description,
    required this.bullets,
  });

  final String type;
  final String title;
  final String description;
  final List<String> bullets;

  OutlineData copyWith({
    String? type,
    String? title,
    String? description,
    List<String>? bullets,
  }) =>
      OutlineData(
        type: type ?? this.type,
        title: title ?? this.title,
        description: description ?? this.description,
        bullets: bullets ?? this.bullets,
      );

  factory OutlineData.fromJson(Map<String, dynamic> j) => OutlineData(
        type: (j['type'] ?? 'Body Paragraph') as String,
        title: (j['title'] ?? '') as String,
        description: (j['description'] ?? '') as String,
        bullets: ((j['bullets'] as List?) ?? const [])
            .map((b) => b.toString())
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'title': title,
        'description': description,
        'bullets': bullets,
      };

  /// Tag hue by section type — introduction=blue, conclusion=teal, body=amber
  /// (matches the web `outlineTagColor`).
  Color get tagColor {
    final t = type.toLowerCase();
    if (t.contains('introduction') || t.contains('intro')) {
      return const Color(0xFF3B82F6);
    }
    if (t.contains('conclusion')) return const Color(0xFF0D9488);
    return const Color(0xFFF59E0B);
  }
}
