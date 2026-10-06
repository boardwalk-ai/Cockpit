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
    this.examIn,
  });

  /// Whole days since the studio was last opened.
  final int away;
  final int due;

  /// The topic slipping most, if any.
  final Topic? fading;

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
      Widget fact(IconData icon, Color color, InlineSpan text) => appear(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.line),
                ),
                child: Icon(icon, size: 17, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(text, style: t.body.copyWith(fontSize: 14)),
              ),
            ],
          ),
        ),
      );
      TextSpan bold(String s) => TextSpan(
        text: s,
        style: const TextStyle(fontWeight: FontWeight.w700),
      );
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
              appear(
                Text(
                  '${wb.away} days away',
                  textAlign: TextAlign.center,
                  style: t.small.copyWith(fontSize: 12.5),
                ),
              ),
              const SizedBox(height: 2),
              appear(
                Text(
                  'Welcome back',
                  textAlign: TextAlign.center,
                  style: t.greeting.copyWith(fontSize: 23),
                ),
              ),
              const SizedBox(height: 18),
              if (wb.due > 0)
                fact(
                  Icons.style_rounded,
                  c.text,
                  TextSpan(
                    children: [
                      bold('${wb.due} card${wb.due == 1 ? '' : 's'}'),
                      const TextSpan(text: ' came due'),
                    ],
                  ),
                ),
              if (wb.fading != null)
                fact(
                  Icons.trending_down_rounded,
                  c.gold,
                  TextSpan(
                    children: [
                      bold(wb.fading!.title),
                      const TextSpan(text: ' is fading'),
                    ],
                  ),
                ),
              if (wb.examIn != null)
                fact(
                  Icons.flag_rounded,
                  c.accentSoft,
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Exam in '),
                      bold('${wb.examIn} day${wb.examIn == 1 ? '' : 's'}'),
                    ],
                  ),
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
                        fontWeight: FontWeight.w700,
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
