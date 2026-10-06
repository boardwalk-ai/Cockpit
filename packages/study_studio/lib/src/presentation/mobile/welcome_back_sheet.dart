import 'package:flutter/material.dart';

import '../../domain/entities/studio.dart';
import '../../domain/entities/topic.dart';
import '../../domain/study_plan.dart';
import 'mastery_report_mobile.dart' show MasteryReport;
import 'mobile_motion.dart';
import 'mobile_style.dart';

/// What changed while the user was away from a studio.
class WelcomeBack {
  const WelcomeBack({
    required this.away,
    required this.due,
    this.fading,
    this.recall = 0,
    this.examIn,
  });

  /// Whole days since the studio was last opened.
  final int away;
  final int due;

  /// The topic slipping most, if any, and how much of it is left (0–1).
  final Topic? fading;
  final double recall;

  /// Days to the exam, with an exam plan.
  final int? examIn;

  static const minDays = 3;

  /// Null on a first visit, after a short break, or with nothing to say.
  static WelcomeBack? of(
    Studio studio, {
    required DateTime? lastOpen,
    required DateTime now,
    PlanSettings? plan,
  }) {
    if (lastOpen == null) return null;
    final away = daysBetween(lastOpen, now);
    if (away < minDays) return null;
    final report = MasteryReport(studio, now);
    final slipping = report.fading.where((f) => f.slipping).firstOrNull;
    final due = report.dueNow;
    if (due == 0 && slipping == null) return null;
    final exam = plan?.mode == PlanMode.exam && plan?.exam != null
        ? daysBetween(now, plan!.exam!)
        : null;
    return WelcomeBack(
      away: away,
      due: due,
      fading: slipping?.topic,
      recall: slipping?.recall ?? 0,
      examIn: exam != null && exam >= 0 ? exam : null,
    );
  }
}

/// The sheet: days away, what came due, what's fading, the exam; a short
/// warm-up or not now.
Future<void> showWelcomeBack(
  BuildContext context,
  WelcomeBack wb, {
  required VoidCallback onWarmUp,
}) {
  final c = SmColors.of(context);
  final t = SmText.of(context);
  final dark = Theme.of(context).brightness == Brightness.dark;
  SmHaptics.select();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (sheet) {
      var i = 0;
      Widget appear(Widget child) => SmAppear(index: i++, child: child);
      Widget fact(Widget lead, Widget text, {bool last = false}) => appear(
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: c.line),
              bottom: last ? BorderSide(color: c.line) : BorderSide.none,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(width: 52, child: lead),
              Expanded(child: text),
            ],
          ),
        ),
      );
      Widget numeral(int n, Color color) => Text(
        '$n',
        style: TextStyle(
          fontFamily: SmFonts.heading,
          fontSize: 26,
          height: 1,
          letterSpacing: -0.9,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      );
      Widget words(String s) => Text(s, style: t.body.copyWith(fontSize: 14));
      final facts = [
        if (wb.due > 0) 'due',
        if (wb.fading != null) 'fading',
        if (wb.examIn != null) 'exam',
      ];
      final minutes = (wb.due / 2).ceil().clamp(5, 15);
      return SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF2A2B2B) : Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: c.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: c.line,
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
              appear(_DaysAway(days: wb.away)),
              const SizedBox(height: 8),
              appear(
                Text(
                  '${wb.away} days away',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: SmFonts.heading,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: c.hint,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              appear(
                Text(
                  'Welcome back',
                  textAlign: TextAlign.center,
                  style: t.greeting.copyWith(
                    fontSize: 25,
                    letterSpacing: -0.8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (wb.due > 0)
                fact(
                  numeral(wb.due, c.text),
                  words('card${wb.due == 1 ? '' : 's'} came due'),
                  last: facts.last == 'due',
                ),
              if (wb.fading != null)
                fact(
                  _Memory(value: wb.recall),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: wb.fading!.title,
                          style: TextStyle(
                            fontFamily: SmFonts.reading,
                            fontStyle: FontStyle.italic,
                            fontSize: 16,
                            color: c.text,
                          ),
                        ),
                        const TextSpan(text: ' is fading'),
                      ],
                    ),
                    style: t.body.copyWith(fontSize: 14),
                  ),
                  last: facts.last == 'fading',
                ),
              if (wb.examIn != null)
                fact(
                  numeral(wb.examIn!, c.accentSoft),
                  words('day${wb.examIn == 1 ? '' : 's'} to your exam'),
                  last: true,
                ),
              const SizedBox(height: 8),
              appear(
                SmPressable(
                  semanticLabel: 'Warm up',
                  haptic: SmHaptics.thud,
                  onTap: () {
                    Navigator.of(sheet).pop();
                    onWarmUp();
                  },
                  child: Container(
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Warm up · $minutes min',
                      style: const TextStyle(
                        fontFamily: SmFonts.heading,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              appear(
                SmPressable(
                  semanticLabel: 'Not now',
                  haptic: SmHaptics.tap,
                  onTap: () => Navigator.of(sheet).pop(),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Not now',
                      textAlign: TextAlign.center,
                      style: t.body.copyWith(fontSize: 14, color: c.muted),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The days away as dots: the last visit filled, the missed days empty,
/// today ringed. A long break shows the last week of it.
class _DaysAway extends StatelessWidget {
  const _DaysAway({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final gap = days.clamp(1, 7) - 1;
    Widget dot({required bool filled, bool ring = false, int delay = 0}) =>
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: smReduceMotion(context)
              ? Duration.zero
              : Duration(milliseconds: 300 + delay * 70),
          curve: Curves.easeOutBack,
          builder: (context, v, child) =>
              Transform.scale(scale: v, child: child),
          child: Container(
            width: ring ? 15 : 8,
            height: ring ? 15 : 8,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled && !ring ? c.accent : Colors.transparent,
              border: ring
                  ? Border.all(color: c.accentSoft, width: 1.5)
                  : filled
                  ? null
                  : Border.all(color: c.hint, width: 1.3),
            ),
            child: ring
                ? Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.accent,
                    ),
                  )
                : null,
          ),
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        dot(filled: true),
        for (var i = 0; i < gap; i++) dot(filled: false, delay: i + 1),
        dot(filled: true, ring: true, delay: gap + 1),
      ],
    );
  }
}

/// Five little bars, filled to how much is still remembered.
class _Memory extends StatelessWidget {
  const _Memory({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final filled = (value * 5).round().clamp(0, 5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Container(
            width: 7,
            height: 4,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: i < filled ? c.gold : c.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}
