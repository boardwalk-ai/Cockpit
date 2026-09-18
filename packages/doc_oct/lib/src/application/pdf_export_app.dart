import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:printing/printing.dart';

import '../domain/citation_templates.dart';
import '../domain/source.dart';
import '../theme/doc_tokens.dart';
import 'pdf_export.dart';

/// The Flutter-facing bridge to the pure-Dart [buildEssayPdf]: loads the bundled
/// fonts, maps the editor's live fields into an [EssayInput], and hands the
/// finished bytes to the platform (a browser download on web).
class DocPdf {
  DocPdf._();

  static DocFonts? _fonts;

  /// Loads (and caches) the four Tinos faces from the package's asset bundle.
  static Future<DocFonts> _loadFonts() async {
    if (_fonts != null) return _fonts!;
    Future<ByteData> load(String f) =>
        rootBundle.load('packages/doc_oct/fonts/$f');
    final results = await Future.wait([
      load('Tinos-Regular.ttf'),
      load('Tinos-Bold.ttf'),
      load('Tinos-Italic.ttf'),
      load('Tinos-BoldItalic.ttf'),
    ]);
    return _fonts = DocFonts.fromBytes(
      regular: results[0],
      bold: results[1],
      italic: results[2],
      boldItalic: results[3],
    );
  }

  static PdfStyle _pdfStyle(FormatStyle s) => switch (s) {
        FormatStyle.apa => PdfStyle.apa,
        FormatStyle.mla => PdfStyle.mla,
        FormatStyle.chicago => PdfStyle.chicago,
        FormatStyle.ieee => PdfStyle.ieee,
        FormatStyle.harvard => PdfStyle.harvard,
      };

  /// Builds an [EssayInput] from the editor's raw field values + body text +
  /// sources, formatting each reference for [style] via [CitationTemplates].
  static EssayInput inputFrom({
    required FormatStyle style,
    required String title,
    required String studentName,
    required String institution,
    required String course,
    required String instructor,
    required String date,
    required String abstractText,
    required String keywords,
    required String bodyText,
    required List<Source> sources,
  }) {
    final paragraphs = bodyText
        .replaceAll('\r\n', '\n')
        .split(RegExp(r'\n+'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    final refs = [
      for (var i = 0; i < sources.length; i++)
        CitationTemplates.reference(style, sources[i], i + 1),
    ];
    final t = title.trim().isEmpty ? 'Untitled Paper' : title.trim();
    return EssayInput(
      title: t,
      studentName: studentName.trim(),
      institution: institution.trim(),
      course: course.trim(),
      instructor: instructor.trim(),
      date: date.trim(),
      dateDayMonthYear: date.trim(),
      abstractText: abstractText.trim(),
      keywords: keywords.trim(),
      body: paragraphs,
      references: refs,
    );
  }

  /// Renders the finished bytes for [input] in [style].
  static Future<Uint8List> render({
    required EssayInput input,
    required FormatStyle style,
  }) async {
    final fonts = await _loadFonts();
    return buildEssayPdf(input: input, style: _pdfStyle(style), fonts: fonts);
  }

  /// Renders and hands the PDF to the platform — a download on web, the share
  /// sheet elsewhere. [docName] becomes the file name.
  static Future<void> exportAndShare({
    required EssayInput input,
    required FormatStyle style,
    required String docName,
  }) async {
    final bytes = await render(input: input, style: style);
    final safe = docName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    await Printing.sharePdf(
      bytes: bytes,
      filename: '${safe.isEmpty ? 'document' : safe}.pdf',
    );
  }
}
