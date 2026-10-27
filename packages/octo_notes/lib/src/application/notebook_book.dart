import 'dart:ui' show Color;

import '../data/api/octo_notes_api.dart';
import '../domain/notes_session.dart';

/// One thing on a notebook page, in the order it was written.
class BookItem {
  const BookItem({
    required this.id,
    required this.kind,
    this.text = '',
    this.checked = false,
    this.atMs,
    this.materialId,
  });

  final String id;

  /// heading · text · bullet · check · quote · pen · formula · photo
  final String kind;
  final String text;
  final bool checked;

  /// When in the lecture it was written (for "follow along"); never shown.
  final int? atMs;

  /// A board photo's material.
  final String? materialId;
}

/// A lecture as a chapter of its notebook.
class BookChapter {
  BookChapter({required this.session, required this.mine, this.clean, this.finalNotesId, this.recordingId, this.durationMs = 0, this.slides = const []});

  final NotesSession session;
  final List<BookItem> mine;

  /// The finalized notes, when there are some.
  final List<BookItem>? clean;
  final String? finalNotesId;

  /// The lecture's recording (joined), if any.
  final String? recordingId;
  final int durationMs;

  /// Slides and documents brought to the lecture: (material id, file name).
  final List<(String, String)> slides;

  bool get finalized => clean != null;

  /// The headings, for the contents page.
  List<String> get headings => [for (final i in mine) if (i.kind == 'heading') i.text];
}

/// A file of the notebook, for the Files view.
class BookFile {
  const BookFile({required this.kind, required this.title, required this.chapter, this.detail = '', this.recordingId, this.materialId, this.item});

  /// text · clean · recording · photo · handwriting · formula · slide
  final String kind;
  final String title;
  final String detail;
  final int chapter;
  final String? recordingId;
  final String? materialId;

  /// The page item it is (handwriting, formula, photo).
  final BookItem? item;
}

class NotebookBook {
  NotebookBook({required this.title, this.code, this.color, required this.chapters, required this.files});
  final String title;
  final String? code;
  final Color? color;
  final List<BookChapter> chapters;
  final List<BookFile> files;
}

/// The notebook's lectures in order, each with what was written in it.
/// [courseId] null with [looseOnly] means lectures without a notebook.
Future<NotebookBook> loadNotebook(OctoNotesApi api, {String? courseId, bool looseOnly = false, Color Function(String?, int)? colorOf}) async {
  final r = await Future.wait([api.courses(), api.sessions(courseId: courseId, limit: 100)]);
  final courses = (r[0] as List).cast<Map<String, dynamic>>();
  final i = courses.indexWhere((c) => c['id'] == courseId);
  final course = i < 0 ? null : courses[i];
  var sessions = (r[1] as SessionPage).items;
  if (courseId == null && looseOnly) sessions = [for (final s in sessions) if (s.courseId == null) s];
  sessions.sort((a, b) => (a.startedAt ?? a.updatedAt).compareTo(b.startedAt ?? b.updatedAt));
  final chapters = await Future.wait(sessions.map((s) => _chapter(api, s)));
  return NotebookBook(
    title: course?['name'] as String? ?? 'Loose pages',
    code: course?['code'] as String?,
    color: colorOf?.call(course?['color'] as String?, i < 0 ? 0 : i),
    chapters: chapters,
    files: _files(chapters),
  );
}

Future<T> _or<T>(Future<T> f, T fallback) => f.catchError((Object _) => fallback);

Future<BookChapter> _chapter(OctoNotesApi api, NotesSession s) async {
  final r = await Future.wait([
    _or(api.blocks(s.id), const <String, dynamic>{}),
    _or(api.inkPages(s.id), const <String, dynamic>{}),
    _or(api.recordings(s.id), const <dynamic>[]),
    _or(api.materials(s.id), const <dynamic>[]),
    _or(api.finalNotesOf(s.id), const <dynamic>[]),
  ]);
  final start = s.startedAt;
  int? since(String? at) {
    final t = DateTime.tryParse(at ?? '');
    if (t == null || start == null) return null;
    final ms = t.difference(start).inMilliseconds;
    return ms < 0 ? 0 : ms;
  }

  // Typed lines, in their order on the page.
  final blocks = [
    for (final b in ((r[0] as Map)['blocks'] as List? ?? const []).cast<Map<String, dynamic>>())
      if (b['deletedAt'] == null) ?_item(b),
  ];

  // Handwriting read on the phone, formulas, board photos: placed by when.
  final extras = <BookItem>[];
  final pages = ((r[1] as Map)['pages'] as List? ?? const []).cast<Map<String, dynamic>>();
  final lines = await Future.wait(pages.map((p) => _or(api.inkRecognitions(p['id'] as String), const <String, dynamic>{})));
  for (final l in lines) {
    for (final x in (l['items'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      final text = (x['text'] as String? ?? '').trim();
      if (text.isEmpty) continue;
      final formula = text.length > 4 && text.startsWith(r'$$') && text.endsWith(r'$$');
      extras.add(BookItem(
        id: 'r${x['id']}',
        kind: formula ? 'formula' : 'pen',
        text: formula ? text.substring(2, text.length - 2) : text,
        atMs: since(x['createdAt'] as String?),
      ));
    }
  }
  final materials = (r[3] as List).cast<Map<String, dynamic>>();
  for (final m in materials) {
    if (m['kind'] == 'whiteboardPhoto') {
      extras.add(BookItem(id: 'm${m['id']}', kind: 'photo', materialId: m['id'] as String, atMs: since(m['createdAt'] as String?), text: 'Board photo'));
    }
  }
  extras.sort((a, b) => (a.atMs ?? 1 << 40).compareTo(b.atMs ?? 1 << 40));

  final recs = (r[2] as List).cast<Map<String, dynamic>>().where((x) => x['state'] == 'assembled').toList()
    ..sort((a, b) => ((b['durationMs'] as num?) ?? 0).compareTo((a['durationMs'] as num?) ?? 0));
  final rec = recs.firstOrNull;

  List<BookItem>? clean;
  String? finalId;
  final finals = (r[4] as List).cast<Map<String, dynamic>>();
  if (finals.isNotEmpty) {
    finalId = finals.first['id'] as String?;
    try {
      final f = await api.finalNotes(finalId!);
      clean = [
        for (final b in (((f['content'] as Map?)?['blocks'] as List?) ?? const []).cast<Map<String, dynamic>>()) ?_item(b),
      ];
    } on Object {
      clean = null;
    }
  }

  return BookChapter(
    session: s,
    mine: merge(blocks, extras),
    clean: clean,
    finalNotesId: finalId,
    recordingId: rec?['id'] as String?,
    durationMs: (rec?['durationMs'] as num?)?.toInt() ?? s.durationMs,
    slides: [
      for (final m in materials)
        if (m['kind'] != 'whiteboardPhoto') (m['id'] as String, m['filename'] as String? ?? 'File'),
    ],
  );
}

/// Typed lines keep their order; each extra goes in before the first line
/// written after it.
List<BookItem> merge(List<BookItem> lines, List<BookItem> extras) {
  final out = <BookItem>[];
  var e = 0;
  for (final b in lines) {
    while (e < extras.length && b.atMs != null && extras[e].atMs != null && extras[e].atMs! < b.atMs!) {
      out.add(extras[e++]);
    }
    out.add(b);
  }
  return out..addAll(extras.skip(e));
}

BookItem? _item(Map<String, dynamic> b) {
  final text = (b['text'] as String? ?? '').trim();
  final type = b['type'] as String? ?? 'paragraph';
  if (text.isEmpty) return null;
  final kind = switch (type) {
    'h1' || 'h2' || 'h3' || 'heading' => 'heading',
    'bulleted' || 'numbered' => 'bullet',
    'checklist' => 'check',
    'quote' || 'transcriptExcerpt' => 'quote',
    _ => 'text',
  };
  final at = (b['audioTsMs'] ?? (b['provenance'] as Map?)?['audioTsMs']) as num?;
  return BookItem(id: '${b['id'] ?? text.hashCode}', kind: kind, text: text, checked: b['checked'] == true, atMs: at?.toInt());
}

String _date(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${m[d.month - 1]} ${d.day}';
}

/// A chapter's date as shown ("Oct 20").
String chapterDate(BookChapter c) => _date((c.session.startedAt ?? c.session.updatedAt).toLocal());

String minutes(int ms) => '${(ms / 60000).round()} min';

List<BookFile> _files(List<BookChapter> chapters) => [
      for (var i = 0; i < chapters.length; i++) ...[
        if (chapters[i].mine.any((x) => x.kind != 'photo'))
          BookFile(kind: 'text', title: '${chapters[i].session.title} — notes', chapter: i, detail: '${chapterDate(chapters[i])} · ${chapters[i].mine.where((x) => x.kind != 'photo').length} lines'),
        if (chapters[i].finalized)
          BookFile(kind: 'clean', title: '${chapters[i].session.title} — clean copy', chapter: i, detail: '${chapterDate(chapters[i])} · finalized'),
        if (chapters[i].recordingId != null)
          BookFile(kind: 'recording', title: chapters[i].session.title, chapter: i, recordingId: chapters[i].recordingId, detail: '${chapterDate(chapters[i])} · ${minutes(chapters[i].durationMs)}'),
        for (final x in chapters[i].mine)
          if (x.kind == 'photo')
            BookFile(kind: 'photo', title: 'Board photo', chapter: i, materialId: x.materialId, item: x, detail: chapterDate(chapters[i]))
          else if (x.kind == 'pen')
            BookFile(kind: 'handwriting', title: x.text, chapter: i, item: x, detail: '${chapterDate(chapters[i])} · Magic Pencil')
          else if (x.kind == 'formula')
            BookFile(kind: 'formula', title: x.text, chapter: i, item: x, detail: '${chapterDate(chapters[i])} · formula'),
        for (final (id, name) in chapters[i].slides)
          BookFile(kind: 'slide', title: name, chapter: i, materialId: id, detail: chapterDate(chapters[i])),
      ],
    ];
