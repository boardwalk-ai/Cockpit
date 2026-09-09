import 'package:flutter/material.dart';

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
  /// abstract).
  List<DocPage> buildPages(BuildContext context, EditorFields f,
      {required Widget body});
}

/// Shared paper metrics + a couple of helpers.
extension _Paper on FormatSpec {
  Widget runningHeadPlaceholder(BuildContext context, String text) => Text(
        text,
        style: TextStyle(
          fontFamily: 'Times New Roman',
          fontFamilyFallback: const ['Georgia', 'serif'],
          fontSize: 13,
          color: const Color(0xFF9AA0AA),
        ),
      );
}

/// APA 7 (student paper): a centred title page, then an Abstract page.
class ApaSpec extends FormatSpec {
  const ApaSpec();

  @override
  List<DocPage> buildPages(BuildContext context, EditorFields f,
      {required Widget body}) {
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
      // ── Body page ──
      DocPage(runningHead: const SizedBox.shrink(), content: body),
    ];
  }
}

/// MLA 9: no title page — a top-left heading block then the centred title, all
/// on the first page. (Abstract has no MLA home, so it's parked, not shown.)
class MlaSpec extends FormatSpec {
  const MlaSpec();

  @override
  List<DocPage> buildPages(BuildContext context, EditorFields f,
      {required Widget body}) {
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
    ];
  }
}
