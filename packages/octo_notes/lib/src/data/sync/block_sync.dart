import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/octo_notes_api.dart';

/// Where unsent block ops wait (survives app restarts and offline periods).
abstract interface class OpStore {
  Future<List<Map<String, dynamic>>> load(String sessionId);
  Future<void> save(String sessionId, List<Map<String, dynamic>> ops);
}

class MemoryOpStore implements OpStore {
  final Map<String, List<Map<String, dynamic>>> _data = {};
  @override
  Future<List<Map<String, dynamic>>> load(String sessionId) async => [...?_data[sessionId]];
  @override
  Future<void> save(String sessionId, List<Map<String, dynamic>> ops) async => _data[sessionId] = [...ops];
}

/// shared_preferences (localStorage on web, platform prefs on Android/iOS).
class PrefsOpStore implements OpStore {
  static String _key(String s) => 'octonotes.ops.$s';
  @override
  Future<List<Map<String, dynamic>>> load(String sessionId) async {
    final raw = (await SharedPreferences.getInstance()).getString(_key(sessionId));
    if (raw == null) return [];
    return [for (final o in jsonDecode(raw) as List) o as Map<String, dynamic>];
  }

  @override
  Future<void> save(String sessionId, List<Map<String, dynamic>> ops) async {
    final prefs = await SharedPreferences.getInstance();
    if (ops.isEmpty) {
      await prefs.remove(_key(sessionId));
    } else {
      await prefs.setString(_key(sessionId), jsonEncode(ops));
    }
  }
}

/// A server block that conflicted with a local edit. The UI keeps BOTH: the
/// server version stays, and the local text becomes a new sibling block.
@immutable
class BlockConflict {
  const BlockConflict({required this.serverBlock, required this.localOp});
  final Map<String, dynamic> serverBlock;
  final Map<String, dynamic> localOp;
}

enum SyncStatus { saved, saving, offline, conflict, synced }

/// Block-level sync for one session. Every edit is queued locally first
/// (typing never waits on the network), sent in batches about once a
/// second, retried with backoff while offline, and replay-safe: each op has a
/// `clientOpId`, so the server applies it at most once.
class BlockSyncEngine extends ChangeNotifier {
  BlockSyncEngine({
    required this.api,
    required this.sessionId,
    this.deviceId,
    OpStore? store,
    this.flushDelay = const Duration(milliseconds: 900),
  }) : store = store ?? MemoryOpStore();

  final OctoNotesApi api;
  final String sessionId;
  final String? deviceId;
  final OpStore store;
  final Duration flushDelay;

  final List<Map<String, dynamic>> _queue = [];
  final _conflicts = StreamController<BlockConflict>.broadcast();
  final _applied = StreamController<Map<String, dynamic>>.broadcast();
  Timer? _timer;
  bool _flushing = false;
  int _failures = 0;

  /// Latest server revision of the blocks layer seen (for `?sinceRev=`).
  int rev = 0;
  SyncStatus status = SyncStatus.synced;

  Stream<BlockConflict> get conflicts => _conflicts.stream;

  /// Blocks the server confirmed (with their new revision).
  Stream<Map<String, dynamic>> get applied => _applied.stream;
  int get pending => _queue.length;

  /// Reloads ops queued before an app restart.
  Future<void> restore() async {
    _queue.addAll(await store.load(sessionId));
    if (_queue.isNotEmpty) _schedule();
  }

  int _seq = 0;
  String _opId() => '${deviceId ?? 'dev'}-${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  /// Create or edit a block (`baseRevision` 0 for a new block).
  Future<void> upsert(String blockId, Map<String, dynamic> block, {int baseRevision = 0}) =>
      _enqueue({'clientOpId': _opId(), 'op': 'upsert', 'blockId': blockId, 'baseRevision': baseRevision, 'block': block});

  Future<void> move(String blockId, String position, {required int baseRevision, int? indent}) =>
      _enqueue({'clientOpId': _opId(), 'op': 'move', 'blockId': blockId, 'baseRevision': baseRevision, 'position': position, 'indent': ?indent});

  Future<void> delete(String blockId, {required int baseRevision}) =>
      _enqueue({'clientOpId': _opId(), 'op': 'delete', 'blockId': blockId, 'baseRevision': baseRevision});

  Future<void> _enqueue(Map<String, dynamic> op) async {
    // Typing the same block again before a flush: keep only the latest upsert.
    if (op['op'] == 'upsert') {
      final i = _queue.lastIndexWhere((q) => q['op'] == 'upsert' && q['blockId'] == op['blockId']);
      if (i >= 0) {
        final prev = _queue[i];
        op = {...op, 'baseRevision': prev['baseRevision'], 'block': {...prev['block'] as Map, ...op['block'] as Map}};
        _queue.removeAt(i);
      }
    }
    _queue.add(op);
    await store.save(sessionId, _queue);
    _set(SyncStatus.saved);
    _schedule();
  }

  void _schedule([Duration? delay]) {
    _timer?.cancel();
    _timer = Timer(delay ?? flushDelay, flush);
  }

  /// Sends everything queued now. Safe to call any time.
  Future<void> flush() async {
    if (_flushing || _queue.isEmpty) return;
    _flushing = true;
    final batch = _queue.take(200).toList();
    _set(SyncStatus.saving);
    try {
      final res = await api.blockOps(sessionId, batch, deviceId: deviceId);
      rev = (res['rev'] as num?)?.toInt() ?? rev;
      var conflicted = false;
      for (final r in (res['results'] as List? ?? const [])) {
        final result = r as Map<String, dynamic>;
        final op = batch.firstWhere((o) => o['clientOpId'] == result['clientOpId'], orElse: () => const {});
        switch (result['status']) {
          case 'applied':
            final block = result['block'];
            if (block is Map<String, dynamic>) {
              _applied.add(block);
              _rebase(block);
            }
          case 'conflict':
            conflicted = true;
            _conflicts.add(BlockConflict(serverBlock: result['block'] as Map<String, dynamic>, localOp: op));
          default:
            debugPrint('block op rejected: ${result['error']}');
        }
      }
      _queue.removeWhere((q) => batch.any((b) => b['clientOpId'] == q['clientOpId']));
      await store.save(sessionId, _queue);
      _failures = 0;
      _set(conflicted ? SyncStatus.conflict : (_queue.isEmpty ? SyncStatus.synced : SyncStatus.saving));
      if (_queue.isNotEmpty) _schedule(Duration.zero);
    } catch (_) {
      // Offline or server error: keep the queue, retry with backoff (max 30 s).
      _failures++;
      _set(SyncStatus.offline);
      _schedule(Duration(seconds: (1 << _failures.clamp(0, 5)).clamp(1, 30)));
    } finally {
      _flushing = false;
    }
  }

  /// Later queued ops on the same block build on the confirmed revision.
  void _rebase(Map<String, dynamic> block) {
    final revision = (block['revision'] as num?)?.toInt();
    if (revision == null) return;
    for (var i = 0; i < _queue.length; i++) {
      if (_queue[i]['blockId'] == block['id']) _queue[i] = {..._queue[i], 'baseRevision': revision};
    }
  }

  /// Catch up after a reconnect or a `block.changed` event from another device.
  Future<List<Map<String, dynamic>>> pull() async {
    final res = await api.blocks(sessionId, sinceRev: rev);
    rev = (res['rev'] as num?)?.toInt() ?? rev;
    return [for (final b in (res['blocks'] as List? ?? const [])) b as Map<String, dynamic>];
  }

  void _set(SyncStatus s) {
    if (status == s) return;
    status = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _conflicts.close();
    _applied.close();
    super.dispose();
  }
}
