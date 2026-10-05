import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/entities/topic.dart';
import 'mobile_header.dart';
import 'mobile_motion.dart';
import 'mobile_style.dart';

/// Which topics show.
enum TopicFilter { all, review, learned, fresh }

/// How they are ordered.
enum TopicSort { path, weakest, name }

const _green = Color(0xFF30A46C);

/// Mastery at which a topic counts as learned.
const learnedAt = 0.8;

/// The phone's topic library: your path (how many are learned), a search,
/// filters (all, to review, learned, new) and a row per topic with its
/// mastery ring.
class TopicLibraryMobile extends StatefulWidget {
  const TopicLibraryMobile({
    super.key,
    required this.topics,
    required this.onBack,
    required this.onOpen,
  });

  /// In the order they are meant to be studied.
  final List<Topic> topics;
  final VoidCallback onBack;
  final void Function(Topic topic) onOpen;

  @override
  State<TopicLibraryMobile> createState() => _TopicLibraryMobileState();
}

class _TopicLibraryMobileState extends State<TopicLibraryMobile> {
  final _search = TextEditingController();
  var _filter = TopicFilter.all;
  var _sort = TopicSort.path;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static bool _keep(TopicFilter f, Topic t) => switch (f) {
    TopicFilter.all => true,
    TopicFilter.review => t.mastery > 0 && t.mastery < learnedAt,
    TopicFilter.learned => t.mastery >= learnedAt,
    TopicFilter.fresh => t.mastery == 0,
  };

  List<Topic> get _shown {
    final q = _search.text.trim().toLowerCase();
    final list = [
      for (final t in widget.topics)
        if (_keep(_filter, t) &&
            (q.isEmpty || t.title.toLowerCase().contains(q)))
          t,
    ];
    switch (_sort) {
      case TopicSort.path:
        break;
      case TopicSort.weakest:
        list.sort((a, b) => a.mastery.compareTo(b.mastery));
      case TopicSort.name:
        list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
    }
    return list;
  }

  Future<void> _pickSort() async {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final picked = await showModalBottomSheet<TopicSort>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (sheet) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF2A2B2B) : Colors.white,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: c.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                child: Text('Sort by', style: t.title),
              ),
              for (final (s, label, icon) in const [
                (TopicSort.path, 'Study order', Icons.route_rounded),
                (TopicSort.weakest, 'Weakest first', Icons.trending_up),
                (TopicSort.name, 'Name', Icons.sort_by_alpha_rounded),
              ])
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.of(sheet).pop(s),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 13,
                    ),
                    child: Row(
                      children: [
                        Icon(icon, size: 20, color: c.text),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            label,
                            style: t.body.copyWith(fontSize: 14),
                          ),
                        ),
                        if (s == _sort)
                          Icon(Icons.check_rounded, size: 20, color: c.accent),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && picked != _sort) {
      SmHaptics.select();
      setState(() => _sort = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final top = MediaQuery.paddingOf(context).top + SmHeader.clearance;
    final topics = widget.topics;
    final learned = topics.where((x) => x.mastery >= learnedAt).length;
    final shown = _shown;

    return Scaffold(
      backgroundColor: c.background,
      body: SmHeaderPage(
        header: SmHeader(
          title: 'Topics',
          onBack: widget.onBack,
          trailing: SmPressable(
            semanticLabel: 'Sort',
            haptic: SmHaptics.tap,
            scale: 0.9,
            onTap: _pickSort,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0x14FFFFFF)
                    : c.raised.withValues(alpha: 0.8),
              ),
              child: Icon(Icons.swap_vert_rounded, size: 20, color: c.text),
            ),
          ),
        ),
        child: ListView(
          physics: const BouncingScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(20, top + 4, 20, 40),
          children: [
            SmAppear(
              index: 0,
              child: _Path(learned: learned, total: topics.length),
            ),
            const SizedBox(height: 18),
            SmAppear(
              index: 1,
              child: _Search(controller: _search, count: topics.length),
            ),
            const SizedBox(height: 12),
            SmAppear(
              index: 2,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                child: Row(
                  children: [
                    for (final f in TopicFilter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _FilterChip(
                          label: switch (f) {
                            TopicFilter.all => 'All',
                            TopicFilter.review => 'To review',
                            TopicFilter.learned => 'Learned',
                            TopicFilter.fresh => 'New',
                          },
                          count: f == TopicFilter.all
                              ? null
                              : topics.where((x) => _keep(f, x)).length,
                          on: f == _filter,
                          onTap: () {
                            if (f == _filter) return;
                            SmHaptics.select();
                            setState(() => _filter = f);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              child: KeyedSubtree(
                key: ValueKey('$_filter/$_sort/${_search.text}'),
                child: shown.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Text(
                          _search.text.trim().isNotEmpty
                              ? 'No topic matches “${_search.text.trim()}”'
                              : 'Nothing here yet',
                          textAlign: TextAlign.center,
                          style: t.small.copyWith(fontSize: 13),
                        ),
                      )
                    : Column(
                        children: [
                          for (final (i, topic) in shown.indexed)
                            _Row(
                              topic: topic,
                              first: i == 0,
                              onTap: () => widget.onOpen(topic),
                            ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Your path: how many topics are learned, as a bar.
class _Path extends StatelessWidget {
  const _Path({required this.learned, required this.total});

  final int learned;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final value = total == 0 ? 0.0 : learned / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                'Your path',
                style: t.greeting.copyWith(fontSize: 22),
              ),
            ),
            Text(
              '$learned of $total learned',
              style: t.small.copyWith(fontSize: 12.5),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(
            height: 6,
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: c.line)),
                TweenAnimationBuilder<double>(
                  tween: Tween(end: value),
                  duration: smReduceMotion(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => FractionallySizedBox(
                    widthFactor: v,
                    child: const ColoredBox(color: _green),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Search extends StatelessWidget {
  const _Search({required this.controller, required this.count});

  final TextEditingController controller;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 20, color: c.hint),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              cursorColor: c.accent,
              textInputAction: TextInputAction.search,
              style: t.body.copyWith(fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Search $count topics',
                hintStyle: t.body.copyWith(fontSize: 14, color: c.hint),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            SmPressable(
              semanticLabel: 'Clear search',
              haptic: SmHaptics.tap,
              onTap: controller.clear,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.close_rounded, size: 18, color: c.hint),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.on,
    required this.onTap,
    this.count,
  });

  final String label;
  final int? count;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return SmPressable(
      semanticLabel: label,
      haptic: () {},
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: on ? c.text : c.raised,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          count == null ? label : '$label  $count',
          style: t.small.copyWith(
            fontSize: 12.5,
            color: on ? c.background : c.muted,
            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.topic, required this.first, required this.onTap});

  final Topic topic;
  final bool first;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final pct = (topic.mastery * 100).round();
    final level = switch (topic.difficulty) {
      <= 2 => 'Easy',
      3 => 'Medium',
      _ => 'Hard',
    };
    return SmPressable(
      semanticLabel: topic.title,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          border: first ? null : Border(top: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(end: topic.mastery.clamp(0, 1)),
              duration: smReduceMotion(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => SizedBox(
                width: 34,
                height: 34,
                child: CustomPaint(
                  painter: _MiniRing(
                    value: v,
                    track: c.line,
                    color: topic.mastery >= learnedAt ? _green : c.accent,
                  ),
                  child: topic.mastery >= learnedAt
                      ? const Icon(Icons.check_rounded, size: 15, color: _green)
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    topic.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.body.copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${pct == 0 ? 'Not started' : '$pct% mastered'} · $level',
                    style: t.small.copyWith(color: c.hint),
                  ),
                ],
              ),
            ),
            if (topic.importance >= 5) ...[
              const SizedBox(width: 6),
              const Icon(
                Icons.star_rounded,
                size: 16,
                color: Color(0xFFF5C04A),
                semanticLabel: 'Key topic',
              ),
            ],
            Icon(Icons.chevron_right_rounded, size: 20, color: c.hint),
          ],
        ),
      ),
    );
  }
}

class _MiniRing extends CustomPainter {
  _MiniRing({required this.value, required this.track, required this.color});

  final double value;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 3.5;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (value > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * value,
        false,
        paint..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_MiniRing old) =>
      old.value != value || old.color != color || old.track != track;
}
