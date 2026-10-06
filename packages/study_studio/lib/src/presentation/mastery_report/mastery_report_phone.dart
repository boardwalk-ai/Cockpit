import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../application/providers.dart';
import '../../domain/study_plan.dart';
import '../mobile/mastery_report_mobile.dart';
import '../mobile/mobile_header.dart';
import '../mobile/mobile_style.dart';

/// The study plan's weekdays for a studio, if it has a plan.
final _studyDaysProvider = FutureProvider.autoDispose.family<Set<int>?, String>(
  (ref, studioId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return PlanSettings.decode(prefs.getString('study.plan.$studioId'))?.days;
    } on Object {
      return null;
    }
  },
);

/// The phone's mastery report, loaded from the studio (with its last two
/// weeks of study, and the plan's days off).
class MasteryReportPhone extends ConsumerWidget {
  const MasteryReportPhone({super.key, required this.studioId});

  final String studioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(studioActivityProvider(studioId));
    final studyDays = ref.watch(_studyDaysProvider(studioId)).valueOrNull;
    final c = SmColors.of(context);
    final base = '/study/$studioId';
    Widget plain(Widget child) => Scaffold(
      backgroundColor: c.background,
      body: SmHeaderPage(
        header: SmHeader(title: 'Mastery', onBack: () => context.go(base)),
        child: SafeArea(child: Center(child: child)),
      ),
    );
    return ref
        .watch(studioProvider(studioId))
        .when(
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          loading: () => plain(
            CircularProgressIndicator(color: c.accent, strokeWidth: 2.5),
          ),
          error: (_, _) => plain(
            Text(
              'Couldn’t load the report',
              style: SmText.of(context).small.copyWith(fontSize: 13),
            ),
          ),
          data: (studio) => MasteryReportMobile(
            studio: studio,
            onBack: () => context.go(base),
            onTopic: (t) => context.go('$base/topics/${t.id}'),
            onCards: () => context.go('$base/flashcards'),
            onPlan: () => context.go('$base/study-plan'),
            onReview: (t) => context.go('$base/flashcards?topicId=${t.id}'),
            // A failed load shows an empty week rather than none.
            activity: activity.hasError ? const [] : activity.valueOrNull,
            studyDays: studyDays,
            onStep: (s) => context.go(switch (s.step) {
              ReportStep.cards => '$base/flashcards?topicId=${s.topic.id}',
              ReportStep.quiz => '$base/quiz?topicId=${s.topic.id}',
              ReportStep.lesson => '$base/teach/${s.topic.id}',
            }),
          ),
        );
  }
}
