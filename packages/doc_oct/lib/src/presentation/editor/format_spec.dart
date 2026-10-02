import 'package:flutter/material.dart';

import '../../domain/citation_templates.dart';
import '../../domain/source.dart';
import '../../theme/doc_tokens.dart';
import 'doc_model.dart';
import 'indented_text.dart';

/// Per-style paper metrics (ported from the web formatter `profile`s). Drives
/// the paper font size, line spacing and the body first-line indent.
class FormatProfile {
  const FormatProfile({
    this.fontSize = 16, // 12pt @96dpi
    this.lineHeight = 2,
    this.firstLineIndent = 48, // 0.5"
  });

  final double fontSize;
  final double lineHeight;
  final double firstLineIndent;

  /// One line's height in px — used for vertical spacers on the title pages.
  double get linePx => fontSize * lineHeight;
}

/// Bound, editable content the [FormatSpec] projects into pages. The controllers
/// ARE the document (the truth); a style change re-projects the same
/// controllers, so nothing is lost when switching APA↔MLA.
class EditorFields {
  EditorFields({
    required this.title,
    required this.fields,
    required this.abstractText,
    required this.keywords,
    required this.baseStyle,
    required this.hintColor,
    required this.cursorColor,
  });

  final TextEditingController title;
  final Map<DocFieldKind, TextEditingController> fields;
  final TextEditingController abstractText;
  final TextEditingController keywords;

  /// Serif paper base style (font, size, double-spacing, ink colour).
  final TextStyle baseStyle;
  final Color hintColor;
  final Color cursorColor;

  Widget editable(
    TextEditingController controller, {
    required String hint,
    TextAlign align = TextAlign.center,
    TextStyle? style,
    int? maxLines = 1,
  }) =>
      _EditableLine(
        controller: controller,
        hint: hint,
        align: align,
        style: style ?? baseStyle,
        hintColor: hintColor,
        cursorColor: cursorColor,
        maxLines: maxLines,
      );

  Widget field(DocFieldKind kind,
          {TextAlign align = TextAlign.center, bool bold = false}) =>
      editable(
        fields[kind]!,
        hint: kind.placeholder,
        align: align,
        style: baseStyle.copyWith(
            fontWeight: bold ? FontWeight.bold : FontWeight.normal),
      );

  String get authorLastName {
    final t = fields[DocFieldKind.studentName]!.text.trim();
    if (t.isEmpty) return 'Lastname';
    return t.split(RegExp(r'\s+')).last;
  }
}

/// A borderless, paper-native editable line — no box, no underline; the ink and
/// the caret are all that show.
class _EditableLine extends StatelessWidget {
  const _EditableLine({
    required this.controller,
    required this.hint,
    required this.align,
    required this.style,
    required this.hintColor,
    required this.cursorColor,
    required this.maxLines,
  });

  final TextEditingController controller;
  final String hint;
  final TextAlign align;
  final TextStyle style;
  final Color hintColor;
  final Color cursorColor;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textAlign: align,
      style: style,
      maxLines: maxLines,
      cursorColor: cursorColor,
      cursorWidth: 1.5,
      decoration: InputDecoration.collapsed(
        hintText: hint,
        hintStyle: style.copyWith(color: hintColor),
      ),
    );
  }
}

/// A single laid-out page: its flowing content (running head + number are drawn
/// by the pager from [runningHead]).
class DocPage {
  const DocPage({
    required this.content,
    this.runningHead,
    this.showPageNumber = true,
  });
  final Widget content;

  /// Left side of the running-head line (right side is the page number).
  final Widget? runningHead;

  /// Whether the page-number/running-head line shows (off for e.g. a Chicago
  /// title page, or IEEE which numbers no pages).
  final bool showPageNumber;
}

/// Projects the semantic fields into paginated pages for one citation style.
/// Presentation-level for now; the print/PDF spec shares the same idea.
abstract class FormatSpec {
  const FormatSpec();

  factory FormatSpec.of(FormatStyle style) => switch (style) {
        FormatStyle.apa => const ApaSpec(),
        FormatStyle.mla => const MlaSpec(),
        FormatStyle.chicago => const ChicagoSpec(),
        FormatStyle.ieee => const IeeeSpec(),
        FormatStyle.harvard => const HarvardSpec(),
      };

  /// Paper metrics (font size, line height, first-line indent) for this style.
  FormatProfile get profile => const FormatProfile();

  /// [body] is the shared prose editor; each style places it where its body
  /// begins (MLA: after the title on page 1; APA: on its own page after the
  /// abstract). [sources] feed the references page, formatted per [style].
  List<DocPage> buildPages(
    BuildContext context,
    EditorFields f, {
    required Widget body,
    required List<Source> sources,
    required FormatStyle style,
  });
}

/// Shared paper metrics + a couple of helpers.
extension _Paper on FormatSpec {
  Widget runningHeadPlaceholder(BuildContext context, String text) => Text(
        text,
        style: TextStyle(
          fontFamily: 'packages/doc_oct/Tinos',
          fontFamilyFallback: const ['Georgia', 'serif'],
          fontSize: 13,
          color: const Color(0xFF9AA0AA),
        ),
      );

  /// The references/works-cited/bibliography page, formatted per [style]:
  /// heading (bold for APA, plain for MLA), entries via [CitationTemplates],
  /// alphabetized (or numbered for IEEE), double-spaced.
  Widget bibliographyPage(EditorFields f, List<Source> sources, FormatStyle style) {
    final meta = _bibMeta(style);
    final entries = [...sources];
    if (!meta.numbered) {
      entries.sort((a, b) => (a.author ?? a.title)
          .toLowerCase()
          .compareTo((b.author ?? b.title).toLowerCase()));
    }
    // Hanging indent (0.5") for author-date styles; none when numbered (IEEE).
    final hang = meta.numbered ? 0.0 : 48.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          meta.heading,
          textAlign: TextAlign.center,
          style: f.baseStyle
              .copyWith(fontWeight: meta.bold ? FontWeight.bold : FontWeight.normal),
        ),
        if (entries.isEmpty)
          // No fake/placeholder citations — a new document has none until the
          // user adds a real source.
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'No sources yet. Add sources from the Tools panel to build your '
              '${meta.heading.toLowerCase()}.',
              textAlign: TextAlign.center,
              style: f.baseStyle.copyWith(
                color: f.hintColor,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          for (var i = 0; i < entries.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: meta.entryGap),
              child: IndentedText(
                CitationTemplates.reference(style, entries[i], i + 1),
                style: f.baseStyle,
                restIndent: hang,
              ),
            ),
      ],
    );
  }

  ({String heading, bool bold, bool numbered, double entryGap}) _bibMeta(
          FormatStyle s) =>
      switch (s) {
        FormatStyle.mla =>
          (heading: 'Works Cited', bold: false, numbered: false, entryGap: 0),
        FormatStyle.apa =>
          (heading: 'References', bold: true, numbered: false, entryGap: 0),
        FormatStyle.chicago =>
          (heading: 'Bibliography', bold: true, numbered: false, entryGap: 16),
        FormatStyle.ieee =>
          (heading: 'References', bold: true, numbered: true, entryGap: 12),
        FormatStyle.harvard => (
            heading: 'Reference List',
            bold: true,
            numbered: false,
            entryGap: 16
          ),
      };

  /// A vertical spacer of [lines] blank lines at the profile's line height.
  Widget spacer(int lines) => SizedBox(height: lines * profile.linePx);
}

/// APA 7 (student paper): a centred title page, then an Abstract page.
class ApaSpec extends FormatSpec {
  const ApaSpec();

  @override
  List<DocPage> buildPages(
    BuildContext context,
    EditorFields f, {
    required Widget body,
    required List<Source> sources,
    required FormatStyle style,
  }) {
    final titleText =
        f.title.text.trim().isEmpty ? 'Untitled Paper' : f.title.text.trim();
    return [
      // ── Title page ──
      DocPage(
        runningHead:
            runningHeadPlaceholder(context, 'Double-click to add a running head'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 120),
            f.editable(f.title,
                hint: 'Untitled Paper',
                align: TextAlign.center,
                style: f.baseStyle.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            f.field(DocFieldKind.studentName),
            f.field(DocFieldKind.institutionName),
            f.field(DocFieldKind.courseName),
            f.field(DocFieldKind.instructorName),
            f.field(DocFieldKind.date),
          ],
        ),
      ),
      // ── Abstract page ──
      DocPage(
        runningHead: const SizedBox.shrink(),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Abstract',
                textAlign: TextAlign.center,
                style: f.baseStyle.copyWith(fontWeight: FontWeight.bold)),
            f.editable(
              f.abstractText,
              hint: 'Write your abstract here (150–250 words). Summarise the '
                  'research question, method, findings, and conclusion.',
              align: TextAlign.left,
              maxLines: null,
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('Keywords: ',
                    style: f.baseStyle.copyWith(fontStyle: FontStyle.italic)),
                Expanded(
                  child: f.editable(
                    f.keywords,
                    hint: 'keyword1, keyword2, keyword3',
                    align: TextAlign.left,
                    style: f.baseStyle.copyWith(fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      // ── Body page (APA repeats the title, bold + centered) ──
      DocPage(
        runningHead: const SizedBox.shrink(),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              titleText,
              textAlign: TextAlign.center,
              style: f.baseStyle.copyWith(fontWeight: FontWeight.bold),
            ),
            body,
          ],
        ),
      ),
      // ── References ──
      DocPage(
        runningHead: const SizedBox.shrink(),
        content: bibliographyPage(f, sources, style),
      ),
    ];
  }
}

/// MLA 9: no title page — a top-left heading block then the centred title, all
/// on the first page. (Abstract has no MLA home, so it's parked, not shown.)
class MlaSpec extends FormatSpec {
  const MlaSpec();

  @override
  List<DocPage> buildPages(
    BuildContext context,
    EditorFields f, {
    required Widget body,
    required List<Source> sources,
    required FormatStyle style,
  }) {
    return [
      DocPage(
        runningHead: null, // MLA head is the page-number line (author + n)
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            f.field(DocFieldKind.studentName, align: TextAlign.left),
            f.field(DocFieldKind.instructorName, align: TextAlign.left),
            f.field(DocFieldKind.courseName, align: TextAlign.left),
            f.field(DocFieldKind.date, align: TextAlign.left),
            const SizedBox(height: 4),
            f.editable(f.title, hint: 'Untitled Paper', align: TextAlign.center),
            const SizedBox(height: 8),
            body,
          ],
        ),
      ),
      // ── Works Cited ──
      DocPage(
        runningHead: null,
        content: bibliographyPage(f, sources, style),
      ),
    ];
  }
}

/// Chicago / Turabian 9: a title page (title ~⅓ down, block ~⅔ down, no page
/// number), body, then a bold "Bibliography" (hanging, alphabetized).
class ChicagoSpec extends FormatSpec {
  const ChicagoSpec();

  @override
  List<DocPage> buildPages(
    BuildContext context,
    EditorFields f, {
    required Widget body,
    required List<Source> sources,
    required FormatStyle style,
  }) {
    return [
      DocPage(
        showPageNumber: false,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            spacer(6),
            f.editable(f.title, hint: 'Untitled Paper', align: TextAlign.center),
            spacer(5),
            f.field(DocFieldKind.studentName),
            f.field(DocFieldKind.courseName),
            f.field(DocFieldKind.instructorName),
            f.field(DocFieldKind.date),
          ],
        ),
      ),
      DocPage(runningHead: const SizedBox.shrink(), content: body),
      DocPage(
        runningHead: const SizedBox.shrink(),
        content: bibliographyPage(f, sources, style),
      ),
    ];
  }
}

/// IEEE: a centred title + author block, ungapped body (no first-line indent,
/// 10pt, single-ish spacing, no page numbers), then numbered "References".
class IeeeSpec extends FormatSpec {
  const IeeeSpec();

  @override
  FormatProfile get profile =>
      const FormatProfile(fontSize: 13.3, lineHeight: 1.15, firstLineIndent: 0);

  @override
  List<DocPage> buildPages(
    BuildContext context,
    EditorFields f, {
    required Widget body,
    required List<Source> sources,
    required FormatStyle style,
  }) {
    return [
      DocPage(
        showPageNumber: false,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            f.editable(f.title,
                hint: 'Untitled Paper',
                align: TextAlign.center,
                style: f.baseStyle.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            f.field(DocFieldKind.studentName),
            f.field(DocFieldKind.institutionName),
            f.field(DocFieldKind.date),
            const SizedBox(height: 12),
            body,
          ],
        ),
      ),
      DocPage(
        showPageNumber: false,
        content: bibliographyPage(f, sources, style),
      ),
    ];
  }
}

/// Harvard: a centred title page, a body that repeats the title, then an
/// alphabetized "Reference List" (hanging indent). 1.5 line spacing.
class HarvardSpec extends FormatSpec {
  const HarvardSpec();

  @override
  FormatProfile get profile =>
      const FormatProfile(fontSize: 16, lineHeight: 1.5, firstLineIndent: 48);

  @override
  List<DocPage> buildPages(
    BuildContext context,
    EditorFields f, {
    required Widget body,
    required List<Source> sources,
    required FormatStyle style,
  }) {
    final titleText =
        f.title.text.trim().isEmpty ? 'Untitled Paper' : f.title.text.trim();
    return [
      DocPage(
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            spacer(5),
            f.editable(f.title,
                hint: 'Untitled Paper',
                align: TextAlign.center,
                style: f.baseStyle.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            f.field(DocFieldKind.studentName),
            f.field(DocFieldKind.institutionName),
            f.field(DocFieldKind.courseName),
            f.field(DocFieldKind.instructorName),
            f.field(DocFieldKind.date),
          ],
        ),
      ),
      DocPage(
        runningHead: const SizedBox.shrink(),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              titleText,
              textAlign: TextAlign.center,
              style: f.baseStyle.copyWith(fontWeight: FontWeight.bold),
            ),
            body,
          ],
        ),
      ),
      DocPage(
        runningHead: const SizedBox.shrink(),
        content: bibliographyPage(f, sources, style),
      ),
    ];
  }
}
