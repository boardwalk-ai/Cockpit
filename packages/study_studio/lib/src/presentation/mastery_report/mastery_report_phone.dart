import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../mobile/mastery_report_mobile.dart';
import '../mobile/mobile_header.dart';
import '../mobile/mobile_style.dart';

/// The phone's mastery report, loaded from the studio.
class MasteryReportPhone extends ConsumerWidget {
  const MasteryReportPhone({super.key, required this.studioId});

  final String studioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            onStep: (s) => context.go(switch (s.step) {
              ReportStep.cards => '$base/flashcards?topicId=${s.topic.id}',
              ReportStep.quiz => '$base/quiz?topicId=${s.topic.id}',
              ReportStep.lesson => '$base/teach/${s.topic.id}',
            }),
          ),
        );
  }
}
