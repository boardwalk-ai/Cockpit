import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/api/upload_api.dart' show BuildSnapshot;
import '../../domain/entities/studio.dart';
import '../../domain/entities/topic.dart';
import 'mobile_header.dart';
import 'mobile_motion.dart';
import 'mobile_style.dart';

/// How the learning modes are laid out; the user's pick is kept.
enum ModesView { carousel, list, grid }

/// One way to learn.
class StudyMode {
  const StudyMode({
    required this.icon,
    required this.color,
    required this.title,
    required this.blurb,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String blurb;
  final String count;
  final VoidCallback onTap;
}

/// The phone's studio page: how to learn (a carousel, a list or a grid),
/// the topics with their mastery, and Continue at the foot.
class StudioMainMobile extends StatefulWidget {
  const StudioMainMobile({
    super.key,
    required this.studio,
    required this.modes,
    this.build,
    this.onMenu,
    this.onRefresh,
  });

  final Studio studio;
  final List<StudyMode> modes;

  /// A build still running: its latest state, shown under the header.
  final BuildSnapshot? build;
  final VoidCallback? onMenu;
  final Future<void> Function()? onRefresh;

  static const viewKey = 'study.modes.view';

  @override
  State<StudioMainMobile> createState() => _StudioMainMobileState();
}

class _StudioMainMobileState extends State<StudioMainMobile> {
  var _view = ModesView.carousel;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(StudioMainMobile.viewKey);
      final view = ModesView.values.where((v) => v.name == saved).firstOrNull;
      if (view != null && mounted) setState(() => _view = view);
    } on Object {
      // No storage: the carousel it is.
    }
  }

  Future<void> _pick(ModesView view) async {
    if (view == _view) return;
    SmHaptics.select();
    setState(() => _view = view);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(StudioMainMobile.viewKey, view.name);
    } on Object {
      // Kept for this visit only.
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final studio = widget.studio;
    final base = '/study/${studio.id}';
    final top = MediaQuery.paddingOf(context).top + SmHeader.clearance;
    final topics = [...studio.topics]
      ..sort((a, b) => a.mastery.compareTo(b.mastery));
    final next = topics.firstOrNull;
    final build = widget.build;

    Widget appear(int i, Widget child) => SmAppear(index: i, child: child);

    final body = ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(0, top + 4, 0, next == null ? 32 : 96),
      children: [
        if (build != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: _BuildStrip(snap: build),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: appear(
            0,
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    'How do you want\nto learn today?',
                    style: t.greeting.copyWith(fontSize: 21),
                  ),
                ),
                const SizedBox(width: 10),
                _ViewPill(view: _view, onPick: _pick),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        appear(
          1,
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.04),
                  end: Offset.zero,
                ).animate(a),
                child: child,
              ),
            ),
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topCenter,
              children: [...previous, ?current],
            ),
            child: KeyedSubtree(
              key: ValueKey(_view),
              child: switch (_view) {
                ModesView.carousel => _Carousel(modes: widget.modes),
                ModesView.list => _ModeList(modes: widget.modes),
                ModesView.grid => _ModeGrid(modes: widget.modes),
              },
            ),
          ),
        ),
        const SizedBox(height: 26),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: appear(
            2,
            _Topics(
              studio: studio,
              topics: topics,
              onOpen: (topic) => context.go('$base/topics/${topic.id}'),
              onAll: () => context.go('$base/topics'),
            ),
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: c.background,
      body: SmHeaderPage(
        header: SmHeader(
          title: studio.title,
          onBack: () => context.go('/study'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RoundButton(
                icon: Icons.auto_awesome_rounded,
                label: 'Ask AI',
                color: c.accentSoft,
                onTap: () => context.go('$base/ask-ai'),
              ),
              if (widget.onMenu != null) ...[
                const SizedBox(width: 6),
                _RoundButton(
                  icon: Icons.more_horiz_rounded,
                  label: 'Studio options',
                  onTap: widget.onMenu!,
                ),
              ],
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: widget.onRefresh == null
                  ? body
                  : RefreshIndicator(
                      color: c.accent,
                      backgroundColor: c.raised,
                      edgeOffset: top,
                      onRefresh: () async {
                        SmHaptics.tap();
                        await widget.onRefresh!();
                      },
                      child: body,
                    ),
            ),
            if (next != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _ContinueBar(
                  topic: next,
                  onTap: () => context.go('$base/teach/${next.id}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SmPressable(
      semanticLabel: label,
      haptic: SmHaptics.tap,
      scale: 0.9,
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: dark
              ? const Color(0x14FFFFFF)
              : c.raised.withValues(alpha: 0.8),
        ),
        child: Icon(icon, size: 19, color: color ?? c.text),
      ),
    );
  }
}

/// Three small icons in a pill; a knob slides to the one picked.
class _ViewPill extends StatelessWidget {
  const _ViewPill({required this.view, required this.onPick});

  final ModesView view;
  final ValueChanged<ModesView> onPick;

  static const _icons = {
    ModesView.carousel: Icons.view_carousel_outlined,
    ModesView.list: Icons.view_agenda_outlined,
    ModesView.grid: Icons.grid_view_rounded,
  };

  static const _w = 28.0;
  static const _h = 24.0;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutBack,
            left: _w * view.index,
            top: 0,
            child: Container(
              width: _w,
              height: _h,
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF424444) : Colors.white,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final v in ModesView.values)
                Semantics(
                  button: true,
                  selected: v == view,
                  label: '${v.name[0].toUpperCase()}${v.name.substring(1)}',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onPick(v),
                    child: SizedBox(
                      width: _w,
                      height: _h,
                      child: Icon(
                        _icons[v],
                        size: 15,
                        color: v == view ? c.text : c.hint,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A mode's tile colour: its hue, faint, over the page.
Color _tint(BuildContext context, Color color) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return Color.alphaBlend(
    color.withValues(alpha: dark ? 0.18 : 0.12),
    SmColors.of(context).background,
  );
}

class _ModeIcon extends StatelessWidget {
  const _ModeIcon({required this.mode, this.size = 36});

  final StudyMode mode;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: mode.color,
      borderRadius: BorderRadius.circular(size * 0.32),
    ),
    child: Icon(mode.icon, size: size * 0.52, color: Colors.white),
  );
}

class _Carousel extends StatefulWidget {
  const _Carousel({required this.modes});

  final List<StudyMode> modes;

  @override
  State<_Carousel> createState() => _CarouselState();
}

class _CarouselState extends State<_Carousel> {
  final _scroll = ScrollController();
  var _page = 0;

  static const _card = 168.0;
  static const _gap = 10.0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final page = (_scroll.offset / (_card + _gap)).round().clamp(
        0,
        widget.modes.length - 1,
      );
      if (page != _page) {
        SmHaptics.select();
        setState(() => _page = page);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 182,
          child: ListView.separated(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            physics: const _SnapPhysics(extent: _card + _gap),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: widget.modes.length,
            separatorBuilder: (_, _) => const SizedBox(width: _gap),
            itemBuilder: (context, i) {
              final m = widget.modes[i];
              return SmPressable(
                semanticLabel: m.title,
                onTap: m.onTap,
                child: Container(
                  width: _card,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _tint(context, m.color),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ModeIcon(mode: m),
                      const Spacer(),
                      Text(m.title, style: t.title.copyWith(fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(
                        m.blurb,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.small.copyWith(
                          color: Color.lerp(m.color, c.text, 0.35),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(m.count, style: t.small.copyWith(color: c.hint)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              for (var i = 0; i < widget.modes.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.only(right: 4),
                  width: i == _page ? 16 : 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: i == _page ? c.accent : c.line,
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Settles on a card's edge.
class _SnapPhysics extends ScrollPhysics {
  const _SnapPhysics({required this.extent, super.parent});

  final double extent;

  @override
  _SnapPhysics applyTo(ScrollPhysics? ancestor) =>
      _SnapPhysics(extent: extent, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final page = position.pixels / extent + velocity / 1800;
    final target = (page.round() * extent).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 0.5) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: toleranceFor(position),
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}

class _ModeList extends StatelessWidget {
  const _ModeList({required this.modes});

  final List<StudyMode> modes;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          for (final (i, m) in modes.indexed)
            SmPressable(
              semanticLabel: m.title,
              onTap: m.onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: i == 0
                      ? null
                      : Border(top: BorderSide(color: c.line)),
                ),
                child: Row(
                  children: [
                    _ModeIcon(mode: m, size: 38),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.title, style: t.title.copyWith(fontSize: 14)),
                          Text(
                            m.blurb,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.small,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(m.count, style: t.small.copyWith(color: c.hint)),
                    Icon(Icons.chevron_right_rounded, color: c.hint, size: 20),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModeGrid extends StatelessWidget {
  const _ModeGrid({required this.modes});

  final List<StudyMode> modes;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = (box.maxWidth - 10) / 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final m in modes)
                SmPressable(
                  semanticLabel: m.title,
                  onTap: m.onTap,
                  child: Container(
                    width: w,
                    height: 100,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _tint(context, m.color),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _ModeIcon(mode: m, size: 30),
                            const Spacer(),
                            Text(
                              m.count.split(' ').first,
                              style: t.small.copyWith(color: c.hint),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          m.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.title.copyWith(fontSize: 13.5),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// TOPICS, the overall mastery, a row per topic (weakest first).
class _Topics extends StatelessWidget {
  const _Topics({
    required this.studio,
    required this.topics,
    required this.onOpen,
    required this.onAll,
  });

  final Studio studio;
  final List<Topic> topics;
  final ValueChanged<Topic> onOpen;
  final VoidCallback onAll;

  static const shown = 6;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    if (topics.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(
          'Topics appear here as your studio finishes building.',
          textAlign: TextAlign.center,
          style: t.small.copyWith(fontSize: 12),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('TOPICS', style: t.section),
            const Spacer(),
            Text(
              '${(studio.overallMastery * 100).round()}% overall',
              style: t.small.copyWith(color: c.accentSoft, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final (i, topic) in topics.take(shown).indexed)
          SmPressable(
            semanticLabel: topic.title,
            onTap: () => onOpen(topic),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                border: i == 0 ? null : Border(top: BorderSide(color: c.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      topic.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.body,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _MasteryBar(value: topic.mastery),
                ],
              ),
            ),
          ),
        if (topics.length > shown)
          SmPressable(
            semanticLabel: 'All topics',
            onTap: onAll,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'All ${topics.length} topics',
                    style: t.small.copyWith(color: c.accentSoft, fontSize: 12),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: c.accentSoft,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _MasteryBar extends StatelessWidget {
  const _MasteryBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final strong = value >= 0.8;
    return SizedBox(
      width: 64,
      height: 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: c.line)),
            TweenAnimationBuilder<double>(
              tween: Tween(end: value.clamp(0, 1)),
              duration: smReduceMotion(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => FractionallySizedBox(
                widthFactor: v,
                child: ColoredBox(
                  color: strong ? const Color(0xFF30A46C) : c.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Continue with the weakest topic, pinned at the foot over a fade.
class _ContinueBar extends StatelessWidget {
  const _ContinueBar({required this.topic, required this.onTap});

  final Topic topic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        28,
        16,
        14 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.45],
          colors: [c.background.withValues(alpha: 0), c.background],
        ),
      ),
      child: SmAppear(
        index: 3,
        child: SmPressable(
          semanticLabel: 'Continue with ${topic.title}',
          haptic: SmHaptics.thud,
          onTap: onTap,
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: c.accent,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: c.accent.withValues(alpha: 0.3),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Continue · ${topic.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.body.copyWith(
                      color: Colors.white,
                      fontSize: 14,
                      fontFamily: SmFonts.heading,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A build still running: what it is doing and how far, slim.
class _BuildStrip extends StatelessWidget {
  const _BuildStrip({required this.snap});

  final BuildSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final done = snap.isDone;
    final failed = snap.isFailed;
    final tint = failed
        ? c.accent
        : done
        ? const Color(0xFF30A46C)
        : c.accentSoft;
    final label = failed
        ? 'The build failed'
        : done
        ? 'Your studio is ready'
        : snap.status == 'generating' && snap.lessonsTotal > 0
        ? 'Building lessons (${snap.lessonsDone} of ${snap.lessonsTotal})…'
        : 'Building your studio…';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              failed
                  ? Icons.error_outline_rounded
                  : done
                  ? Icons.check_circle_rounded
                  : Icons.auto_awesome_rounded,
              size: 16,
              color: tint,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: t.small.copyWith(color: tint, fontSize: 12),
              ),
            ),
            Text(
              '${(snap.progressPct * 100).floor()}%',
              style: t.small.copyWith(
                color: tint,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(
            height: 4,
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: c.line)),
                TweenAnimationBuilder<double>(
                  tween: Tween(end: snap.progressPct.clamp(0, 1)),
                  duration: const Duration(milliseconds: 700),
                  builder: (context, v, _) => FractionallySizedBox(
                    widthFactor: v,
                    child: ColoredBox(color: tint),
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
