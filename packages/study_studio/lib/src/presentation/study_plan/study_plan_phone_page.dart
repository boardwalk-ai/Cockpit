import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../domain/study_plan.dart';
import '../mobile/mobile_header.dart';
import '../mobile/mobile_style.dart';
import '../mobile/study_plan_mobile.dart';

/// The phone's study plan, loaded from the studio.
class StudyPlanPhonePage extends ConsumerWidget {
  const StudyPlanPhonePage({super.key, required this.studioId});

  final String studioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = SmColors.of(context);
    final base = '/study/$studioId';
    Widget plain(Widget child) => Scaffold(
      backgroundColor: c.background,
      body: SmHeaderPage(
        header: SmHeader(title: 'Study plan', onBack: () => context.go(base)),
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
              'Couldn’t open the plan',
              style: SmText.of(context).small.copyWith(fontSize: 13),
            ),
          ),
          data: (studio) => StudyPlanMobile(
            studio: studio,
            onBack: () => context.go(base),
            onStep: (s) {
              final id = s.topic?.id;
              context.go(switch (s.kind) {
                StepKind.review => '$base/flashcards',
                StepKind.lesson => '$base/teach/$id',
                StepKind.cards => '$base/flashcards?topicId=$id',
                StepKind.quiz => '$base/quiz?topicId=$id',
              });
            },
          ),
        );
  }
}
