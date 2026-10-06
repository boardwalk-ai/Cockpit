import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'entities/concept.dart';
import 'entities/topic.dart';

/// A node on a lesson's concept map: one of its ideas, or a stub that
/// leads into another lesson.
class ConceptNode {
  const ConceptNode({
    required this.id,
    required this.name,
    this.concept,
    this.topicTitle,
  });

  final String id;
  final String name;
  final Concept? concept;

  /// Set for a stub: the other lesson's title.
  final String? topicTitle;

  bool get isStub => topicTitle != null;
}

/// A labelled arrow: "[from] [label] [to]".
class ConceptEdge {
  const ConceptEdge(this.from, this.label, this.to);

  final String from;
  final String label;
  final String to;

  String get key => '$from>$to';
}

/// One lesson's ideas and how they connect, laid out in rows (an idea sits
/// below the ones that lead to it), plus the links to hide when practising.
class ConceptMap {
  ConceptMap._(this.topic, this.nodes, this.edges, this.home);

  final Topic topic;
  final List<ConceptNode> nodes;
  final List<ConceptEdge> edges;
  final Map<String, Offset> home;

  static const rowGap = 118.0;
  static const columnGap = 150.0;

  bool get isEmpty => nodes.isEmpty;

  factory ConceptMap.of(Topic topic) {
    final nodes = <ConceptNode>[
      for (final c in topic.concepts)
        ConceptNode(id: c.id, name: c.name, concept: c),
    ];
    final ids = {for (final n in nodes) n.id};
    final edges = <ConceptEdge>[];
    for (final l in topic.conceptLinks) {
      if (!ids.contains(l.from)) continue;
      final to = l.to;
      final other = l.toTopic;
      if (to != null && ids.contains(to) && to != l.from) {
        edges.add(ConceptEdge(l.from, l.label, to));
      } else if (other != null && other.trim().isNotEmpty) {
        final stub = 'topic:${other.trim()}';
        if (!ids.contains(stub)) {
          ids.add(stub);
          nodes.add(
            ConceptNode(id: stub, name: other.trim(), topicTitle: other.trim()),
          );
        }
        edges.add(ConceptEdge(l.from, l.label, stub));
      }
    }

    // Rows: one below the deepest idea that leads to it.
    final parents = <String, List<String>>{};
    for (final e in edges) {
      (parents[e.to] ??= []).add(e.from);
    }
    final depth = <String, int>{};
    int depthOf(String id, Set<String> path) {
      final known = depth[id];
      if (known != null) return known;
      if (!path.add(id)) return 0;
      final ps = parents[id] ?? const [];
      final d = ps.isEmpty
          ? 0
          : ps.map((p) => depthOf(p, path)).reduce(math.max) + 1;
      path.remove(id);
      return depth[id] = d;
    }

    final rows = <int, List<ConceptNode>>{};
    for (final n in nodes) {
      (rows[depthOf(n.id, {})] ??= []).add(n);
    }
    final widest = rows.values.fold<int>(0, (m, r) => math.max(m, r.length));
    final width = math.max(1, widest - 1) * columnGap;
    final home = <String, Offset>{};
    for (final MapEntry(key: row, value: list) in rows.entries) {
      final span = (list.length - 1) * columnGap;
      for (final (i, n) in list.indexed) {
        final stagger = list.length > 2 && i.isOdd ? 26.0 : 0.0;
        home[n.id] = Offset(
          (width - span) / 2 + i * columnGap,
          row * rowGap + stagger,
        );
      }
    }
    return ConceptMap._(topic, nodes, edges, home);
  }

  ConceptNode? node(String id) {
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  /// The links whose words are hidden in "Complete the map": every other
  /// link between two ideas, at most four, at least one.
  List<ConceptEdge> get practice {
    final inner = [
      for (final e in edges)
        if (!e.to.startsWith('topic:')) e,
    ];
    if (inner.isEmpty) return const [];
    final picked = [
      for (final (i, e) in inner.indexed)
        if (i.isEven) e,
    ];
    return picked.take(4).toList();
  }

  static const _fallback = [
    'causes',
    'is part of',
    'prevents',
    'contrasts with',
    'depends on',
    'produces',
  ];

  /// Four labels to choose from for [edge]: its own, and three others
  /// ([pool]: other labels in the studio, used first).
  static List<String> choices(ConceptEdge edge, Iterable<String> pool) {
    final right = edge.label.trim().toLowerCase();
    final others = <String>[];
    for (final l in [...pool, ..._fallback]) {
      final t = l.trim().toLowerCase();
      if (t.isEmpty || t == right || others.contains(t)) continue;
      others.add(t);
      if (others.length == 3) break;
    }
    final all = [right, ...others];
    // A fixed shuffle per link, so the right answer isn't always first.
    final seed = edge.key.codeUnits.fold<int>(0, (a, b) => a + b);
    all.shuffle(math.Random(seed));
    return all;
  }
}
