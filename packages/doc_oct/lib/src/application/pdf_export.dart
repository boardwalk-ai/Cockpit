import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// The five citation styles Doc Oct exports. Kept independent of the Flutter
/// `FormatStyle` enum so this file stays pure Dart (no `dart:ui`) and can run in
/// a plain VM/test context for headless PDF generation and verification.
enum PdfStyle { apa, mla, chicago, ieee, harvard }

/// The document, as plain data. `body` is the prose split into paragraphs;
/// `references` are the already-formatted citation entries (per style, in
/// citation order — the exporter sorts them when the style calls for it).
class EssayInput {
  const EssayInput({
    required this.title,
    required this.studentName,
    required this.institution,
    required this.course,
    required this.instructor,
    required this.date,
    required this.dateDayMonthYear,
    required this.abstractText,
    required this.keywords,
    required this.body,
    required this.references,
  });

  final String title;
  final String studentName;
  final String institution;
  final String course;
  final String instructor;
  final String date; // "Month D, YYYY"
  final String dateDayMonthYear; // "D Month YYYY" (MLA)
  final String abstractText;
  final String keywords;
  final List<String> body;
  final List<String> references;

  String get authorLastName {
    final t = studentName.trim();
    if (t.isEmpty) return 'Student';
    return t.split(RegExp(r'\s+')).last;
  }
}

/// The four TNR-metric-compatible font faces (we bundle Tinos ≈ Times New
/// Roman). Rendering uses the [pw.Font] widgets; measurement uses a [PdfFont]
/// built from the same bytes against a throwaway document.
class DocFonts {
  DocFonts({
    required this.regular,
    required this.bold,
    required this.italic,
    required this.boldItalic,
  });

  final pw.Font regular;
  final pw.Font bold;
  final pw.Font italic;
  final pw.Font boldItalic;

  static DocFonts fromBytes({
    required ByteData regular,
    required ByteData bold,
    required ByteData italic,
    required ByteData boldItalic,
  }) =>
      DocFonts(
        regular: pw.Font.ttf(regular),
        bold: pw.Font.ttf(bold),
        italic: pw.Font.ttf(italic),
        boldItalic: pw.Font.ttf(boldItalic),
      );
}

// US Letter in PDF points (72pt = 1in).
const double _pageW = 612;
const double _pageH = 792;
const double _marginX = 72; // 1"
const double _marginBottom = 72; // 1"
const double _marginTop = 36; // 0.5" — the page-number band sits here
const double _headBand = 36; // header height → body begins at 1"
const double _contentW = _pageW - _marginX * 2; // 468
const double _indent = 36; // 0.5" first-line / hanging indent

final PdfColor _ink = PdfColor.fromInt(0xFF111827);

/// Builds the finished PDF bytes for [input] in [style].
Future<Uint8List> buildEssayPdf({
  required EssayInput input,
  required PdfStyle style,
  required DocFonts fonts,
}) async {
  // A throwaway document just to build measurable PdfFonts (metrics are
  // independent of which document they belong to).
  final measureDoc = PdfDocument();
  // buildFont is @protected but is the supported way to obtain a measurable
  // PdfFont (metrics are document-independent), so we opt in deliberately.
  // ignore: invalid_use_of_protected_member
  final mReg = fonts.regular.buildFont(measureDoc);
  // ignore: invalid_use_of_protected_member
  final mBold = fonts.bold.buildFont(measureDoc);

  final size = style == PdfStyle.ieee ? 10.0 : 12.0;
  final bodyMult = switch (style) {
    PdfStyle.apa || PdfStyle.mla || PdfStyle.chicago => 2.0,
    PdfStyle.ieee => 1.15,
    PdfStyle.harvard => 1.5,
  };
  final refMult = switch (style) {
    PdfStyle.apa || PdfStyle.mla => 2.0,
    PdfStyle.chicago || PdfStyle.ieee => 1.15,
    PdfStyle.harvard => 1.5,
  };
  final bodyLine = size * bodyMult;
  final refLine = size * refMult;

  final layout = _Layout(size: size, mReg: mReg, mBold: mBold, fonts: fonts);

  final flow = <pw.Widget>[];
  switch (style) {
    case PdfStyle.apa:
      _buildApa(flow, layout, input, bodyLine, refLine);
    case PdfStyle.mla:
      _buildMla(flow, layout, input, bodyLine, refLine);
    case PdfStyle.chicago:
      _buildChicago(flow, layout, input, bodyLine, refLine);
    case PdfStyle.ieee:
      _buildIeee(flow, layout, input, bodyLine, refLine);
    case PdfStyle.harvard:
      _buildHarvard(flow, layout, input, bodyLine, refLine);
  }

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: const PdfPageFormat(
          _pageW,
          _pageH,
          marginLeft: _marginX,
          marginRight: _marginX,
          marginTop: _marginTop,
          marginBottom: _marginBottom,
        ),
        theme: pw.ThemeData.withFont(
          base: fonts.regular,
          bold: fonts.bold,
          italic: fonts.italic,
          boldItalic: fonts.boldItalic,
        ),
      ),
      header: (context) => _header(context, style, input, size, fonts),
      build: (context) => flow,
    ),
  );
  return Uint8List.fromList(await doc.save());
}

/// The top-right page-number band (0.5"–1"). Always 36pt tall so the body
/// begins at exactly 1" whether or not a number shows.
pw.Widget _header(
  pw.Context context,
  PdfStyle style,
  EssayInput input,
  double size,
  DocFonts fonts,
) {
  final n = _displayNumber(style, context.pageNumber);
  final text = n == null
      ? ''
      : (style == PdfStyle.mla ? '${input.authorLastName} $n' : '$n');
  return pw.Container(
    height: _headBand,
    alignment: pw.Alignment.topRight,
    child: pw.Text(
      text,
      style: pw.TextStyle(font: fonts.regular, fontSize: size, color: _ink),
    ),
  );
}

/// The number to print on physical page [page] (1-based, global). IEEE numbers
/// nothing; Chicago starts "1" on page 2 (title page bare); the rest number
/// every page from 1.
int? _displayNumber(PdfStyle style, int page) => switch (style) {
      PdfStyle.ieee => null,
      PdfStyle.chicago => page <= 1 ? null : page - 1,
      _ => page,
    };

// ── Per-style flows ──────────────────────────────────────────────────────────

void _buildApa(List<pw.Widget> out, _Layout l, EssayInput i, double bodyLine,
    double refLine) {
  // Title page: title 3 double-spaced lines down, bold; one blank line; block.
  l.blank(out, bodyLine, 3);
  l.para(out, i.title, line: bodyLine, center: true, bold: true);
  l.blank(out, bodyLine, 1);
  for (final s in [i.studentName, i.institution, i.course, i.instructor, i.date]) {
    l.para(out, s, line: bodyLine, center: true);
  }
  out.add(pw.NewPage());
  // Abstract page.
  l.para(out, 'Abstract', line: bodyLine, center: true, bold: true);
  l.para(out, i.abstractText, line: bodyLine);
  l.keywords(out, i.keywords, line: bodyLine);
  out.add(pw.NewPage());
  // Body (repeats the title, bold + centered).
  l.para(out, i.title, line: bodyLine, center: true, bold: true);
  l.paras(out, i.body, line: bodyLine, firstIndent: _indent);
  out.add(pw.NewPage());
  // References — bold heading, hanging indent, alphabetized.
  l.references(out, 'References',
      entries: _sorted(i.references), line: refLine, hanging: true, bold: true);
}

void _buildMla(List<pw.Widget> out, _Layout l, EssayInput i, double bodyLine,
    double refLine) {
  for (final s in [i.studentName, i.instructor, i.course, i.dateDayMonthYear]) {
    l.para(out, s, line: bodyLine);
  }
  l.para(out, i.title, line: bodyLine, center: true);
  l.paras(out, i.body, line: bodyLine, firstIndent: _indent);
  out.add(pw.NewPage());
  l.references(out, 'Works Cited',
      entries: _sorted(i.references), line: refLine, hanging: true, bold: false);
}

void _buildChicago(List<pw.Widget> out, _Layout l, EssayInput i, double bodyLine,
    double refLine) {
  // Title page (no page number): title ~⅓ down, block ~⅔ down.
  l.blank(out, bodyLine, 7);
  l.para(out, i.title, line: bodyLine, center: true);
  l.blank(out, bodyLine, 6);
  for (final s in [i.studentName, i.course, i.instructor, i.date]) {
    l.para(out, s, line: bodyLine, center: true);
  }
  out.add(pw.NewPage());
  l.paras(out, i.body, line: bodyLine, firstIndent: _indent);
  out.add(pw.NewPage());
  // Bibliography — single-spaced entries, blank line between, hanging, A→Z.
  l.references(out, 'Bibliography',
      entries: _sorted(i.references),
      line: refLine,
      hanging: true,
      bold: true,
      headingGap: 12,
      entryGap: 12);
}

void _buildIeee(List<pw.Widget> out, _Layout l, EssayInput i, double bodyLine,
    double refLine) {
  l.para(out, i.title, line: bodyLine, center: true, bold: true, gapAfter: 12);
  l.para(out, i.studentName, line: bodyLine, center: true, gapAfter: 5);
  l.para(out, i.institution, line: bodyLine, center: true, gapAfter: 5);
  l.para(out, i.date, line: bodyLine, center: true, gapAfter: 12);
  l.paras(out, i.body, line: bodyLine, firstIndent: 0, gapAfter: 9);
  out.add(pw.NewPage());
  // References numbered in citation order — never alphabetized, no hanging.
  final numbered = [
    for (var k = 0; k < i.references.length; k++)
      '[${k + 1}] ${i.references[k].replaceFirst(RegExp(r'^\[\d+\]\s*'), '')}'
  ];
  l.references(out, 'References',
      entries: numbered,
      line: refLine,
      hanging: false,
      bold: true,
      headingGap: 10,
      entryGap: 8);
}

void _buildHarvard(List<pw.Widget> out, _Layout l, EssayInput i, double bodyLine,
    double refLine) {
  // Title page — centered block, 1.2em gaps.
  l.blank(out, bodyLine, 5);
  l.para(out, i.title, line: bodyLine, center: true, bold: true, gapAfter: 14);
  for (final s in [i.studentName, i.institution, i.course, i.instructor, i.date]) {
    l.para(out, s, line: bodyLine, center: true, gapAfter: 14);
  }
  out.add(pw.NewPage());
  l.para(out, i.title, line: bodyLine, center: true, bold: true, gapAfter: 19);
  l.paras(out, i.body, line: bodyLine, firstIndent: _indent);
  out.add(pw.NewPage());
  l.references(out, 'Reference List',
      entries: _sorted(i.references),
      line: refLine,
      hanging: true,
      bold: true,
      headingGap: 12,
      entryGap: 12);
}

// ── Bibliography ordering ────────────────────────────────────────────────────
String _sortKey(String entry) => entry
    .replaceFirst(RegExp(r'^\[\d+\]\s*'), '')
    .replaceFirst(RegExp(r'^[^\p{L}\p{N}]+', unicode: true), '')
    .toLowerCase();

List<String> _sorted(List<String> entries) {
  final copy = [...entries];
  copy.sort((a, b) => _sortKey(a).compareTo(_sortKey(b)));
  return copy;
}

// ── The line-layout engine ───────────────────────────────────────────────────
/// Lays paragraphs out line by line using real font metrics, so first-line and
/// hanging indents, spacing and pagination are all exact. Each line is a
/// fixed-height box (the line height), which MultiPage paginates between.
class _Layout {
  _Layout({
    required this.size,
    required this.mReg,
    required this.mBold,
    required this.fonts,
  });

  final double size;
  final PdfFont mReg;
  final PdfFont mBold;
  final DocFonts fonts;

  double _width(String s, PdfFont f) => f.stringMetrics(s).width * size;

  List<String> _wrap(String text, PdfFont f,
      {required double firstIndent, required double restIndent}) {
    final words = text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return const [''];
    final lines = <String>[];
    var cur = '';
    double avail() => _contentW - (lines.isEmpty ? firstIndent : restIndent);
    for (final w in words) {
      var word = w;
      while (true) {
        final trial = cur.isEmpty ? word : '$cur $word';
        if (_width(trial, f) <= avail()) {
          cur = trial;
          break;
        }
        if (cur.isNotEmpty) {
          lines.add(cur);
          cur = '';
          continue; // retry the word on a fresh line
        }
        // Single token wider than a whole line (e.g. a long URL): hard-break it
        // at the character that still fits, like CSS `word-break: break-all`.
        final fit = _maxPrefix(word, f, avail());
        if (fit <= 0) {
          cur = word; // degenerate: can't fit even one char — just place it
          break;
        }
        lines.add(word.substring(0, fit));
        word = word.substring(fit);
      }
    }
    if (cur.isNotEmpty || lines.isEmpty) lines.add(cur);
    return lines;
  }

  /// Largest prefix length of [word] whose width fits [avail] (binary search).
  int _maxPrefix(String word, PdfFont f, double avail) {
    var lo = 0, hi = word.length;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_width(word.substring(0, mid), f) <= avail) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  void blank(List<pw.Widget> out, double line, int n) {
    for (var k = 0; k < n; k++) {
      out.add(pw.SizedBox(height: line));
    }
  }

  /// One paragraph (may wrap). [center] centers every line (indents ignored).
  void para(
    List<pw.Widget> out,
    String text, {
    required double line,
    bool center = false,
    bool bold = false,
    double firstIndent = 0,
    double restIndent = 0,
    double gapAfter = 0,
  }) {
    final measure = bold ? mBold : mReg;
    final render = bold ? fonts.bold : fonts.regular;
    final lines = _wrap(text, measure,
        firstIndent: center ? 0 : firstIndent,
        restIndent: center ? 0 : restIndent);
    for (var idx = 0; idx < lines.length; idx++) {
      final ind = idx == 0 ? firstIndent : restIndent;
      out.add(_lineBox(lines[idx], render, line, center: center, indent: ind));
    }
    if (gapAfter > 0) out.add(pw.SizedBox(height: gapAfter));
  }

  /// A run of body paragraphs sharing one indent + spacing.
  void paras(
    List<pw.Widget> out,
    List<String> paragraphs, {
    required double line,
    double firstIndent = 0,
    double gapAfter = 0,
  }) {
    for (final p in paragraphs) {
      para(out, p, line: line, firstIndent: firstIndent, gapAfter: gapAfter);
    }
  }

  /// APA keywords line: italic "Keywords:" label, indented like a paragraph.
  void keywords(List<pw.Widget> out, String kw, {required double line}) {
    out.add(pw.Container(
      height: line,
      padding: const pw.EdgeInsets.only(left: _indent),
      alignment: pw.Alignment.centerLeft,
      child: pw.RichText(
        maxLines: 1,
        text: pw.TextSpan(children: [
          pw.TextSpan(
            text: 'Keywords: ',
            style: pw.TextStyle(font: fonts.italic, fontSize: size, color: _ink),
          ),
          pw.TextSpan(
            text: kw,
            style: pw.TextStyle(font: fonts.regular, fontSize: size, color: _ink),
          ),
        ]),
      ),
    ));
  }

  /// A references section: centered heading, then the entries.
  void references(
    List<pw.Widget> out,
    String heading, {
    required List<String> entries,
    required double line,
    required bool hanging,
    required bool bold,
    double headingGap = 0,
    double entryGap = 0,
  }) {
    para(out, heading, line: line, center: true, bold: bold);
    if (headingGap > 0) out.add(pw.SizedBox(height: headingGap));
    for (final e in entries) {
      para(out, e,
          line: line,
          firstIndent: 0,
          restIndent: hanging ? _indent : 0,
          gapAfter: entryGap);
    }
  }

  pw.Widget _lineBox(String text, pw.Font font, double line,
      {required bool center, required double indent}) {
    return pw.Container(
      height: line,
      alignment: center ? pw.Alignment.center : pw.Alignment.centerLeft,
      padding: center ? null : pw.EdgeInsets.only(left: indent),
      child: pw.Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: pw.TextStyle(font: font, fontSize: size, color: _ink),
      ),
    );
  }
}
