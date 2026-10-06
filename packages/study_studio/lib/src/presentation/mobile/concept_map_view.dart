import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/concept_map.dart';
import '../../domain/entities/topic.dart';
import 'mobile_motion.dart';
import 'mobile_style.dart';

const _green = Color(0xFF30A46C);

/// One lesson's concept map on an n8n-style canvas: its ideas as pills,
/// joined by arrows that say how ("triggers", "halves"). Drag space to
/// pan, pinch to zoom, drag an idea to move it, tap an idea to read it.
/// "Complete the map" hides some arrows' words to fill back in.
class ConceptMapView extends StatefulWidget {
  const ConceptMapView({
    super.key,
    required this.studioId,
    required this.topic,
    required this.labelPool,
    required this.onLesson,
    required this.onOpenTopic,
    required this.onAnswer,
    this.loading = false,
    this.top = 0,
  });

  final String studioId;
  final Topic topic;

  /// Link words used across the studio, for wrong choices.
  final List<String> labelPool;
  final VoidCallback onLesson;

  /// A stub into another lesson was tapped (its title).
  final void Function(String title) onOpenTopic;
  final void Function(bool correct) onAnswer;

  /// The map is still being made (an older lesson).
  final bool loading;

  /// Room taken at the top by the header.
  final double top;

  @override
  State<ConceptMapView> createState() => _ConceptMapViewState();
}

class _ConceptMapViewState extends State<ConceptMapView>
    with SingleTickerProviderStateMixin {
  late ConceptMap _map = ConceptMap.of(widget.topic);

  /// The tidy layout, spaced by each pill's real width.
  late Map<String, Offset> _home = _spaced();
  late Map<String, Offset> _places = Map.of(_home);
  final _sizes = <String, Size>{};

  var _pan = Offset.zero;
  var _scale = 1.0;
  var _fitted = false;
  Size _view = Size.zero;

  var _practice = false;
  final _answers = <String, String>{};
  String? _selected;

  String? _dragging;
  var _dragged = false;
  var _startScale = 1.0;
  var _lastFocal = Offset.zero;

  late final AnimationController _tidy = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  Map<String, Offset> _tidyFrom = const {};

  String get _key => 'study.concepts.${widget.studioId}.${widget.topic.id}';

  @override
  void initState() {
    super.initState();
    _tidy.addListener(() {
      final t = Curves.easeOutCubic.transform(_tidy.value);
      setState(() {
        _places = {
          for (final id in _home.keys)
            id: Offset.lerp(_tidyFrom[id] ?? _home[id], _home[id], t)!,
        };
      });
    });
    unawaited(_load());
  }

  @override
  void didUpdateWidget(ConceptMapView old) {
    super.didUpdateWidget(old);
    if (old.topic != widget.topic) {
      final was = _map.isEmpty;
      _map = ConceptMap.of(widget.topic);
      _home = _spaced();
      _places = {for (final id in _home.keys) id: _places[id] ?? _home[id]!};
      if (was) _fitted = false;
    }
  }

  @override
  void dispose() {
    _tidy.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || !mounted) return;
      final saved = (jsonDecode(raw) as Map).cast<String, dynamic>();
      setState(() {
        for (final MapEntry(:key, :value) in saved.entries) {
          if (!_places.containsKey(key)) continue;
          final xy = (value as List).cast<num>();
          _places[key] = Offset(xy[0].toDouble(), xy[1].toDouble());
        }
      });
    } on Object {
      // The tidy layout.
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          for (final MapEntry(:key, :value) in _places.entries)
            key: [value.dx.roundToDouble(), value.dy.roundToDouble()],
        }),
      );
    } on Object {
      // This visit only.
    }
  }

  /// Rows from the map, each pill placed by its width so none overlap.
  Map<String, Offset> _spaced() {
    const gap = 30.0;
    final rows = <double, List<ConceptNode>>{};
    for (final n in _map.nodes) {
      final at = _map.home[n.id];
      if (at == null) continue;
      (rows[(at.dy / ConceptMap.rowGap).floorToDouble()] ??= []).add(n);
    }
    final out = <String, Offset>{};
    for (final MapEntry(key: row, value: list) in rows.entries) {
      list.sort((a, b) => _map.home[a.id]!.dx.compareTo(_map.home[b.id]!.dx));
      final total =
          list.fold<double>(0, (w, n) => w + _size(n).width) +
          gap * (list.length - 1);
      var x = -total / 2;
      for (final (i, n) in list.indexed) {
        final w = _size(n).width;
        // A little stagger keeps the arrows' words apart.
        final stagger = list.length > 2 && i.isOdd ? 26.0 : 0.0;
        out[n.id] = Offset(x + w / 2, row * ConceptMap.rowGap + stagger);
        x += w + gap;
      }
    }
    return out;
  }

  Size _size(ConceptNode n) => _sizes[n.id] ??= () {
    final tp = TextPainter(
      text: TextSpan(
        text: n.isStub ? '→ ${n.name}' : n.name,
        style: const TextStyle(fontFamily: SmFonts.body, fontSize: 12.5),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 190);
    return Size(tp.width + 30, n.isStub ? 30 : 40);
  }();

  Rect _rect(ConceptNode n) {
    final at = _places[n.id] ?? Offset.zero;
    final s = _size(n);
    return Rect.fromCenter(center: at, width: s.width, height: s.height);
  }

  Offset _toCanvas(Offset screen) => (screen - _pan) / _scale;

  ConceptNode? _nodeAt(Offset screen) {
    final p = _toCanvas(screen);
    for (final n in _map.nodes.reversed) {
      if (_rect(n).inflate(6).contains(p)) return n;
    }
    return null;
  }

  ConceptEdge? _labelAt(Offset screen) {
    final p = _toCanvas(screen);
    for (final e in _map.edges) {
      final m = _labelCentre(e);
      if (m != null && (m - p).distance < 22) return e;
    }
    return null;
  }

  Offset? _labelCentre(ConceptEdge e) {
    final a = _map.node(e.from), b = _map.node(e.to);
    if (a == null || b == null) return null;
    final (s, t) = _ends(_rect(a), _rect(b));
    return Offset.lerp(s, t, 0.5);
  }

  void _fit() {
    if (_view.isEmpty || _places.isEmpty) return;
    final top = widget.top + 56;
    const bottom = 60.0;
    var box = Rect.zero;
    var first = true;
    for (final n in _map.nodes) {
      final r = _rect(n);
      box = first ? r : box.expandToInclude(r);
      first = false;
    }
    box = box.inflate(30);
    final room = Size(_view.width, _view.height - top - bottom);
    final s = math.min(
      1.3,
      math.min(room.width / box.width, room.height / box.height),
    );
    setState(() {
      _scale = s.clamp(0.35, 2.5);
      _pan =
          Offset(room.width / 2, top + room.height / 2) - box.center * _scale;
    });
  }

  void _zoom(double by) {
    SmHaptics.tap();
    _zoomAt(by, Offset(_view.width / 2, _view.height / 2));
  }

  void _zoomAt(double by, Offset focus) {
    final next = (_scale * by).clamp(0.35, 2.5);
    setState(() {
      _pan = focus - (focus - _pan) * (next / _scale);
      _scale = next;
    });
  }

  void _tidyUp() {
    SmHaptics.thud();
    _tidyFrom = Map.of(_places);
    unawaited(
      _tidy.forward(from: 0).then((_) {
        unawaited(_save());
        if (mounted) _fit();
      }),
    );
  }

  void _setPractice(bool on) {
    if (on == _practice) return;
    SmHaptics.select();
    setState(() {
      _practice = on;
      _selected = null;
    });
  }

  void _openConcept(ConceptNode n) {
    if (n.isStub) {
      SmHaptics.select();
      widget.onOpenTopic(n.topicTitle!);
      return;
    }
    if (_practice) return;
    SmHaptics.select();
    setState(() => _selected = n.id);
    final source = widget.topic.sources.firstOrNull;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.3),
        isScrollControlled: true,
        builder: (sheet) => _ConceptSheet(
          node: n,
          source: source == null
              ? null
              : source.page == null
              ? source.fileName
              : '${source.fileName} · p.${source.page}',
          onLesson: () {
            Navigator.of(sheet).pop();
            widget.onLesson();
          },
        ),
      ).whenComplete(() {
        if (mounted && _selected == n.id) setState(() => _selected = null);
      }),
    );
  }

  void _ask(ConceptEdge e) {
    final a = _map.node(e.from), b = _map.node(e.to);
    if (a == null || b == null) return;
    SmHaptics.select();
    unawaited(
      showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.3),
        builder: (sheet) => _ChoiceSheet(
          from: a.name,
          to: b.name,
          choices: ConceptMap.choices(e, widget.labelPool),
        ),
      ).then((picked) {
        if (picked == null || !mounted) return;
        final right = picked == e.label.trim().toLowerCase();
        if (right) {
          SmHaptics.done();
        } else {
          SmHaptics.error();
        }
        widget.onAnswer(right);
        setState(() => _answers[e.key] = picked);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final practice = _map.practice;
    final hidden = {for (final e in practice) e.key};
    final done = practice.where((e) => _answers.containsKey(e.key)).length;
    final right = practice
        .where((e) => _answers[e.key] == e.label.trim().toLowerCase())
        .length;

    if (_map.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(32, widget.top, 32, 0),
          child: widget.loading
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      color: c.accent,
                      strokeWidth: 2.5,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Pulling out the key ideas…',
                      style: t.small.copyWith(fontSize: 13),
                    ),
                  ],
                )
              : Text(
                  'This lesson has no concept map yet.',
                  textAlign: TextAlign.center,
                  style: t.small.copyWith(fontSize: 13),
                ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, box) {
        _view = box.biggest;
        if (!_fitted && _view.width > 0) {
          _fitted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _fit();
          });
        }
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  if (_practice) {
                    final e = _labelAt(d.localPosition);
                    if (e != null &&
                        hidden.contains(e.key) &&
                        !_answers.containsKey(e.key)) {
                      _ask(e);
                      return;
                    }
                  }
                  final n = _nodeAt(d.localPosition);
                  if (n != null) {
                    _openConcept(n);
                  } else if (_selected != null) {
                    setState(() => _selected = null);
                  }
                },
                onScaleStart: (d) {
                  _lastFocal = d.localFocalPoint;
                  _startScale = _scale;
                  _dragged = false;
                  final n = d.pointerCount == 1
                      ? _nodeAt(d.localFocalPoint)
                      : null;
                  _dragging = n?.id;
                  if (n != null) SmHaptics.select();
                },
                onScaleUpdate: (d) {
                  final delta = d.localFocalPoint - _lastFocal;
                  _lastFocal = d.localFocalPoint;
                  final id = _dragging;
                  if (id != null && d.pointerCount == 1) {
                    _dragged = true;
                    setState(() => _places[id] = _places[id]! + delta / _scale);
                    return;
                  }
                  final next = (_startScale * d.scale).clamp(0.35, 2.5);
                  setState(() {
                    final focus = d.localFocalPoint;
                    _pan = focus - (focus - delta - _pan) * (next / _scale);
                    _scale = next;
                  });
                },
                onScaleEnd: (_) {
                  if (_dragging != null && _dragged) {
                    SmHaptics.tap();
                    unawaited(_save());
                  }
                  _dragging = null;
                },
                child: CustomPaint(
                  painter: _ConceptPainter(
                    map: _map,
                    rectOf: _rect,
                    pan: _pan,
                    scale: _scale,
                    selected: _selected,
                    hidden: _practice ? hidden : const {},
                    answers: _practice ? _answers : const {},
                    colors: c,
                    dark: Theme.of(context).brightness == Brightness.dark,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            // The mouse wheel zooms (desktop); touches pass through.
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerSignal: (e) {
                  if (e is! PointerScrollEvent) return;
                  final by = e.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1;
                  _zoomAt(by, e.localPosition);
                },
              ),
            ),
            // Accessibility: the ideas and the blanks, behind the canvas.
            Positioned(
              left: 0,
              top: 0,
              width: 1,
              height: 1,
              child: Semantics(
                container: true,
                child: Column(
                  children: [
                    for (final n in _map.nodes)
                      Semantics(
                        button: true,
                        label: n.isStub ? 'Go to ${n.name}' : n.name,
                        onTap: () => _openConcept(n),
                        child: const SizedBox(width: 1, height: 0.01),
                      ),
                    if (_practice)
                      for (final e in practice)
                        if (!_answers.containsKey(e.key))
                          Semantics(
                            button: true,
                            label:
                                'Blank between ${_map.node(e.from)?.name} '
                                'and ${_map.node(e.to)?.name}',
                            onTap: () => _ask(e),
                            child: const SizedBox(width: 1, height: 0.01),
                          ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: widget.top + 6,
              left: 0,
              right: 0,
              child: Center(
                child: _Modes(
                  practice: _practice,
                  canPractise: practice.isNotEmpty,
                  onChange: _setPractice,
                ),
              ),
            ),
            if (_practice)
              Positioned(
                left: 60,
                right: 60,
                bottom: 22 + bottom,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  child: Text(
                    done < practice.length
                        ? '$done of ${practice.length} filled · tap a ?'
                        : '$right of ${practice.length} right · mastery updated',
                    key: ValueKey('$done/$right'),
                    textAlign: TextAlign.center,
                    style: t.small.copyWith(
                      fontSize: 12,
                      color: done == practice.length ? _green : c.muted,
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 12,
              bottom: 14 + bottom,
              child: _Controls(
                onIn: () => _zoom(1.2),
                onOut: () => _zoom(1 / 1.2),
                onFit: () {
                  SmHaptics.tap();
                  _fit();
                },
                onTidy: _tidyUp,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Where an arrow between two pills starts and ends: on their edges, along
/// the line between their centres.
(Offset, Offset) _ends(Rect a, Rect b) {
  Offset edge(Rect r, Offset toward) {
    final c = r.center;
    final d = toward - c;
    if (d.distance < 1) return c;
    final sx = d.dx == 0 ? double.infinity : (r.width / 2) / d.dx.abs();
    final sy = d.dy == 0 ? double.infinity : (r.height / 2) / d.dy.abs();
    return c + d * math.min(sx, sy);
  }

  return (edge(a, b.center), edge(b, a.center));
}

class _ConceptPainter extends CustomPainter {
  _ConceptPainter({
    required this.map,
    required this.rectOf,
    required this.pan,
    required this.scale,
    required this.selected,
    required this.hidden,
    required this.answers,
    required this.colors,
    required this.dark,
  });

  final ConceptMap map;
  final Rect Function(ConceptNode) rectOf;
  final Offset pan;
  final double scale;
  final String? selected;
  final Set<String> hidden;
  final Map<String, String> answers;
  final SmColors colors;
  final bool dark;

  bool _near(String id) {
    final s = selected;
    if (s == null || id == s) return true;
    return map.edges.any(
      (e) => (e.from == s && e.to == id) || (e.to == s && e.from == id),
    );
  }

  void _text(
    Canvas canvas,
    String text,
    Offset centre,
    TextStyle style, {
    double max = 190,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: max);
    tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = colors;
    final gap = 22 * scale;
    if (gap >= 8) {
      final dot = Paint()..color = dark ? const Color(0xFF34363A) : c.line;
      for (var x = pan.dx % gap; x < size.width; x += gap) {
        for (var y = pan.dy % gap; y < size.height; y += gap) {
          canvas.drawCircle(Offset(x, y), 1, dot);
        }
      }
    }
    canvas
      ..save()
      ..translate(pan.dx, pan.dy)
      ..scale(scale);

    final lines = dark ? const Color(0xFF5A5C5C) : c.hint;
    for (final e in map.edges) {
      final a = map.node(e.from), b = map.node(e.to);
      if (a == null || b == null) continue;
      final (s, t) = _ends(rectOf(a), rectOf(b));
      final on = selected != null && (e.from == selected || e.to == selected);
      final faded = selected != null && !on;
      final colour = (on ? c.accentSoft : lines).withValues(
        alpha: faded ? 0.25 : 1,
      );
      final paint = Paint()
        ..color = colour
        ..strokeWidth = on ? 2 : 1.6
        ..style = PaintingStyle.stroke;
      final stub = b.isStub;
      if (stub) {
        final u = (t - s) / math.max((t - s).distance, 1);
        var run = 0.0;
        final total = (t - s).distance;
        while (run < total) {
          canvas.drawLine(s + u * run, s + u * math.min(run + 5, total), paint);
          run += 10;
        }
      } else {
        canvas.drawLine(s, t, paint);
      }
      // Arrowhead.
      final d = t - s;
      if (d.distance > 1) {
        final n = d / d.distance;
        final side = Offset(-n.dy, n.dx);
        final tip = t - n * 2;
        canvas.drawPath(
          Path()
            ..moveTo(tip.dx, tip.dy)
            ..lineTo((tip - n * 9 + side * 5).dx, (tip - n * 9 + side * 5).dy)
            ..lineTo((tip - n * 9 - side * 5).dx, (tip - n * 9 - side * 5).dy)
            ..close(),
          Paint()..color = colour,
        );
      }
      // The words on the arrow, in a small pill.
      final mid = Offset.lerp(s, t, 0.5)!;
      final blank = hidden.contains(e.key) && !answers.containsKey(e.key);
      final given = answers[e.key];
      final right = given != null && given == e.label.trim().toLowerCase();
      final words = blank ? '?' : (given ?? e.label);
      final style = TextStyle(
        fontFamily: SmFonts.body,
        fontSize: 11,
        fontStyle: blank ? FontStyle.normal : FontStyle.italic,
        fontWeight: blank ? FontWeight.w700 : FontWeight.w400,
        color: blank
            ? c.accentSoft
            : given == null
            ? c.muted.withValues(alpha: faded ? 0.3 : 1)
            : (right ? _green : c.accent),
      );
      final tp = TextPainter(
        text: TextSpan(text: words, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: 130);
      final pill = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: mid,
          width: math.max(26, tp.width + 16),
          height: 22,
        ),
        const Radius.circular(11),
      );
      canvas
        ..drawRRect(pill, Paint()..color = c.background)
        ..drawRRect(
          pill,
          Paint()
            ..color = blank
                ? c.accent
                : given == null
                ? c.line.withValues(alpha: faded ? 0.3 : 1)
                : (right ? _green : c.accent)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      tp.paint(canvas, mid - Offset(tp.width / 2, tp.height / 2));
    }

    for (final n in map.nodes) {
      final r = RRect.fromRectAndRadius(rectOf(n), const Radius.circular(99));
      final alpha = _near(n.id) ? 1.0 : 0.35;
      final on = n.id == selected;
      canvas
        ..drawRRect(
          r,
          Paint()
            ..color =
                (n.isStub
                        ? c.background
                        : on
                        ? (dark
                              ? const Color(0xFF3A1517)
                              : const Color(0xFFFDECEC))
                        : c.raised)
                    .withValues(alpha: alpha),
        )
        ..drawRRect(
          r,
          Paint()
            ..color = (on ? c.accent : c.line).withValues(alpha: alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      _text(
        canvas,
        n.isStub ? '→ ${n.name}' : n.name,
        r.center,
        TextStyle(
          fontFamily: SmFonts.body,
          fontSize: 12.5,
          fontWeight: n.isStub ? FontWeight.w400 : FontWeight.w500,
          color: (n.isStub ? c.muted : c.text).withValues(alpha: alpha),
        ),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ConceptPainter old) => true;
}

/// Explore · Complete the map.
class _Modes extends StatelessWidget {
  const _Modes({
    required this.practice,
    required this.canPractise,
    required this.onChange,
  });

  final bool practice;
  final bool canPractise;
  final ValueChanged<bool> onChange;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget tab(String label, bool on, VoidCallback? onTap) => SmPressable(
      semanticLabel: label,
      haptic: () {},
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: on
              ? (dark ? const Color(0xFF424444) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          label,
          style: t.small.copyWith(
            fontSize: 12,
            color: on ? c.text : c.muted,
            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          tab('Explore', !practice, () => onChange(false)),
          tab(
            'Complete the map',
            practice,
            canPractise ? () => onChange(true) : null,
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.onIn,
    required this.onOut,
    required this.onFit,
    required this.onTidy,
  });

  final VoidCallback onIn;
  final VoidCallback onOut;
  final VoidCallback onFit;
  final VoidCallback onTidy;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    Widget b(IconData i, String label, VoidCallback onTap) => SmPressable(
      semanticLabel: label,
      haptic: () {},
      scale: 0.9,
      onTap: onTap,
      child: SizedBox(
        width: 42,
        height: 38,
        child: Icon(i, size: 18, color: c.muted),
      ),
    );
    Widget rule() => Container(height: 1, width: 42, color: c.line);
    return Container(
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line, width: 1.5),
      ),
      child: Column(
        children: [
          b(Icons.add_rounded, 'Zoom in', onIn),
          rule(),
          b(Icons.remove_rounded, 'Zoom out', onOut),
          rule(),
          b(Icons.center_focus_strong_outlined, 'Fit to screen', onFit),
          rule(),
          b(Icons.auto_fix_high_rounded, 'Tidy up', onTidy),
        ],
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF2A2B2B) : Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: c.line),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: c.line,
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _ConceptSheet extends StatelessWidget {
  const _ConceptSheet({
    required this.node,
    required this.source,
    required this.onLesson,
  });

  final ConceptNode node;
  final String? source;
  final VoidCallback onLesson;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final concept = node.concept!;
    return _Sheet(
      children: [
        Text(concept.name, style: t.title.copyWith(fontSize: 18)),
        if (concept.meaning.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            concept.meaning,
            style: TextStyle(
              fontFamily: SmFonts.reading,
              fontSize: 15.5,
              height: 1.55,
              color: c.text.withValues(alpha: 0.92),
            ),
          ),
        ],
        if (concept.example.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF14202E) : const Color(0xFFEAF2FB),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'EXAMPLE',
                  style: t.section.copyWith(
                    fontSize: 10.5,
                    color: dark
                        ? const Color(0xFF85B7EB)
                        : const Color(0xFF185FA5),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  concept.example,
                  style: t.body.copyWith(
                    fontSize: 13.5,
                    color: dark
                        ? const Color(0xFFD6E6F7)
                        : const Color(0xFF0C2F55),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            if (source != null)
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: c.line, width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: 14,
                        color: c.muted,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          source!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.small.copyWith(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const Spacer(),
            SmPressable(
              semanticLabel: 'Open the lesson',
              haptic: SmHaptics.thud,
              onTap: onLesson,
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.menu_book_rounded,
                      color: Colors.white,
                      size: 17,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Lesson',
                      style: TextStyle(
                        fontFamily: SmFonts.heading,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// "How does it connect?": the four choices for a blank.
class _ChoiceSheet extends StatelessWidget {
  const _ChoiceSheet({
    required this.from,
    required this.to,
    required this.choices,
  });

  final String from;
  final String to;
  final List<String> choices;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return _Sheet(
      children: [
        Text('How does it connect?', style: t.small.copyWith(fontSize: 13)),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '$from '),
              TextSpan(
                text: '→ ? →',
                style: TextStyle(color: c.accentSoft),
              ),
              TextSpan(text: ' $to'),
            ],
          ),
          style: t.title.copyWith(fontSize: 16, height: 1.4),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final choice in choices)
              SmPressable(
                semanticLabel: choice,
                haptic: () {},
                onTap: () => Navigator.of(context).pop(choice),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: c.line, width: 1.5),
                  ),
                  child: Text(
                    choice,
                    style: t.body.copyWith(
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
