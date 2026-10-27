import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart' as mlkit;

import '../data/api/octo_notes_api.dart';
import '../domain/ink_controller.dart';
import '../domain/ink_models.dart';

/// Reads a line of handwriting; null when there's nothing to read.
typedef InkReader = Future<({String text, double confidence})?> Function(List<Stroke> strokes);

/// A line of handwriting as text, kept with the strokes it came from.
class InkLine {
  InkLine({required this.text, required this.strokeIds, required this.at, this.id});
  final String text;
  final List<String> strokeIds;
  final DateTime at;
  String? id;
}

/// Magic Pencil with the server: loads the session's pages and strokes, then
/// sends every change (add, move or recolour, erase, new page). It watches
/// [InkController] and sends what differs from what the server has, so
/// undo, lasso and eraser need nothing of their own.
///
/// It also reads each line: about a second after the pen stops, the new pen
/// strokes are read on the device and the text is kept with the page.
class InkSync extends ChangeNotifier {
  InkSync({
    required this.api,
    required this.sessionId,
    required this.ink,
    required this.read,
    this.deviceId,
    this.pause = const Duration(milliseconds: 1200),
  }) {
    ink.live = true;
    ink.addListener(_changed);
  }

  final OctoNotesApi? api;
  final String sessionId;
  final InkController ink;
  final InkReader read;
  final String? deviceId;
  final Duration pause;

  /// Lines read, per page.
  final Map<String, List<InkLine>> lines = {};

  /// Reading a line right now.
  bool reading = false;

  // What the server has: stroke (as last sent) and its revision, per local id.
  final Map<String, Stroke> _sent = {};
  final Map<String, int> _rev = {};
  final Set<String> _pages = {};
  // A stroke erased then brought back by undo returns under a new id.
  final Map<String, String> _alias = {};
  final Set<String> _erased = {};
  // Strokes already read, or there before this visit.
  final Set<String> _seen = {};
  Timer? _flushTimer;
  Timer? _readTimer;
  bool _flushing = false;
  bool _disposed = false;

  String _server(String id) => _alias[id] ?? id;

  /// Lines on the page still backed by ink (erased ink takes its text away).
  List<InkLine> linesOf(InkPage p) {
    final live = {for (final s in p.strokes) s.id};
    return [for (final l in lines[p.id] ?? const <InkLine>[]) if (l.strokeIds.any(live.contains)) l];
  }

  Future<void> load() async {
    final a = api;
    if (a == null) return;
    final res = await a.inkPages(sessionId);
    final raw = [...(res['pages'] as List? ?? const []).cast<Map<String, dynamic>>()]
      ..sort((x, y) => ((x['ordinal'] as num?) ?? 0).compareTo((y['ordinal'] as num?) ?? 0));
    final pages = <InkPage>[];
    for (var i = 0; i < raw.length; i++) {
      final id = raw[i]['id'] as String;
      final strokes = await a.inkStrokes(id);
      final page = InkPage(id: id, title: 'Page ${i + 1}', background: PaperBackground.blank);
      for (final j in (strokes['strokes'] as List? ?? const []).cast<Map<String, dynamic>>()) {
        if (j['deletedAt'] != null) continue;
        final s = strokeFromJson(j, id);
        if (s == null) continue;
        page.strokes.add(s);
        _sent[s.id] = s;
        _rev[s.id] = (j['revision'] as num?)?.toInt() ?? 1;
        _seen.add(s.id);
      }
      _pages.add(id);
      pages.add(page);
      try {
        final r = await a.inkRecognitions(id);
        lines[id] = [
          for (final x in (r['items'] as List? ?? const []).cast<Map<String, dynamic>>())
            InkLine(
              id: x['id'] as String?,
              text: x['text'] as String? ?? '',
              strokeIds: [...(x['strokeIds'] as List? ?? const []).cast<String>()],
              at: DateTime.tryParse(x['createdAt'] as String? ?? '') ?? DateTime.now(),
            ),
        ];
      } on Object {
        // Old server: no lines yet.
      }
    }
    ink.removeListener(_changed);
    ink.load(pages);
    ink.addListener(_changed);
    // A first visit: the blank page is new to the server.
    _changed();
    notifyListeners();
  }

  void _changed() {
    if (_disposed) return;
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 400), () => unawaited(flush()));
    final pending = _unread();
    _readTimer?.cancel();
    if (pending.isNotEmpty) _readTimer = Timer(pause, () => unawaited(_readLine()));
  }

  List<Stroke> _unread() => [
        for (final s in ink.page.strokes)
          if ((s.tool == InkTool.pen || s.tool == InkTool.pencil) && !_seen.contains(s.id)) s,
      ];

  Future<void> _readLine() async {
    final strokes = _unread();
    if (strokes.isEmpty || _disposed) return;
    final pageId = ink.page.id;
    _seen.addAll(strokes.map((s) => s.id));
    reading = true;
    notifyListeners();
    try {
      final r = await read(strokes);
      final text = r?.text.trim() ?? '';
      if (text.isEmpty || _disposed) return;
      final line = InkLine(text: text, strokeIds: [for (final s in strokes) s.id], at: DateTime.now());
      (lines[pageId] ??= []).add(line);
      notifyListeners();
      final a = api;
      if (a != null) {
        await flush(); // the server needs the strokes first
        final saved = await a.addInkRecognition(pageId, [for (final id in line.strokeIds) _server(id)], text, r!.confidence);
        line.id = saved['id'] as String?;
      }
    } on Object catch (e) {
      debugPrint('ink read: $e');
    } finally {
      reading = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Reads [strokes] as a formula on the server. It replaces any text read
  /// from the same ink. Returns the LaTeX.
  Future<String> readFormula(List<Stroke> strokes) async {
    final a = api;
    if (a == null) throw StateError('Formulas need the OctoNotes server.');
    final pageId = ink.page.id;
    final ids = [for (final s in strokes) s.id];
    _seen.addAll(ids);
    reading = true;
    notifyListeners();
    try {
      await flush(); // the server needs the strokes first
      final r = await a.inkFormula(pageId, [for (final id in ids) _server(id)]);
      lines[pageId]?.removeWhere((l) => l.strokeIds.every(ids.contains));
      (lines[pageId] ??= []).add(InkLine(id: r['id'] as String?, text: r['text'] as String, strokeIds: ids, at: DateTime.now()));
      return r['latex'] as String;
    } finally {
      reading = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Sends what changed since the last send.
  Future<void> flush() async {
    final a = api;
    if (a == null || _flushing || _disposed) return;
    _flushing = true;
    try {
      for (final p in ink.pages) {
        if (!_pages.contains(p.id)) {
          await a.addInkPage(sessionId, id: p.id, background: 'blank');
          _pages.add(p.id);
        }
        final ops = <Map<String, dynamic>>[];
        final here = {for (final s in p.strokes) s.id: s};
        for (final s in p.strokes) {
          final before = _sent[s.id];
          if (identical(before, s) && !_erased.contains(s.id)) continue;
          if (before == null || _erased.contains(s.id)) {
            if (_erased.remove(s.id)) _alias[s.id] = OctoNotesApi.newId();
            ops.add({'clientOpId': OctoNotesApi.newId(), 'op': 'add', 'strokeId': _server(s.id), 'stroke': strokeToJson(s)});
          } else {
            ops.add({
              'clientOpId': OctoNotesApi.newId(),
              'op': 'update',
              'strokeId': _server(s.id),
              'baseRevision': _rev[s.id] ?? 1,
              'stroke': strokeToJson(s),
            });
          }
          _sent[s.id] = s;
        }
        for (final id in [..._sent.keys]) {
          if (_sent[id]!.pageId == p.id && !here.containsKey(id) && !_erased.contains(id)) {
            ops.add({'clientOpId': OctoNotesApi.newId(), 'op': 'erase', 'strokeId': _server(id)});
            _erased.add(id);
          }
        }
        if (ops.isEmpty) continue;
        final res = await a.strokeOps(p.id, ops, deviceId: deviceId);
        for (final r in (res['results'] as List? ?? const []).cast<Map<String, dynamic>>()) {
          final st = r['stroke'] as Map<String, dynamic>?;
          if (st == null) continue;
          final local = _alias.entries.where((e) => e.value == st['id']).firstOrNull?.key ?? st['id'] as String;
          _rev[local] = (st['revision'] as num?)?.toInt() ?? 1;
        }
      }
    } on Object catch (e) {
      // Offline: strokes the server never took go again with the next change.
      // shortcut: a failed move or erase isn't retried; queue ops like
      // BlockSyncEngine if that shows up in use.
      debugPrint('ink sync: $e');
      _sent.removeWhere((id, _) => !_rev.containsKey(id) && !_erased.contains(id));
    } finally {
      _flushing = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _flushTimer?.cancel();
    _readTimer?.cancel();
    ink.removeListener(_changed);
    unawaited(flush()); // the last strokes still go out
    _disposed = true;
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Stroke format v1: [u8 1][u32 count][count × (f32 x, f32 y, f32 pressure)], LE.
// ---------------------------------------------------------------------------

String encodePoints(List<Offset> pts, List<double> pressures) {
  final b = ByteData(5 + pts.length * 12)
    ..setUint8(0, 1)
    ..setUint32(1, pts.length, Endian.little);
  for (var i = 0; i < pts.length; i++) {
    b
      ..setFloat32(5 + i * 12, pts[i].dx, Endian.little)
      ..setFloat32(9 + i * 12, pts[i].dy, Endian.little)
      ..setFloat32(13 + i * 12, i < pressures.length ? pressures[i] : 1, Endian.little);
  }
  return base64Encode(b.buffer.asUint8List());
}

(List<Offset>, List<double>)? decodePoints(String b64) {
  final bytes = base64Decode(b64);
  if (bytes.length < 5 || bytes[0] != 1) return null;
  final d = ByteData.sublistView(bytes);
  final n = d.getUint32(1, Endian.little);
  if (bytes.length != 5 + n * 12) return null;
  return (
    [for (var i = 0; i < n; i++) Offset(d.getFloat32(5 + i * 12, Endian.little), d.getFloat32(9 + i * 12, Endian.little))],
    [for (var i = 0; i < n; i++) d.getFloat32(13 + i * 12, Endian.little)],
  );
}

String _hex(Color c) => '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

Color _color(String? v) {
  final h = v?.replaceFirst('#', '') ?? '';
  final n = int.tryParse(h, radix: 16);
  if (n == null) return const Color(0xFF16213E);
  return Color(h.length == 6 ? 0xFF000000 | n : n);
}

Map<String, dynamic> strokeToJson(Stroke s) => {
      'tool': s.tool.name,
      'points': encodePoints(s.points, s.pressures),
      'color': _hex(s.color),
      'width': s.width,
      'text': ?s.text,
    };

Stroke? strokeFromJson(Map<String, dynamic> j, String pageId) {
  final tool = InkTool.values.where((t) => t.name == j['tool']).firstOrNull;
  final pts = decodePoints(j['points'] as String? ?? '');
  if (tool == null || pts == null) return null;
  return Stroke(
    id: j['id'] as String,
    tool: tool,
    points: pts.$1,
    pressures: pts.$2,
    color: _color(j['color'] as String?),
    width: (j['width'] as num?)?.toDouble() ?? 2,
    pageId: pageId,
    text: j['text'] as String?,
    revision: (j['revision'] as num?)?.toInt() ?? 1,
  );
}

// ---------------------------------------------------------------------------
// On-device reading (Google ML Kit digital ink, English).
// ---------------------------------------------------------------------------

/// Reads English handwriting on the phone. The model (~20 MB) downloads once,
/// the first time it's needed; until then lines wait and are read after.
class DeviceInkReader {
  static const _model = 'en-US';
  final _recognizer = mlkit.DigitalInkRecognizer(languageCode: _model);
  Future<bool>? _ready;

  Future<bool> _ensure() => _ready ??= () async {
        final m = mlkit.DigitalInkRecognizerModelManager();
        if (await m.isModelDownloaded(_model)) return true;
        return m.downloadModel(_model, isWifiRequired: false);
      }();

  Future<({String text, double confidence})?> call(List<Stroke> strokes) async {
    if (strokes.isEmpty) return null;
    if (!await _ensure()) {
      _ready = null; // try the download again next time
      return null;
    }
    final ink = mlkit.Ink();
    // Our points carry no time; a steady 10 ms between them keeps the order.
    var t = DateTime.now().millisecondsSinceEpoch;
    for (final s in strokes) {
      final st = mlkit.Stroke();
      for (final p in s.points) {
        st.points.add(mlkit.StrokePoint(x: p.dx, y: p.dy, t: t += 10));
      }
      ink.strokes.add(st);
    }
    final c = await _recognizer.recognize(ink);
    if (c.isEmpty) return null;
    // ML Kit's score is a cost (lower is better); keep a rough 0..1.
    return (text: c.first.text, confidence: (1 / (1 + c.first.score)).clamp(0.0, 1.0));
  }

  Future<void> close() => _recognizer.close();
}
