import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../data/gw_api.dart';

/// Where the editor's copy stands against the server's.
enum SaveState {
  /// Nothing to save.
  saved,

  /// Edited; a save is coming.
  dirty,
  saving,

  /// The last save failed (offline); it is retried.
  failed,

  /// The document changed elsewhere since this copy was loaded. Saving stops
  /// until the user reloads.
  conflict,
}

/// The title-page fields, in the order the editor shows them. The keys are
/// the ones the agent stores (and Doc Oct's `DocFieldKind` names).
const kDocFields = <(String, String)>[
  ('studentName', 'Student name'),
  ('instructorName', 'Instructor'),
  ('courseName', 'Course'),
  ('institutionName', 'Institution'),
  ('date', 'Date'),
];

/// An open document: follows the document stream (CONTRACT.md 7.1), shows
/// the agent's text as it is written, and once the document is unlocked
/// saves the user's edits on its own (7.2).
///
/// The body is a quill document. The server also keeps it as plain text,
/// paragraphs separated by a blank line, which is what the agent writes.
class GwDocumentSession extends ChangeNotifier {
  GwDocumentSession(
    this.api,
    this.projectId, {
    this.autosaveDelay = const Duration(milliseconds: 1200),
    this.retryDelay = const Duration(seconds: 3),
  }) {
    for (final (key, _) in kDocFields) {
      fields[key] = TextEditingController()..addListener(_edited);
    }
    title.addListener(_edited);
    bibliography.addListener(_edited);
    _watchBody();
    _connect();
  }

  final GwApi api;
  final String projectId;
  final Duration autosaveDelay;
  final Duration retryDelay;

  final QuillController body = QuillController.basic();
  final TextEditingController title = TextEditingController();
  final TextEditingController bibliography = TextEditingController();
  final Map<String, TextEditingController> fields = {};

  bool loaded = false;

  /// The agent is writing: everything is read-only.
  bool locked = false;

  /// The live stream is down (being retried).
  bool offline = false;

  String style = 'apa';
  int wordCount = 0;
  SaveState saveState = SaveState.saved;

  /// The `rev` this copy is based on.
  int rev = 0;

  /// Set when the agent took the document back while there were unsaved
  /// edits, which are then lost; shown once.
  String? notice;

  StreamSubscription<Map<String, dynamic>>? _stream;
  StreamSubscription<DocChange>? _bodyChanges;
  Timer? _autosave;
  Timer? _reconnect;

  /// True while the session itself changes the text (a snapshot, a delta),
  /// so that is not taken for an edit.
  bool _applying = false;

  /// Edits made while a save was in flight.
  bool _editedDuringSave = false;
  bool _disposed = false;

  bool get editable => loaded && !locked;

  // ── The stream ───────────────────────────────────────────────────────────

  void _connect() {
    _reconnect?.cancel();
    unawaited(_stream?.cancel());
    _stream = api
        .documentEvents(projectId)
        .listen(_onEvent, onError: (_) => _lost(), onDone: _lost);
  }

  void _lost() {
    if (_disposed) return;
    offline = true;
    _notify();
    _reconnect = Timer(retryDelay, _connect);
  }

  void _onEvent(Map<String, dynamic> event) {
    if (offline) offline = false;
    switch (event['type']) {
      case 'snapshot':
        _onSnapshot(event);
      case 'delta':
        _appendText(event['text']?.toString() ?? '');
        wordCount = countWords(body.document.toPlainText());
      case 'committed':
        if (locked) rev = _int(event['rev']) ?? rev;
      case 'unlocked':
        locked = false;
    }
    _notify();
  }

  void _onSnapshot(Map<String, dynamic> doc) {
    final snapshotRev = _int(doc['rev']) ?? 0;
    final snapshotLocked = doc['locked'] == true;
    final dirty =
        saveState == SaveState.dirty ||
        saveState == SaveState.saving ||
        saveState == SaveState.failed;

    if (loaded && !snapshotLocked) {
      // A save is in flight: its reply settles where we stand, and if
      // someone else saved first it is refused as stale.
      if (saveState == SaveState.saving) return;
      // Our own save coming back, or nothing new.
      if (snapshotRev <= rev && !locked) return;
      // Changed elsewhere while this copy has edits: keep them, and let the
      // user choose (the next save would be refused anyway).
      if (dirty) {
        saveState = SaveState.conflict;
        return;
      }
    }
    if (snapshotLocked && dirty) {
      notice =
          'GhostWriter started writing, so your last few unsaved edits '
          'were not kept.';
    }
    _apply(doc);
  }

  /// Replaces the whole copy with [doc] (a snapshot or a GET).
  void _apply(Map<String, dynamic> doc) {
    _autosave?.cancel();
    _applying = true;
    try {
      rev = _int(doc['rev']) ?? 0;
      locked = doc['locked'] == true;
      style = doc['style']?.toString() ?? style;
      _set(title, doc['title']?.toString() ?? '');
      _set(bibliography, doc['bibliography']?.toString() ?? '');
      final values = doc['fields'];
      for (final (key, _) in kDocFields) {
        _set(fields[key]!, values is Map ? values[key]?.toString() ?? '' : '');
      }
      body.document = documentFrom(doc['body']?.toString() ?? '', doc['delta']);
      body.readOnly = locked;
      _watchBody();
    } finally {
      _applying = false;
    }
    wordCount = countWords(body.document.toPlainText());
    loaded = true;
    saveState = SaveState.saved;
    _editedDuringSave = false;
  }

  void _set(TextEditingController c, String text) {
    if (c.text != text) c.text = text;
  }

  /// The agent's next piece of text, at the end of the body.
  void _appendText(String text) {
    // The agent separates paragraphs with a blank line; the editor keeps one
    // paragraph per line. A blank line may be split across two pieces.
    final plain = body.document.toPlainText();
    final atLineStart = plain.length < 2 || plain[plain.length - 2] == '\n';
    var piece = text.replaceAll(RegExp(r'\n\s*\n'), '\n');
    if (atLineStart) piece = piece.replaceFirst(RegExp(r'^\s+'), '');
    if (piece.isEmpty) return;
    _applying = true;
    try {
      final end = body.document.length - 1;
      body.compose(
        Delta()
          ..retain(end)
          ..insert(piece),
        body.selection,
        ChangeSource.remote,
      );
    } finally {
      _applying = false;
    }
  }

  void _watchBody() {
    unawaited(_bodyChanges?.cancel());
    _bodyChanges = body.document.changes.listen((change) {
      if (change.source == ChangeSource.local) _edited();
    });
  }

  // ── Saving ───────────────────────────────────────────────────────────────

  void _edited() {
    if (_applying || !loaded || locked || _disposed) return;
    if (saveState == SaveState.conflict) return;
    wordCount = countWords(body.document.toPlainText());
    if (saveState == SaveState.saving) {
      _editedDuringSave = true;
    } else {
      saveState = SaveState.dirty;
      _autosave?.cancel();
      _autosave = Timer(autosaveDelay, save);
    }
    _notify();
  }

  /// What a save sends: everything the editor can change.
  Map<String, dynamic> _payload() => {
    'baseRev': rev,
    'title': title.text,
    'fields': {
      for (final (key, _) in kDocFields)
        if (fields[key]!.text.trim().isNotEmpty) key: fields[key]!.text.trim(),
    },
    'body': bodyText(body.document),
    'delta': body.document.toDelta().toJson(),
    'bibliography': bibliography.text,
  };

  /// Saves now if there is anything to save. Safe to call at any time.
  Future<void> save() async {
    _autosave?.cancel();
    if (_disposed ||
        locked ||
        saveState == SaveState.saving ||
        saveState == SaveState.saved ||
        saveState == SaveState.conflict) {
      return;
    }
    saveState = SaveState.saving;
    _editedDuringSave = false;
    _notify();
    try {
      final saved = await api.saveDocument(projectId, _payload());
      rev = _int(saved['rev']) ?? rev;
      wordCount = _int(saved['wordCount']) ?? wordCount;
      saveState = SaveState.saved;
      if (_editedDuringSave) {
        saveState = SaveState.dirty;
        _autosave = Timer(autosaveDelay, save);
      }
    } on GwApiException catch (e) {
      if (e.code == 'stale_rev') {
        saveState = SaveState.conflict;
      } else if (e.code == 'document_locked') {
        // The agent has it; the stream brings its snapshot.
        locked = true;
        body.readOnly = true;
        saveState = SaveState.dirty;
      } else {
        _failed();
      }
    } catch (_) {
      _failed();
    }
    _notify();
  }

  void _failed() {
    saveState = SaveState.failed;
    _autosave = Timer(retryDelay, () {
      if (saveState == SaveState.failed) {
        saveState = SaveState.dirty;
        save();
      }
    });
  }

  /// Drops this copy's edits and loads the server's.
  Future<void> reload() async {
    final doc = await api.document(projectId);
    _apply(doc);
    _notify();
  }

  // ── Versions ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> versions() async {
    final data = await api.versions(projectId);
    return [
      for (final v in data['versions'] as List? ?? const [])
        if (v is Map<String, dynamic>) v,
    ];
  }

  /// Puts [versionId] back. Unsaved edits are dropped; what is replaced is
  /// kept as a version on the server.
  Future<void> restore(String versionId) async {
    final doc = await api.restoreVersion(projectId, versionId);
    _apply(doc);
    _notify();
  }

  void clearNotice() {
    notice = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    // Last chance for pending edits.
    if (saveState == SaveState.dirty) unawaited(save());
    _disposed = true;
    _autosave?.cancel();
    _reconnect?.cancel();
    unawaited(_stream?.cancel());
    unawaited(_bodyChanges?.cancel());
    body.dispose();
    title.dispose();
    bibliography.dispose();
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }
}

/// A quill document for a saved body: the rich [delta] when there is one,
/// else the plain text, one paragraph per line.
Document documentFrom(String body, Object? delta) {
  if (delta is List && delta.isNotEmpty) {
    try {
      return Document.fromJson(delta);
    } catch (_) {
      // A delta we cannot read: fall back to the text.
    }
  }
  final paragraphs = body
      .split(RegExp(r'\n\s*\n'))
      .map((p) => p.trim().replaceAll('\n', ' '))
      .where((p) => p.isNotEmpty);
  final text = paragraphs.join('\n');
  return Document.fromDelta(Delta()..insert(text.isEmpty ? '\n' : '$text\n'));
}

/// The body as the server keeps it: paragraphs separated by a blank line.
String bodyText(Document document) => document
    .toPlainText()
    .split('\n')
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .join('\n\n');

int countWords(String text) =>
    text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v');
