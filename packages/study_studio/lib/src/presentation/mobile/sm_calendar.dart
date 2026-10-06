import 'package:flutter/material.dart';

import '../../domain/study_plan.dart';
import 'mobile_motion.dart';
import 'mobile_style.dart';

const smMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const smWeekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Fri, Oct 24".
String smDate(DateTime d) =>
    '${smWeekdays[d.weekday - 1]}, ${smMonths[d.month - 1].substring(0, 3)} '
    '${d.day}';

/// A day as a small tile: the weekday over a big number, the month above
/// it on the first of one. Today is ringed, a [highlight] day filled.
class SmDateBadge extends StatelessWidget {
  const SmDateBadge({
    super.key,
    required this.date,
    this.today = false,
    this.highlight = false,
    this.muted = false,
    this.icon,
  });

  final DateTime date;
  final bool today;
  final bool highlight;
  final bool muted;

  /// Shown instead of the number (the exam's flag).
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final fg = highlight
        ? Colors.white
        : muted
        ? c.hint
        : c.text;
    return Semantics(
      label: smDate(date),
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 46,
          height: 50,
          decoration: BoxDecoration(
            color: highlight ? c.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: highlight
                  ? c.accent
                  : today
                  ? c.accentSoft
                  : c.line,
              width: today ? 1.6 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                smWeekdays[date.weekday - 1].toUpperCase(),
                style: TextStyle(
                  fontFamily: SmFonts.heading,
                  fontSize: 9,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                  color: highlight
                      ? Colors.white.withValues(alpha: 0.85)
                      : today
                      ? c.accentSoft
                      : c.hint,
                ),
              ),
              const SizedBox(height: 1),
              if (icon != null)
                Icon(icon, size: 19, color: fg)
              else
                Text(
                  '${date.day}',
                  style: TextStyle(
                    fontFamily: SmFonts.heading,
                    fontSize: 18,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Picks a date: months swipe sideways, today is ringed, the picked day
/// fills with the accent and the days up to it glow faintly, with a dot on
/// each study day. Under it, the count of days and quick picks.
class SmCalendar extends StatefulWidget {
  const SmCalendar({
    super.key,
    required this.today,
    required this.selected,
    required this.onSelected,
    this.studyDays = const {},
    this.months = 12,
  });

  final DateTime today;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelected;
  final Set<int> studyDays;

  /// How many months ahead can be picked.
  final int months;

  @override
  State<SmCalendar> createState() => _SmCalendarState();
}

class _SmCalendarState extends State<SmCalendar> {
  late final PageController _pages = PageController(
    initialPage: widget.selected == null ? 0 : _monthIndex(widget.selected!),
  );
  late int _page = _pages.initialPage;

  /// A move the code made (an arrow, a pick): its haptic is already given.
  var _moving = false;

  DateTime get _first => DateTime(widget.today.year, widget.today.month);

  int _monthIndex(DateTime d) =>
      ((d.year - _first.year) * 12 + d.month - _first.month).clamp(
        0,
        widget.months - 1,
      );

  DateTime _month(int i) => DateTime(_first.year, _first.month + i);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _go(int to) async {
    if (to < 0 || to >= widget.months) return;
    _moving = true;
    await _pages.animateToPage(
      to,
      duration: smReduceMotion(context)
          ? const Duration(milliseconds: 1)
          : const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
    _moving = false;
  }

  void _pick(DateTime d) {
    SmHaptics.select();
    widget.onSelected(d);
    final i = _monthIndex(d);
    if (i != _page) _go(i);
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final month = _month(_page);
    final sel = widget.selected;
    final away = sel == null ? null : daysBetween(widget.today, sel);
    Widget arrow(IconData icon, int to, String label) {
      final on = to >= 0 && to < widget.months;
      return SmPressable(
        semanticLabel: label,
        haptic: SmHaptics.tap,
        scale: 0.88,
        onTap: on ? () => _go(to) : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: on ? 1 : 0.3,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: c.line),
            ),
            child: Icon(icon, size: 18, color: c.text),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, 0.3),
                      end: Offset.zero,
                    ).animate(a),
                    child: child,
                  ),
                ),
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previous, ?current],
                ),
                child: Text.rich(
                  key: ValueKey(_page),
                  TextSpan(
                    children: [
                      TextSpan(
                        text: smMonths[month.month - 1],
                        style: t.greeting.copyWith(fontSize: 21),
                      ),
                      TextSpan(
                        text: '  ${month.year}',
                        style: t.small.copyWith(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            arrow(Icons.chevron_left_rounded, _page - 1, 'Previous month'),
            const SizedBox(width: 6),
            arrow(Icons.chevron_right_rounded, _page + 1, 'Next month'),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var w = 1; w <= 7; w++)
              Expanded(
                child: Center(
                  child: Text(
                    smWeekdays[w - 1].substring(0, 1),
                    style: t.section.copyWith(
                      fontSize: 10.5,
                      color: widget.studyDays.contains(w) ? c.muted : c.hint,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 6 * 44,
          child: PageView.builder(
            controller: _pages,
            itemCount: widget.months,
            onPageChanged: (i) {
              if (!_moving) SmHaptics.select(); // a swipe
              setState(() => _page = i);
            },
            itemBuilder: (context, i) => _Month(
              month: _month(i),
              today: widget.today,
              selected: sel,
              studyDays: widget.studyDays,
              onPick: _pick,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, a) => ScaleTransition(
                scale: Tween(begin: 0.7, end: 1.0).animate(a),
                child: FadeTransition(opacity: a, child: child),
              ),
              child: Text(
                away == null ? '–' : '$away',
                key: ValueKey(away),
                style: TextStyle(
                  fontFamily: SmFonts.heading,
                  fontSize: 34,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: away == null ? c.hint : c.text,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  sel == null
                      ? 'Pick your exam day'
                      : '${away == 1 ? 'day' : 'days'} to go · ${smDate(sel)}',
                  style: t.small.copyWith(fontSize: 12.5),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (label, days) in const [
              ('1 week', 7),
              ('2 weeks', 14),
              ('1 month', 30),
              ('2 months', 61),
            ])
              _Quick(
                label: label,
                on: away == days,
                onTap: () => _pick(widget.today.add(Duration(days: days))),
              ),
          ],
        ),
      ],
    );
  }
}

class _Month extends StatelessWidget {
  const _Month({
    required this.month,
    required this.today,
    required this.selected,
    required this.studyDays,
    required this.onPick,
  });

  final DateTime month;
  final DateTime today;
  final DateTime? selected;
  final Set<int> studyDays;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final lead = month.weekday - 1;
    final count = DateTime(month.year, month.month + 1, 0).day;
    final sel = selected == null ? null : dayOf(selected!);
    final start = dayOf(today);
    return Column(
      children: [
        for (var row = 0; row < 6; row++)
          SizedBox(
            height: 44,
            child: Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final n = row * 7 + col - lead + 1;
                        if (n < 1 || n > count) return const SizedBox();
                        final d = DateTime(month.year, month.month, n);
                        final past = d.isBefore(start);
                        final isToday = d == start;
                        final picked = sel != null && d == sel;
                        final between =
                            sel != null && d.isAfter(start) && d.isBefore(sel);
                        final study = studyDays.contains(d.weekday);
                        return _Day(
                          day: d,
                          past: past,
                          today: isToday,
                          picked: picked,
                          between: between,
                          startOfBand: between && (col == 0 || n == 1),
                          endOfBand: between && (col == 6 || n == count),
                          dot: between && study,
                          onTap: past ? null : () => onPick(d),
                          colors: c,
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({
    required this.day,
    required this.past,
    required this.today,
    required this.picked,
    required this.between,
    required this.startOfBand,
    required this.endOfBand,
    required this.dot,
    required this.onTap,
    required this.colors,
  });

  final DateTime day;
  final bool past;
  final bool today;
  final bool picked;
  final bool between;
  final bool startOfBand;
  final bool endOfBand;
  final bool dot;
  final VoidCallback? onTap;
  final SmColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final band = c.accent.withValues(alpha: 0.12);
    return Semantics(
      button: onTap != null,
      selected: picked,
      label: smDate(day),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // The faint band from today to the picked day.
            if (between)
              Positioned.fill(
                top: 5,
                bottom: 5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: band,
                    borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(startOfBand ? 17 : 0),
                      right: Radius.circular(endOfBand ? 17 : 0),
                    ),
                  ),
                ),
              ),
            AnimatedScale(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              scale: picked ? 1.08 : 1,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: picked ? c.accent : Colors.transparent,
                  border: today && !picked
                      ? Border.all(color: c.accentSoft, width: 1.5)
                      : null,
                  boxShadow: picked
                      ? [
                          BoxShadow(
                            color: c.accent.withValues(alpha: 0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: ExcludeSemantics(
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      fontFamily: SmFonts.heading,
                      fontSize: 13.5,
                      fontWeight: picked || today
                          ? FontWeight.w800
                          : FontWeight.w500,
                      color: picked
                          ? Colors.white
                          : past
                          ? c.line
                          : c.text,
                    ),
                  ),
                ),
              ),
            ),
            if (dot)
              Positioned(
                bottom: 6,
                child: Container(
                  width: 3.5,
                  height: 3.5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.accentSoft,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Quick extends StatelessWidget {
  const _Quick({required this.label, required this.on, required this.onTap});

  final String label;
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
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: on ? c.accent : c.line),
        ),
        child: Text(
          label,
          style: t.body.copyWith(
            fontSize: 12.5,
            color: on ? c.accentSoft : c.text,
          ),
        ),
      ),
    );
  }
}
