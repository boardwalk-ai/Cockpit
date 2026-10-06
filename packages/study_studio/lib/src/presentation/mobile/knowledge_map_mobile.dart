import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/topic.dart';
import '../../domain/knowledge_map.dart';
import 'mobile_header.dart';
import 'mobile_motion.dart';
import 'mobile_style.dart';

const _green = Color(0xFF30A46C);
const _amber = Color(0xFFF5A623);
const _gold = Color(0xFFF5C04A);

/// A topic's colour on the map: learned, learning, needs work, or new.
Color masteryColor(Topic t, SmColors c) {
  final m = t.mastery;
  if (m >= 0.8) return _green;
  if (m >= 0.3) return _amber;
  if (m > 0) return c.accent;
  return c.line;
}

double _radius(Topic t) => 16 + t.importance.clamp(1, 5) * 2.6;

/// The phone's knowledge map: the studio's topics on a canvas, laid out by
/// what builds on what and coloured by mastery. Like n8n: drag empty space
/// to pan, pinch to zoom, drag a topic to move it (kept per studio), tap a
/// topic to open it.
class KnowledgeMapMobile extends StatefulWidget {
  const KnowledgeMapMobile({
    super.key,
    required this.studioId,
    required this.topics,
    required this.onBack,
    required this.onLesson,
    required this.onQuiz,
    this.linking = false,
  });

  final String studioId;
  final List<Topic> topics;
  final VoidCallback onBack;
  final void Function(Topic topic) onLesson;
  final void Function(Topic topic) onQuiz;

  /// The connections are still being worked out (an older studio).
  final bool linking;

  String get placesKey => 'study.map.$studioId';

  @override
  State<KnowledgeMapMobile> createState() => _KnowledgeMapMobileState();
}

class _KnowledgeMapMobileState extends State<KnowledgeMapMobile>
    with SingleTickerProviderStateMixin {
  late KnowledgeMap _map = KnowledgeMap.of(widget.topics);
  late Map<String, Offset> _places = Map.of(_map.home);

  /// Canvas → screen: screen = canvas * _scale + _pan.
  var _pan = Offset.zero;
  var _scale = 1.0;
  var _fitted = false;
  Size _view = Size.zero;

  String? _selected;

  // A gesture: dragging a topic, or panning / zooming the canvas.
  String? _dragging;
  var _startScale = 1.0;
  var _lastFocal = Offset.zero;
  var _dragged = false;

  late final AnimationController _tidy = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  Map<String, Offset> _tidyFrom = const {};

  @override
  void initState() {
    super.initState();
    _tidy.addListener(() {
      final t = Curves.easeOutCubic.transform(_tidy.value);
      setState(() {
        _places = {
          for (final id in _map.home.keys)
            id: Offset.lerp(_tidyFrom[id] ?? _map.home[id], _map.home[id], t)!,
        };
      });
    });
    unawaited(_loadPlaces());
  }

  @override
  void didUpdateWidget(KnowledgeMapMobile old) {
    super.didUpdateWidget(old);
    if (old.topics != widget.topics) {
      final hadLinks = !_map.bare;
      _map = KnowledgeMap.of(widget.topics);
      // Links arrived (an older studio): lay it out afresh.
      _places = {
        for (final id in _map.home.keys)
          id: hadLinks ? (_places[id] ?? _map.home[id]!) : _map.home[id]!,
      };
      if (!hadLinks) _fitted = false;
    }
  }

  @override
  void dispose() {
    _tidy.dispose();
    super.dispose();
  }

  Future<void> _loadPlaces() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(widget.placesKey);
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

  Future<void> _savePlaces() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        widget.placesKey,
        jsonEncode({
          for (final MapEntry(:key, :value) in _places.entries)
            key: [value.dx.roundToDouble(), value.dy.roundToDouble()],
        }),
      );
    } on Object {
      // This visit only.
    }
  }

  Offset _toCanvas(Offset screen) => (screen - _pan) / _scale;

  Topic? _topicAt(Offset screen) {
    final p = _toCanvas(screen);
    Topic? hit;
    var best = double.infinity;
    for (final t in _map.topics) {
      final at = _places[t.id];
      if (at == null) continue;
      final d = (at - p).distance;
      if (d <= _radius(t) + 10 && d < best) {
        best = d;
        hit = t;
      }
    }
    return hit;
  }

  /// Everything on screen, with room for the header and the legend.
  void _fit() {
    if (_view.isEmpty || _places.isEmpty) return;
    final top = MediaQuery.paddingOf(context).top + SmHeader.clearance + 70;
    const bottom = 70.0;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final o in _places.values) {
      minX = math.min(minX, o.dx);
      minY = math.min(minY, o.dy);
      maxX = math.max(maxX, o.dx);
      maxY = math.max(maxY, o.dy);
    }
    const pad = 56.0;
    final w = maxX - minX + pad * 2;
    final h = maxY - minY + pad * 2 + 20;
    final room = Size(_view.width, _view.height - top - bottom);
    final s = math.min(1.4, math.min(room.width / w, room.height / h));
    setState(() {
      _scale = s.clamp(0.35, 2.5);
      final centre = Offset((minX + maxX) / 2, (minY + maxY) / 2 + 10);
      _pan = Offset(room.width / 2, top + room.height / 2) - centre * _scale;
    });
  }

  void _open(Topic t) {
    SmHaptics.select();
    setState(() => _selected = t.id);
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.35),
        isScrollControlled: true,
        builder: (sheet) => _TopicSheet(
          topic: t,
          map: _map,
          onOpen: (other) {
            Navigator.of(sheet).pop();
            _centreOn(other);
            Future<void>.delayed(const Duration(milliseconds: 220), () {
              if (mounted) _open(other);
            });
          },
          onLesson: () {
            Navigator.of(sheet).pop();
            widget.onLesson(t);
          },
          onQuiz: () {
            Navigator.of(sheet).pop();
            widget.onQuiz(t);
          },
        ),
      ).whenComplete(() {
        if (mounted && _selected == t.id) setState(() => _selected = null);
      }),
    );
  }

  void _centreOn(Topic t) {
    final at = _places[t.id];
    if (at == null || _view.isEmpty) return;
    setState(() {
      _pan = Offset(_view.width / 2, _view.height * 0.38) - at * _scale;
    });
  }

  void _zoom(double by, [Offset? around]) {
    final focus = around ?? Offset(_view.width / 2, _view.height / 2);
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
        unawaited(_savePlaces());
        if (mounted) _fit();
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final top = MediaQuery.paddingOf(context).top + SmHeader.clearance;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final weak = _map.weakFoundation;
    final links = _map.edges.length;

    return Scaffold(
      backgroundColor: c.background,
      body: SmHeaderPage(
        header: SmHeader(
          title: 'How it connects',
          onBack: widget.onBack,
          trailing: SmPressable(
            semanticLabel: 'Tidy up',
            haptic: () {},
            scale: 0.9,
            onTap: _tidyUp,
            child: SizedBox(
              width: 38,
              height: 38,
              child: Icon(Icons.auto_fix_high_rounded, size: 19, color: c.text),
            ),
          ),
        ),
        child: LayoutBuilder(
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
                      final hit = _topicAt(d.localPosition);
                      if (hit != null) {
                        _open(hit);
                      } else if (_selected != null) {
                        setState(() => _selected = null);
                      }
                    },
                    onScaleStart: (d) {
                      _lastFocal = d.localFocalPoint;
                      _startScale = _scale;
                      _dragged = false;
                      final hit = d.pointerCount == 1
                          ? _topicAt(d.localFocalPoint)
                          : null;
                      _dragging = hit?.id;
                      if (hit != null) SmHaptics.select();
                    },
                    onScaleUpdate: (d) {
                      final delta = d.localFocalPoint - _lastFocal;
                      _lastFocal = d.localFocalPoint;
                      final dragging = _dragging;
                      if (dragging != null && d.pointerCount == 1) {
                        _dragged = true;
                        setState(() {
                          _places[dragging] =
                              _places[dragging]! + delta / _scale;
                        });
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
                        unawaited(_savePlaces());
                      }
                      _dragging = null;
                    },
                    child: CustomPaint(
                      painter: _MapPainter(
                        map: _map,
                        places: _places,
                        pan: _pan,
                        scale: _scale,
                        selected: _selected,
                        colors: c,
                        dark: Theme.of(context).brightness == Brightness.dark,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                // Accessibility: the topics as a list behind the canvas.
                Positioned(
                  left: 0,
                  top: 0,
                  width: 1,
                  height: 1,
                  child: Semantics(
                    container: true,
                    child: Column(
                      children: [
                        for (final topic in _map.topics)
                          Semantics(
                            button: true,
                            label:
                                '${topic.title}, '
                                '${(topic.mastery * 100).round()}% mastered',
                            onTap: () => _open(topic),
                            child: const SizedBox(width: 1, height: 0.01),
                          ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  top: top,
                  child: SmAppear(
                    index: 0,
                    child: _Insight(
                      linking: widget.linking,
                      weak: weak,
                      busiest: weak == null ? _map.mostConnected : null,
                      topics: _map.topics.length,
                      links: links,
                      onTap: (topic) {
                        _centreOn(topic);
                        _open(topic);
                      },
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  bottom: 16 + bottom,
                  child: Text(
                    '${(_scale * 100).round()}%',
                    style: t.small.copyWith(
                      fontFamily: SmFonts.heading,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: c.hint,
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 14 + bottom,
                  child: _Zoom(
                    onIn: () {
                      SmHaptics.tap();
                      _zoom(1.2);
                    },
                    onOut: () {
                      SmHaptics.tap();
                      _zoom(1 / 1.2);
                    },
                    onFit: () {
                      SmHaptics.tap();
                      _fit();
                    },
                  ),
                ),
                Positioned(
                  left: 54,
                  right: 64,
                  bottom: 18 + bottom,
                  child: const _Legend(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Room under a topic for its label.
const _label = 32.0;

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.map,
    required this.places,
    required this.pan,
    required this.scale,
    required this.selected,
    required this.colors,
    required this.dark,
  });

  final KnowledgeMap map;
  final Map<String, Offset> places;
  final Offset pan;
  final double scale;
  final String? selected;
  final SmColors colors;
  final bool dark;

  bool _lit(String id) {
    final s = selected;
    if (s == null || id == s) return true;
    return map.edges.any(
      (e) => (e.from == s && e.to == id) || (e.to == s && e.from == id),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = colors;
    // The dot grid, moving with the canvas.
    final gap = 22 * scale;
    if (gap >= 8) {
      final dot = Paint()..color = dark ? const Color(0xFF34363A) : c.line;
      final ox = pan.dx % gap;
      final oy = pan.dy % gap;
      for (var x = ox; x < size.width; x += gap) {
        for (var y = oy; y < size.height; y += gap) {
          canvas.drawCircle(Offset(x, y), 1, dot);
        }
      }
    }

    canvas
      ..save()
      ..translate(pan.dx, pan.dy)
      ..scale(scale);
    final byId = {for (final t in map.topics) t.id: t};

    for (final e in map.edges) {
      final a = places[e.from], b = places[e.to];
      final ta = byId[e.from], tb = byId[e.to];
      if (a == null || b == null || ta == null || tb == null) continue;
      final on = selected != null && (e.from == selected || e.to == selected);
      final faded = selected != null && !on;
      final colour = on
          ? c.accentSoft
          : (dark ? const Color(0xFF4A4C4C) : c.hint);
      final paint = Paint()
        ..color = colour.withValues(alpha: faded ? 0.25 : 1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = on ? 2.2 : 1.6;
      final d = b - a;
      final len = d.distance;
      if (len < 1) continue;
      final u = d / len;
      var start = a + u * _radius(ta);
      var end = b - u * (_radius(tb) + (e.buildsOn ? 4 : 0));
      // Well below: leave from under the label, arrive on top (like n8n).
      if (e.buildsOn && b.dy - a.dy > _radius(ta) + _radius(tb) + _label * 2) {
        start = Offset(a.dx, a.dy + _radius(ta) + _label);
        end = Offset(b.dx, b.dy - _radius(tb) - 4);
      }
      if (e.buildsOn) {
        final my = (start.dy + end.dy) / 2;
        final path = Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(start.dx, my, end.dx, my, end.dx, end.dy);
        canvas.drawPath(path, paint);
        // The arrowhead, along the curve's last direction.
        final dir = (end - Offset(end.dx, my));
        final n = dir.distance < 1 ? u : dir / dir.distance;
        final side = Offset(-n.dy, n.dx);
        final head = Path()
          ..moveTo(end.dx, end.dy)
          ..lineTo((end - n * 9 + side * 5).dx, (end - n * 9 + side * 5).dy)
          ..lineTo((end - n * 9 - side * 5).dx, (end - n * 9 - side * 5).dy)
          ..close();
        canvas.drawPath(
          head,
          Paint()..color = colour.withValues(alpha: faded ? 0.25 : 1),
        );
      } else {
        // Dashed: only related.
        const dash = 5.0, gapLen = 5.0;
        var run = 0.0;
        final total = (end - start).distance;
        while (run < total) {
          final p0 = start + u * run;
          final p1 = start + u * math.min(run + dash, total);
          canvas.drawLine(p0, p1, paint);
          run += dash + gapLen;
        }
      }
    }

    for (final t in map.topics) {
      final at = places[t.id];
      if (at == null) continue;
      final r = _radius(t);
      final colour = masteryColor(t, c);
      final alpha = _lit(t.id) ? 1.0 : 0.3;
      if (t.id == selected) {
        canvas.drawCircle(
          at,
          r + 7,
          Paint()
            ..color = colour.withValues(alpha: 0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      canvas
        ..drawCircle(
          at,
          r,
          Paint()
            ..color = colour.withValues(
              alpha: (t.mastery > 0 ? 0.22 : 0.14) * alpha,
            ),
        )
        ..drawCircle(
          at,
          r,
          Paint()
            ..color = colour.withValues(alpha: alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      final pct = TextPainter(
        text: TextSpan(
          text: t.mastery > 0 ? '${(t.mastery * 100).round()}%' : 'new',
          style: TextStyle(
            fontFamily: SmFonts.heading,
            fontWeight: FontWeight.w700,
            fontSize: 11,
            color: c.text.withValues(alpha: alpha),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      pct.paint(canvas, at - Offset(pct.width / 2, pct.height / 2));
      final label = TextPainter(
        text: TextSpan(
          text: t.title,
          style: TextStyle(
            fontFamily: SmFonts.body,
            fontSize: 11.5,
            height: 1.25,
            color: (t.id == selected ? c.text : c.muted).withValues(
              alpha: alpha,
            ),
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: 104);
      label.paint(canvas, at + Offset(-label.width / 2, r + 5));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MapPainter old) => true;
}

class _Insight extends StatelessWidget {
  const _Insight({
    required this.linking,
    required this.weak,
    required this.busiest,
    required this.topics,
    required this.links,
    required this.onTap,
  });

  final bool linking;
  final (Topic, int)? weak;
  final Topic? busiest;
  final int topics;
  final int links;
  final void Function(Topic topic) onTap;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final Widget body;
    VoidCallback? tap;
    if (linking) {
      body = Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: c.accentSoft,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Working out how your topics connect…',
              style: t.small.copyWith(fontSize: 12.5, color: c.text),
            ),
          ),
        ],
      );
    } else if (weak != null) {
      final (topic, n) = weak!;
      tap = () => onTap(topic);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '⚠ WEAK FOUNDATION',
            style: t.section.copyWith(fontSize: 10.5, color: _gold),
          ),
          const SizedBox(height: 3),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: topic.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text:
                      ' is at ${(topic.mastery * 100).round()}%, and $n '
                      '${n == 1 ? 'topic builds' : 'topics build'} on it. '
                      'Strengthen it first.',
                ),
              ],
            ),
            style: t.small.copyWith(
              fontSize: 12.5,
              height: 1.45,
              color: dark ? const Color(0xFFFFE7A8) : const Color(0xFF4F3500),
            ),
          ),
        ],
      );
    } else {
      final b = busiest;
      if (b != null) tap = () => onTap(b);
      body = Text(
        b == null
            ? '$topics topics, studied in order'
            : '$topics topics · $links links · ${b.title} ties the most together',
        style: t.small.copyWith(fontSize: 12.5, color: c.text),
      );
    }
    return SmPressable(
      semanticLabel: 'Insight',
      onTap: tap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: weak != null && !linking
              ? (dark ? const Color(0xFF2B2312) : const Color(0xFFFFF4D6))
              : c.raised,
          borderRadius: BorderRadius.circular(18),
        ),
        child: body,
      ),
    );
  }
}

class _Zoom extends StatelessWidget {
  const _Zoom({required this.onIn, required this.onOut, required this.onFit});

  final VoidCallback onIn;
  final VoidCallback onOut;
  final VoidCallback onFit;

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
        height: 40,
        child: Icon(i, size: 19, color: c.muted),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line, width: 1.5),
      ),
      child: Column(
        children: [
          b(Icons.add_rounded, 'Zoom in', onIn),
          Container(height: 1, width: 42, color: c.line),
          b(Icons.remove_rounded, 'Zoom out', onOut),
          Container(height: 1, width: 42, color: c.line),
          b(Icons.center_focus_strong_outlined, 'Fit to screen', onFit),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    Widget item(Color colour, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: t.small.copyWith(fontSize: 10.5)),
      ],
    );
    return IgnorePointer(
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 4,
        children: [
          item(_green, 'Learned'),
          item(_amber, 'Learning'),
          item(c.accent, 'Needs work'),
          item(c.line, 'New'),
        ],
      ),
    );
  }
}

/// A topic, opened from the map: how well it is known, and its links.
class _TopicSheet extends StatelessWidget {
  const _TopicSheet({
    required this.topic,
    required this.map,
    required this.onOpen,
    required this.onLesson,
    required this.onQuiz,
  });

  final Topic topic;
  final KnowledgeMap map;
  final void Function(Topic other) onOpen;
  final VoidCallback onLesson;
  final VoidCallback onQuiz;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final byId = {for (final x in map.topics) x.id: x};
    final colour = masteryColor(topic, c);
    final pct = (topic.mastery * 100).round();

    Widget group(String title, IconData icon, List<String> ids) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(title, style: t.section.copyWith(fontSize: 10.5)),
        const SizedBox(height: 6),
        if (ids.isEmpty)
          Text('None', style: t.small.copyWith(fontSize: 12, color: c.hint))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final id in ids)
                if (byId[id] case final other?)
                  SmPressable(
                    semanticLabel: other.title,
                    onTap: () => onOpen(other),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: c.line, width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 13, color: masteryColor(other, c)),
                          const SizedBox(width: 5),
                          Text(
                            other.title,
                            style: t.small.copyWith(
                              fontSize: 12,
                              color: c.text,
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

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
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
              Row(
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: topic.mastery.clamp(0, 1)),
                    duration: smReduceMotion(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => SizedBox(
                      width: 54,
                      height: 54,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: v,
                            strokeWidth: 5,
                            strokeCap: StrokeCap.round,
                            color: colour == c.line ? c.hint : colour,
                            backgroundColor: c.line,
                          ),
                          Text(
                            '$pct%',
                            style: TextStyle(
                              fontFamily: SmFonts.heading,
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                              color: c.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          topic.title,
                          style: t.title.copyWith(fontSize: 18),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            for (var s = 1; s <= 5; s++)
                              Icon(
                                s <= topic.importance
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                size: 14,
                                color: s <= topic.importance ? _gold : c.line,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              group('BUILDS ON', Icons.north_rounded, map.buildsOn(topic.id)),
              group('LEADS TO', Icons.south_rounded, map.leadsTo(topic.id)),
              group('RELATED', Icons.swap_horiz_rounded, map.related(topic.id)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SmPressable(
                      semanticLabel: 'Start lesson',
                      haptic: SmHaptics.thud,
                      onTap: onLesson,
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: c.accent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.menu_book_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Start lesson',
                              style: TextStyle(
                                fontFamily: SmFonts.heading,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SmPressable(
                    semanticLabel: 'Quiz me on this',
                    haptic: SmHaptics.tap,
                    onTap: onQuiz,
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: c.line, width: 1.5),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.help_outline_rounded,
                            size: 18,
                            color: c.text,
                          ),
                          const SizedBox(width: 6),
                          Text('Quiz', style: t.body.copyWith(fontSize: 14)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
