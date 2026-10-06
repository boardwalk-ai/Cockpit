import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../domain/entities/studio.dart';
import '../../domain/entities/topic.dart';

/// A safe file name from a studio's title.
String exportName(Studio s) {
  final base = s.title
      .replaceAll(RegExp(r'[^\w\s-]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '-');
  return base.isEmpty ? 'study-studio' : base;
}

/// The flashcards as a tab-separated file Anki imports (front, back, tag).
String ankiTsv(Studio s) {
  String cell(String v) => v.replaceAll(RegExp(r'[\t\r\n]+'), ' ').trim();
  final tag = exportName(s);
  final out = StringBuffer()
    ..writeln('#separator:tab')
    ..writeln('#html:false')
    ..writeln('#tags column:3');
  for (final t in s.topics) {
    final topicTag = '$tag::${t.title.replaceAll(RegExp(r'\s+'), '_')}';
    for (final c in t.flashcards) {
      if (c.front.trim().isEmpty) continue;
      out.writeln('${cell(c.front)}\t${cell(c.back)}\t${cell(topicTag)}');
    }
  }
  return out.toString();
}

int ankiCount(Studio s) => s.topics.fold(
  0,
  (n, t) => n + t.flashcards.where((c) => c.front.trim().isNotEmpty).length,
);

/// The studio as study notes: each topic's summary, key ideas, examples,
/// mistakes to avoid, and its cards to test yourself with.
Future<Uint8List> studyNotesPdf(Studio s, {DateTime? now}) async {
  Future<pw.Font> font(String file) async => pw.Font.ttf(
    await rootBundle.load('packages/cockpit_ui/assets/fonts/$file'),
  );
  final body = await font('Poppins-Regular.ttf');
  final medium = await font('Poppins-Medium.ttf');
  final head = await font('PlusJakartaSans-Bold.ttf');
  const accent = PdfColor.fromInt(0xFFC40C1A);
  const muted = PdfColor.fromInt(0xFF6B6B66);
  const line = PdfColor.fromInt(0xFFE0DDD6);

  final doc = pw.Document(
    title: s.title,
    creator: 'Octopilot Study Studio',
    theme: pw.ThemeData.withFont(base: body, bold: medium),
  );
  pw.Widget label(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
    child: pw.Text(
      text.toUpperCase(),
      style: pw.TextStyle(
        font: head,
        fontSize: 8,
        letterSpacing: 1.2,
        color: muted,
      ),
    ),
  );
  pw.Widget bullet(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 3.5,
          height: 3.5,
          margin: const pw.EdgeInsets.only(top: 5, right: 7),
          decoration: const pw.BoxDecoration(
            color: accent,
            shape: pw.BoxShape.circle,
          ),
        ),
        pw.Expanded(
          child: pw.Text(text, style: const pw.TextStyle(fontSize: 10.5)),
        ),
      ],
    ),
  );

  List<pw.Widget> topic(int i, Topic t) {
    final points = t.summary.where((p) => p.trim().isNotEmpty).toList();
    return [
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 18),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              '${i + 1}'.padLeft(2, '0'),
              style: pw.TextStyle(font: head, fontSize: 11, color: accent),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: pw.Text(
                t.title,
                style: pw.TextStyle(font: head, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
      pw.Divider(color: line, thickness: 0.6),
      if (points.isNotEmpty) ...[
        label('Summary'),
        for (final p in points) bullet(p.trim()),
      ] else if (t.definition.trim().isNotEmpty)
        pw.Text(t.definition.trim(), style: const pw.TextStyle(fontSize: 10.5)),
      if (t.concepts.isNotEmpty) ...[
        label('Key ideas'),
        for (final c in t.concepts)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.RichText(
              text: pw.TextSpan(
                style: const pw.TextStyle(fontSize: 10.5),
                children: [
                  pw.TextSpan(
                    text: c.name,
                    style: pw.TextStyle(font: medium),
                  ),
                  if (c.meaning.trim().isNotEmpty)
                    pw.TextSpan(text: ' — ${c.meaning.trim()}'),
                ],
              ),
            ),
          ),
      ],
      if (t.examples.isNotEmpty) ...[
        label('Examples'),
        for (final e in t.examples.take(3)) bullet(e),
      ],
      if (t.commonMistakes.isNotEmpty) ...[
        label('Watch out for'),
        for (final m in t.commonMistakes.take(3)) bullet(m),
      ],
      if (t.flashcards.isNotEmpty) ...[
        label('Test yourself'),
        for (final c in t.flashcards.take(8))
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 4),
            padding: const pw.EdgeInsets.fromLTRB(8, 5, 8, 5),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: line, width: 0.6),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(c.front, style: pw.TextStyle(font: medium, fontSize: 10)),
                pw.SizedBox(height: 2),
                pw.Text(
                  c.back,
                  style: const pw.TextStyle(fontSize: 9.5, color: muted),
                ),
              ],
            ),
          ),
      ],
    ];
  }

  final date = now ?? DateTime.now();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(48, 44, 48, 44),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            s.title,
            style: const pw.TextStyle(fontSize: 8, color: muted),
          ),
          pw.Text(
            '${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: muted),
          ),
        ],
      ),
      build: (context) => [
        pw.Text(
          'STUDY NOTES',
          style: pw.TextStyle(
            font: head,
            fontSize: 9,
            letterSpacing: 2,
            color: accent,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text(s.title, style: pw.TextStyle(font: head, fontSize: 28)),
        pw.SizedBox(height: 4),
        pw.Text(
          '${s.topics.length} topics · ${date.year}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')} · Octopilot Study Studio',
          style: const pw.TextStyle(fontSize: 10, color: muted),
        ),
        for (final (i, t) in s.topics.indexed) ...topic(i, t),
      ],
    ),
  );
  return doc.save();
}

/// Hands a file to the phone's share sheet.
Future<void> shareFile(
  Uint8List bytes, {
  required String name,
  required String mime,
  String? subject,
}) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, mimeType: mime, name: name)],
      fileNameOverrides: [name],
      subject: subject,
    ),
  );
}

Uint8List utf8Bytes(String s) => Uint8List.fromList(utf8.encode(s));
