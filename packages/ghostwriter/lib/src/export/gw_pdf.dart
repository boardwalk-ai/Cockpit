import 'package:doc_oct/doc_oct.dart';

import '../data/gw_api.dart';

/// The essay as a formatted PDF, laid out by Doc Oct's exporter (title
/// page, page numbers, spacing and the references page of its citation
/// style), handed to the phone's share sheet (a download on the web).
abstract final class GwPdf {
  /// From the document as the API returns it.
  static Future<void> shareDocument(Map<String, dynamic> doc) {
    final raw = doc['fields'];
    final fields = <String, String>{
      if (raw is Map)
        for (final e in raw.entries)
          e.key.toString(): e.value?.toString() ?? '',
    };
    return share(
      style: doc['style']?.toString() ?? 'apa',
      title: doc['title']?.toString() ?? '',
      fields: fields,
      body: doc['body']?.toString() ?? '',
      bibliography: doc['bibliography']?.toString() ?? '',
    );
  }

  /// Fetches the project's document and shares it.
  static Future<void> shareProject(GwApi api, String projectId) async =>
      shareDocument(await api.document(projectId));

  /// [fields] uses the editor's keys (`studentName`, `instructorName`,
  /// `courseName`, `institutionName`, `date`); [bibliography] has one
  /// formatted reference per line.
  static Future<void> share({
    required String style,
    required String title,
    required Map<String, String> fields,
    required String body,
    required String bibliography,
  }) {
    final format = formatStyle(style);
    final date = fields['date']?.trim() ?? '';
    final input = DocPdf.inputFrom(
      style: format,
      title: title,
      studentName: fields['studentName'] ?? '',
      institution: fields['institutionName'] ?? '',
      course: fields['courseName'] ?? '',
      instructor: fields['instructorName'] ?? '',
      date: date.isEmpty ? today() : date,
      abstractText: '',
      keywords: '',
      bodyText: body,
      sources: const [],
      references: [
        for (final line in bibliography.split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
      ],
    );
    return DocPdf.exportAndShare(
      input: input,
      style: format,
      docName: title.trim().isEmpty ? 'essay' : title,
    );
  }

  /// The document's style; "none" is laid out like APA.
  static FormatStyle formatStyle(String style) => switch (style.toLowerCase()) {
    'mla' => FormatStyle.mla,
    'chicago' => FormatStyle.chicago,
    'ieee' => FormatStyle.ieee,
    'harvard' => FormatStyle.harvard,
    _ => FormatStyle.apa,
  };

  /// "March 4, 2026".
  static String today([DateTime? now]) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final d = now ?? DateTime.now();
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}
