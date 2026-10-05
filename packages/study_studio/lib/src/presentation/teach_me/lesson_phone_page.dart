import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../domain/entities/topic.dart';
import '../mobile/lesson_mobile.dart';
import '../mobile/mobile_header.dart';
import '../mobile/mobile_motion.dart';
import '../mobile/mobile_style.dart';

/// The phone's lesson: loads the topic, records answers and "Got it", and
/// opens Ask AI on it.
class LessonPhonePage extends ConsumerWidget {
  const LessonPhonePage({
    super.key,
    required this.studioId,
    required this.topicId,
  });

  final String studioId;
  final String topicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = SmColors.of(context);
    final base = '/study/$studioId';
    Widget plain(Widget child) => Scaffold(
      backgroundColor: c.background,
      body: SmHeaderPage(
        header: SmHeader(title: '', onBack: () => context.go(base)),
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
              'Couldn’t open this lesson',
              style: SmText.of(context).small.copyWith(fontSize: 13),
            ),
          ),
          data: (studio) {
            final topics = studio.topics;
            final i = topics.indexWhere((t) => t.id == topicId);
            if (i < 0) {
              return plain(
                Text(
                  'This topic is gone',
                  style: SmText.of(context).small.copyWith(fontSize: 13),
                ),
              );
            }
            final topic = topics[i];
            final next = i + 1 < topics.length ? topics[i + 1] : null;
            final repo = ref.read(studioRepositoryProvider);
            return LessonMobile(
              // A new topic starts at the top.
              key: ValueKey(topic.id),
              topic: topic,
              studioTitle: studio.title,
              number: i + 1,
              total: topics.length,
              hasNext: next != null,
              onBack: () => context.go(base),
              onAsk: () => showLessonAsk(context, ref, topic),
              onAnswer: (correct) => unawaited(
                repo
                    .recordQuizResult(
                      studioId: studioId,
                      topicId: topic.id,
                      correct: correct,
                    )
                    .catchError((Object _) {}),
              ),
              onDone: () {
                unawaited(
                  repo
                      .markReviewed(studioId, topic.id)
                      .then((_) => ref.invalidate(studioProvider(studioId)))
                      .catchError((Object _) {}),
                );
                context.go(next == null ? base : '$base/teach/${next.id}');
              },
            );
          },
        );
  }
}

/// Ask AI about [topic], in a sheet over the lesson.
Future<void> showLessonAsk(BuildContext context, WidgetRef ref, Topic topic) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _AskSheet(
      topic: topic,
      ask: (text) =>
          ref.read(aiServiceProvider).teach(topic: topic, message: text),
    ),
  );
}

class _AskSheet extends StatefulWidget {
  const _AskSheet({required this.topic, required this.ask});

  final Topic topic;
  final Future<String> Function(String text) ask;

  @override
  State<_AskSheet> createState() => _AskSheetState();
}

class _AskSheetState extends State<_AskSheet> {
  final _input = TextEditingController();
  final _turns = <(String, bool)>[];
  var _thinking = false;

  static const _ideas = [
    'Explain it more simply',
    'Give me another example',
    'How does this show up in an exam?',
  ];

  Future<void> _send(String text) async {
    final q = text.trim();
    if (q.isEmpty || _thinking) return;
    SmHaptics.tap();
    setState(() {
      _turns.add((q, true));
      _thinking = true;
      _input.clear();
    });
    String reply;
    try {
      reply = await widget.ask(q);
    } on Object {
      reply = 'That didn’t go through. Try again in a moment.';
    }
    if (!mounted) return;
    setState(() {
      _turns.add((reply, false));
      _thinking = false;
    });
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.78,
          ),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF2A2B2B) : Colors.white,
            borderRadius: BorderRadius.circular(26),
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
                  margin: const EdgeInsets.only(top: 10, bottom: 10),
                  decoration: BoxDecoration(
                    color: c.line,
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 18,
                      color: c.accentSoft,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ask about ${widget.topic.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.title,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                  children: [
                    if (_thinking)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Thinking…',
                          style: t.small.copyWith(color: c.accentSoft),
                        ),
                      ),
                    for (final (text, mine) in _turns.reversed)
                      SmAppear(
                        index: 0,
                        child: Align(
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: mine
                                ? const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 9,
                                  )
                                : EdgeInsets.zero,
                            constraints: const BoxConstraints(maxWidth: 300),
                            decoration: mine
                                ? BoxDecoration(
                                    color: c.raised,
                                    borderRadius: BorderRadius.circular(18),
                                  )
                                : null,
                            child: Text(
                              text,
                              style: mine
                                  ? t.body.copyWith(fontSize: 14)
                                  : TextStyle(
                                      fontFamily: SmFonts.reading,
                                      fontSize: 15.5,
                                      height: 1.6,
                                      color: c.text,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    if (_turns.isEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final idea in _ideas)
                            SmPressable(
                              semanticLabel: idea,
                              onTap: () => _send(idea),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: c.raised,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  idea,
                                  style: t.small.copyWith(
                                    fontSize: 12.5,
                                    color: c.text,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                child: Container(
                  padding: const EdgeInsets.only(left: 14, right: 5),
                  decoration: BoxDecoration(
                    color: c.raised,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          minLines: 1,
                          maxLines: 4,
                          textCapitalization: TextCapitalization.sentences,
                          onSubmitted: _send,
                          style: t.body.copyWith(fontSize: 14),
                          cursorColor: c.accent,
                          decoration: InputDecoration(
                            isDense: true,
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            hintText: 'Ask anything about this topic',
                            hintStyle: t.body.copyWith(
                              fontSize: 14,
                              color: c.hint,
                            ),
                          ),
                        ),
                      ),
                      SmPressable(
                        semanticLabel: 'Send',
                        haptic: () {},
                        scale: 0.9,
                        onTap: () => _send(_input.text),
                        child: Container(
                          width: 38,
                          height: 38,
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          decoration: BoxDecoration(
                            color: c.accent,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_upward_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
