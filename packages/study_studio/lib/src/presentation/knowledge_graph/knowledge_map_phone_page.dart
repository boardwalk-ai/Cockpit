import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../domain/entities/studio.dart';
import '../../domain/knowledge_map.dart';
import '../mobile/knowledge_map_mobile.dart';
import '../mobile/mobile_header.dart';
import '../mobile/mobile_style.dart';

/// Visualize (phone and desktop): loads the studio, and for one built before its
/// topics were linked, asks the server once to link them.
class KnowledgeMapPhonePage extends ConsumerStatefulWidget {
  const KnowledgeMapPhonePage({super.key, required this.studioId});

  final String studioId;

  @override
  ConsumerState<KnowledgeMapPhonePage> createState() =>
      _KnowledgeMapPhonePageState();
}

class _KnowledgeMapPhonePageState extends ConsumerState<KnowledgeMapPhonePage> {
  var _asked = false;
  var _linking = false;

  Future<void> _link(Studio studio) async {
    if (_asked || studio.topics.length < 2) return;
    if (!KnowledgeMap.of(studio.topics).bare) return;
    _asked = true;
    setState(() => _linking = true);
    try {
      final linked = await ref
          .read(studioRepositoryProvider)
          .linkTopics(widget.studioId);
      if (linked) ref.invalidate(studioProvider(widget.studioId));
    } on Object {
      // The map stays in study order.
    }
    if (mounted) setState(() => _linking = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final base = '/study/${widget.studioId}';
    Widget plain(Widget child) => Scaffold(
      backgroundColor: c.background,
      body: SmHeaderPage(
        header: SmHeader(
          title: 'How it connects',
          onBack: () => context.go(base),
        ),
        child: SafeArea(child: Center(child: child)),
      ),
    );
    final note = SmText.of(context).small.copyWith(fontSize: 13);
    return ref
        .watch(studioProvider(widget.studioId))
        .when(
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          loading: () => plain(
            CircularProgressIndicator(color: c.accent, strokeWidth: 2.5),
          ),
          error: (_, _) => plain(Text('Couldn’t load the map', style: note)),
          data: (studio) {
            if (studio.topics.isEmpty) {
              return plain(
                Text('Topics appear here as your studio builds', style: note),
              );
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) unawaited(_link(studio));
            });
            return KnowledgeMapMobile(
              studioId: studio.id,
              topics: studio.topics,
              linking: _linking,
              onBack: () => context.go(base),
              onLesson: (t) => context.go('$base/teach/${t.id}'),
              onQuiz: (t) => context.go('$base/quiz?topicId=${t.id}'),
              onNeedConcepts: (t) async {
                final made = await ref
                    .read(studioRepositoryProvider)
                    .mapConcepts(widget.studioId, t.id);
                if (made) {
                  ref.invalidate(studioProvider(widget.studioId));
                  await ref.read(studioProvider(widget.studioId).future);
                }
              },
              onAnswer: (t, correct) => unawaited(
                ref
                    .read(studioRepositoryProvider)
                    .recordQuizResult(
                      studioId: widget.studioId,
                      topicId: t.id,
                      correct: correct,
                    )
                    .catchError((Object _) {}),
              ),
            );
          },
        );
  }
}
