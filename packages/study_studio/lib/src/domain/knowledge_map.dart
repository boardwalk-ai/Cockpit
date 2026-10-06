import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'entities/topic.dart';

/// A link between two topics on the knowledge map.
class MapEdge {
  const MapEdge(this.from, this.to, {required this.buildsOn});

  /// For "builds on": the topic needed first.
  final String from;
  final String to;

  /// Solid arrow (from → to) when one builds on the other; a dashed line
  /// when they are only related.
  final bool buildsOn;
}

/// The studio's topics as a map: who builds on whom, who is related, and
/// where each sits (needed-first above, later below).
class KnowledgeMap {
  KnowledgeMap._(this.topics, this.edges, this.home);

  /// The topics, in study order.
  final List<Topic> topics;
  final List<MapEdge> edges;

  /// Each topic's place in the tidy layout.
  final Map<String, Offset> home;

  static const rowGap = 130.0;
  static const columnGap = 112.0;

  /// True when nothing links the topics: the map is just study order.
  bool get bare => edges.isEmpty;

  factory KnowledgeMap.of(List<Topic> topics) {
    final byTitle = {for (final t in topics) t.title.trim().toLowerCase(): t};
    final ids = {for (final t in topics) t.id};
    final edges = <MapEdge>[];
    final parents = <String, List<String>>{};
    for (final t in topics) {
      for (final name in t.prerequisites) {
        final p = byTitle[name.trim().toLowerCase()];
        if (p == null || p.id == t.id) continue;
        edges.add(MapEdge(p.id, t.id, buildsOn: true));
        (parents[t.id] ??= []).add(p.id);
      }
    }
    final seen = <String>{};
    for (final t in topics) {
      for (final other in t.relatedTopicIds) {
        if (!ids.contains(other) || other == t.id) continue;
        final key = ([t.id, other]..sort()).join('|');
        if (!seen.add(key)) continue;
        final linked = edges.any(
          (e) =>
              (e.from == t.id && e.to == other) ||
              (e.from == other && e.to == t.id),
        );
        if (!linked) edges.add(MapEdge(t.id, other, buildsOn: false));
      }
    }

    // Rows: a topic sits one below the deepest topic it builds on.
    final depth = <String, int>{};
    int depthOf(String id, Set<String> path) {
      final known = depth[id];
      if (known != null) return known;
      if (!path.add(id)) return 0; // a loop: stop here
      final ps = parents[id] ?? const [];
      final d = ps.isEmpty
          ? 0
          : ps.map((p) => depthOf(p, path)).reduce(math.max) + 1;
      path.remove(id);
      return depth[id] = d;
    }

    final rows = <int, List<Topic>>{};
    if (edges.any((e) => e.buildsOn)) {
      for (final t in topics) {
        (rows[depthOf(t.id, {})] ??= []).add(t);
      }
    } else {
      // Nothing builds on anything: rows of three, in study order.
      for (final (i, t) in topics.indexed) {
        (rows[i ~/ 3] ??= []).add(t);
      }
    }
    final widest = rows.values.fold<int>(0, (m, r) => math.max(m, r.length));
    final width = math.max(1, widest - 1) * columnGap;
    final home = <String, Offset>{};
    for (final MapEntry(key: row, value: list) in rows.entries) {
      final span = (list.length - 1) * columnGap;
      for (final (i, t) in list.indexed) {
        // Stagger long rows so labels don't sit on one line.
        final stagger = list.length > 3 && i.isOdd ? 34.0 : 0.0;
        home[t.id] = Offset(
          (width - span) / 2 + i * columnGap,
          row * rowGap + stagger,
        );
      }
    }
    return KnowledgeMap._(topics, edges, home);
  }

  /// Topics that build on [id].
  List<String> leadsTo(String id) => [
    for (final e in edges)
      if (e.buildsOn && e.from == id) e.to,
  ];

  /// Topics [id] builds on.
  List<String> buildsOn(String id) => [
    for (final e in edges)
      if (e.buildsOn && e.to == id) e.from,
  ];

  /// Topics only related to [id].
  List<String> related(String id) => [
    for (final e in edges)
      if (!e.buildsOn && (e.from == id || e.to == id))
        e.from == id ? e.to : e.from,
  ];

  /// Everything that, step by step, builds on [id].
  Set<String> dependents(String id) {
    final out = <String>{};
    final queue = [id];
    while (queue.isNotEmpty) {
      for (final next in leadsTo(queue.removeLast())) {
        if (out.add(next)) queue.add(next);
      }
    }
    return out;
  }

  /// The weakest topic that others depend on, with how many: the one to
  /// strengthen first. Null when nothing weak holds anything up.
  (Topic, int)? get weakFoundation {
    (Topic, int)? best;
    for (final t in topics) {
      if (t.mastery >= 0.6) continue;
      final n = dependents(t.id).length;
      if (n == 0) continue;
      if (best == null ||
          n > best.$2 ||
          (n == best.$2 && t.mastery < best.$1.mastery)) {
        best = (t, n);
      }
    }
    return best;
  }

  /// The topic with the most links.
  Topic? get mostConnected {
    Topic? best;
    var most = 0;
    for (final t in topics) {
      final n = edges.where((e) => e.from == t.id || e.to == t.id).length;
      if (n > most) {
        most = n;
        best = t;
      }
    }
    return best;
  }
}
