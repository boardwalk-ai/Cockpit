import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../application/study_voice.dart';
import '../mobile/ask_ai_mobile.dart';
import '../mobile/mobile_header.dart';
import '../mobile/mobile_style.dart';

/// The phone's Ask AI, answered from the studio's files by the backend.
class AskAiPhonePage extends ConsumerWidget {
  const AskAiPhonePage({super.key, required this.studioId});

  final String studioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = SmColors.of(context);
    final base = '/study/$studioId';
    Widget plain(Widget child) => Scaffold(
      backgroundColor: c.background,
      body: SmHeaderPage(
        header: SmHeader(title: 'Ask AI', onBack: () => context.go(base)),
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
              'Couldn’t open this studio',
              style: SmText.of(context).small.copyWith(fontSize: 13),
            ),
          ),
          data: (studio) => AskAiMobile(
            topics: studio.topics,
            fileCount: studio.sourceFiles.length,
            voice: ref.watch(studyVoiceProvider),
            ask: (question, topic, history) => ref
                .read(aiServiceProvider)
                .ask(
                  studioId: studioId,
                  question: question,
                  topic: topic,
                  history: history,
                ),
            onBack: () => context.go(base),
            onLesson: (t) => context.go('$base/teach/${t.id}'),
            onQuiz: (t) => context.go('$base/quiz?topicId=${t.id}'),
            onCards: (t) => context.go('$base/flashcards?topicId=${t.id}'),
          ),
        );
  }
}
