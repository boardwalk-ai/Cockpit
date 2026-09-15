import 'package:flutter/material.dart';

import '../../domain/citation_templates.dart';
import '../../domain/source.dart';
import '../../theme/doc_tokens.dart';
import 'doc_model.dart';

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
  const DocPage({required this.content, this.runningHead});
  final Widget content;

  /// Left side of the running-head line (right side is always the page number).
  final Widget? runningHead;
}

/// Projects the semantic fields into paginated pages for one citation style.
/// Presentation-level for now; the print/PDF spec shares the same idea.
abstract class FormatSpec {
  const FormatSpec();

  factory FormatSpec.of(FormatStyle style) => switch (style) {
        FormatStyle.apa => const ApaSpec(),
        FormatStyle.mla => const MlaSpec(),
        // Chicago/IEEE/Harvard fall back to the MLA-shaped layout for now
        // (their own specs land as we build each out).
        _ => const MlaSpec(),
      };

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          meta.heading,
          textAlign: TextAlign.center,
          style: f.baseStyle
              .copyWith(fontWeight: meta.bold ? FontWeight.bold : FontWeight.normal),
        ),
        for (var i = 0; i < entries.length; i++)
          Text(
            CitationTemplates.reference(style, entries[i], i + 1),
            style: f.baseStyle,
          ),
      ],
    );
  }

  ({String heading, bool bold, bool numbered}) _bibMeta(FormatStyle s) =>
      switch (s) {
        FormatStyle.mla => (heading: 'Works Cited', bold: false, numbered: false),
        FormatStyle.apa => (heading: 'References', bold: true, numbered: false),
        FormatStyle.chicago =>
          (heading: 'Bibliography', bold: true, numbered: false),
        FormatStyle.ieee => (heading: 'References', bold: true, numbered: true),
        FormatStyle.harvard => (heading: 'References', bold: true, numbered: false),
      };
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
