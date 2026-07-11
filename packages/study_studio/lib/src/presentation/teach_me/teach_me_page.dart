import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../domain/entities/studio.dart';
import '../../domain/entities/topic.dart';

/// Screen 6 — Teach Me.
///
/// Not a chatbot with a PDF: an interactive AI *textbook* built from the Study
/// Object. Structured lesson cards and callouts present the topic; a grounded
/// chat is woven in for clarification. Calm, spacious, Outfit typography.
class TeachMePage extends ConsumerStatefulWidget {
  const TeachMePage({super.key, required this.studioId, required this.topicId});
  final String studioId;
  final String topicId;

  @override
  ConsumerState<TeachMePage> createState() => _TeachMePageState();
}

class _Msg {
  _Msg(this.text, {required this.fromUser});
  final String text;
  final bool fromUser;
}

class _TeachMePageState extends ConsumerState<TeachMePage> {
  final _controller = TextEditingController();
  final _askFocus = FocusNode();
  final _messages = <_Msg>[];
  bool _thinking = false;
  bool _lessonOpen = true;

  static const _suggestions = [
    "Explain like I'm 10",
    'Give another example',
    'Why does this matter?',
    'Compare with a related topic',
  ];

  Future<void> _send(Topic topic, String text) async {
    if (text.trim().isEmpty || _thinking) return;
    setState(() {
      _messages.add(_Msg(text, fromUser: true));
      _thinking = true;
      _controller.clear();
    });
    final reply =
        await ref.read(aiServiceProvider).teach(topic: topic, message: text);
    if (!mounted) return;
    setState(() {
      _messages.add(_Msg(reply, fromUser: false));
      _thinking = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _askFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(studioProvider(widget.studioId));
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (studio) {
                final i = studio.topics.indexWhere((t) => t.id == widget.topicId);
                if (i < 0) {
                  return const Center(child: Text('Topic not found'));
                }
                return _buildLesson(context, studio, i);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLesson(BuildContext context, Studio studio, int index) {
    final topics = studio.topics;
    final topic = topics[index];
    final total = topics.length;
    final base = '/study/${studio.id}';
    final prev = index > 0 ? topics[index - 1] : null;
    final next = index < total - 1 ? topics[index + 1] : null;
    final related = [
      for (final id in topic.relatedTopicIds)
        ...topics.where((t) => t.id == id),
    ];

    return Column(
      children: [
        _Header(
          studioTitle: studio.title,
          lessonNumber: index + 1,
          total: total,
          onBack: () => context.go(base),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              CockpitSpacing.lg,
              CockpitSpacing.md,
              CockpitSpacing.lg,
              CockpitSpacing.xxl,
            ),
            children: [
              _Hero(
                topic: topic,
                onStart: () {
                  setState(() => _lessonOpen = true);
                },
                onAsk: () => _askFocus.requestFocus(),
              ),
              const SizedBox(height: CockpitSpacing.xl),
              _LessonCard(
                topic: topic,
                open: _lessonOpen,
                onToggle: () => setState(() => _lessonOpen = !_lessonOpen),
              ),
              const SizedBox(height: CockpitSpacing.xl),
              _AskAi(
                controller: _controller,
                focusNode: _askFocus,
                suggestions: _suggestions,
                messages: _messages,
                thinking: _thinking,
                onSend: (t) => _send(topic, t),
              ),
              const SizedBox(height: CockpitSpacing.xl),
              _ReadyToTest(onStart: () => context.go('$base/quiz?topicId=${topic.id}')),
              if (related.isNotEmpty) ...[
                const SizedBox(height: CockpitSpacing.xl),
                _RelatedConcepts(
                  related: related,
                  onTap: (t) => context.go('$base/teach/${t.id}'),
                ),
              ],
            ],
          ),
        ),
        _LessonNav(
          current: topic.title,
          index: index,
          total: total,
          onPrev: prev == null ? null : () => context.go('$base/teach/${prev.id}'),
          onNext: next == null ? null : () => context.go('$base/teach/${next.id}'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.studioTitle,
    required this.lessonNumber,
    required this.total,
    required this.onBack,
  });
  final String studioTitle;
  final int lessonNumber;
  final int total;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    void soon(String l) => ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$l — coming soon')));

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CockpitSpacing.md,
        CockpitSpacing.sm,
        CockpitSpacing.md,
        CockpitSpacing.sm,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _CircleButton(icon: Icons.arrow_back_ios_new, onTap: onBack),
              const SizedBox(width: CockpitSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      studioTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Row(
                      children: [
                        Icon(Icons.school_rounded, size: 13, color: scheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          'Teach Me',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _CircleButton(
                icon: Icons.bookmark_border,
                onTap: () => soon('Bookmark'),
              ),
              const SizedBox(width: CockpitSpacing.xs),
              _CircleButton(icon: Icons.more_horiz, onTap: () => soon('More')),
            ],
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Row(
            children: [
              Text(
                'Lesson Progress',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              Text(
                '$lessonNumber / $total',
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(CockpitRadii.pill),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : lessonNumber / total,
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

class _Hero extends StatelessWidget {
  const _Hero({required this.topic, required this.onStart, required this.onAsk});
  final Topic topic;
  final VoidCallback onStart;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Current Topic',
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: CockpitSpacing.xs),
        Text(
          topic.title,
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            height: 1.05,
          ),
        ),
        const SizedBox(height: CockpitSpacing.sm),
        Text(
          topic.simpleExplanation,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: CockpitSpacing.lg),
        Row(
          children: [
            _MetaChip(
              icon: Icons.schedule,
              label: 'Estimated reading',
              value: '${topic.estimatedStudyTimeMinutes} minutes',
            ),
            const SizedBox(width: CockpitSpacing.md),
            _MetaChip(
              icon: Icons.bar_chart,
              label: 'Difficulty',
              value: _difficultyLabel(topic.difficulty),
              valueColor: scheme.primary,
            ),
          ],
        ),
        const SizedBox(height: CockpitSpacing.lg),
        Row(
          children: [
            Expanded(
              child: _GradientButton(
                icon: Icons.play_circle_outline,
                label: 'Start Lesson',
                onTap: onStart,
              ),
            ),
            const SizedBox(width: CockpitSpacing.md),
            _OutlineButton(
              icon: Icons.chat_bubble_outline,
              label: 'Ask Anything',
              onTap: onAsk,
            ),
          ],
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.md,
          vertical: CockpitSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(CockpitRadii.md),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: CockpitSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: valueColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Lesson card
// ---------------------------------------------------------------------------

class _LessonCard extends StatelessWidget {
  const _LessonCard({
    required this.topic,
    required this.open,
    required this.onToggle,
  });
  final Topic topic;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    topic.title,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Icon(open ? Icons.expand_less : Icons.expand_more,
                    color: scheme.onSurfaceVariant),
              ],
            ),
          ),
          if (open) ...[
            const SizedBox(height: CockpitSpacing.lg),
            _Pill(icon: Icons.menu_book_rounded, label: 'Definition', color: scheme.primary),
            const SizedBox(height: CockpitSpacing.sm),
            Text(
              topic.definition,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
            const SizedBox(height: CockpitSpacing.lg),
            // "How it works" — detailed explanation + key points in a framed box.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(CockpitSpacing.md),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(CockpitRadii.md),
                border: Border.all(color: scheme.primary.withValues(alpha: 0.12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How it works',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: CockpitSpacing.sm),
                  Text(
                    topic.detailedExplanation,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
                  ),
                  if (topic.examples.isNotEmpty) ...[
                    const SizedBox(height: CockpitSpacing.md),
                    for (final ex in topic.examples)
                      Padding(
                        padding: const EdgeInsets.only(bottom: CockpitSpacing.xs),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.check_circle,
                                size: 15, color: scheme.tertiary),
                            const SizedBox(width: CockpitSpacing.sm),
                            Expanded(
                              child: Text(ex,
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(height: 1.35)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: CockpitSpacing.lg),
            // Callouts.
            _Callout(
              icon: Icons.lightbulb_outline,
              color: scheme.primary,
              title: 'Why is this important?',
              body: topic.whyItMatters,
            ),
            if (topic.memoryHooks.isNotEmpty)
              _Callout(
                icon: Icons.psychology_alt_outlined,
                color: const Color(0xFF30A46C),
                title: 'Remember this',
                body: topic.memoryHooks.first,
              ),
            if (topic.commonMistakes.isNotEmpty)
              _Callout(
                icon: Icons.warning_amber_rounded,
                color: const Color(0xFFF5A623),
                title: 'Common misconception',
                body: topic.commonMistakes.first,
              ),
            if (topic.sources.isNotEmpty)
              _Callout(
                icon: Icons.description_outlined,
                color: scheme.onSurfaceVariant,
                title: 'From your material',
                body: '"${topic.sources.first.snippet}"\n— ${topic.sources.first.fileName}'
                    '${topic.sources.first.page != null ? ', p.${topic.sources.first.page}' : ''}',
              ),
          ],
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CockpitSpacing.sm,
        vertical: CockpitSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(CockpitRadii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: CockpitSpacing.xs),
          Text(
            label,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _Callout extends StatelessWidget {
  const _Callout({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: CockpitSpacing.sm),
      padding: const EdgeInsets.all(CockpitSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(CockpitRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: CockpitSpacing.sm),
              Text(
                title,
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: color, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.xs),
          Text(
            body,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ask AI (woven-in chat)
// ---------------------------------------------------------------------------

class _AskAi extends StatelessWidget {
  const _AskAi({
    required this.controller,
    required this.focusNode,
    required this.suggestions,
    required this.messages,
    required this.thinking,
    required this.onSend,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<String> suggestions;
  final List<_Msg> messages;
  final bool thinking;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.md),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (messages.isNotEmpty) ...[
            for (final m in messages) _ChatLine(msg: m),
            if (thinking) const _ChatLine(msg: null),
            const SizedBox(height: CockpitSpacing.sm),
          ],
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.smart_toy_rounded, size: 20, color: scheme.primary),
              ),
              const SizedBox(width: CockpitSpacing.sm),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    hintText: 'Ask anything about this topic…',
                  ),
                  onSubmitted: onSend,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Voice input — coming soon')),
                ),
                icon: Icon(Icons.mic_none, color: scheme.onSurfaceVariant),
              ),
              _SendButton(onTap: () => onSend(controller.text)),
            ],
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Wrap(
            spacing: CockpitSpacing.sm,
            runSpacing: CockpitSpacing.sm,
            children: [
              for (final s in suggestions)
                InkWell(
                  onTap: () => onSend(s),
                  borderRadius: BorderRadius.circular(CockpitRadii.pill),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CockpitSpacing.md,
                      vertical: CockpitSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(CockpitRadii.pill),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Text(s, style: theme.textTheme.labelMedium),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChatLine extends StatelessWidget {
  const _ChatLine({required this.msg});
  final _Msg? msg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fromUser = msg?.fromUser ?? false;
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: CockpitSpacing.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.md,
          vertical: CockpitSpacing.sm,
        ),
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: fromUser ? scheme.primary : scheme.surface,
          borderRadius: BorderRadius.circular(CockpitRadii.md),
          border: fromUser ? null : Border.all(color: scheme.outlineVariant),
        ),
        child: Text(
          msg?.text ?? '…',
          style: theme.textTheme.bodySmall?.copyWith(
            height: 1.4,
            color: fromUser ? scheme.onPrimary : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final violet = _shiftHue(scheme.primary, -28);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [scheme.secondary, violet]),
        ),
        child: const Icon(Icons.send, color: Colors.white, size: 18),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ready to test
// ---------------------------------------------------------------------------

class _ReadyToTest extends StatelessWidget {
  const _ReadyToTest({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        gradient: LinearGradient(
          colors: [
            scheme.primary.withValues(alpha: 0.10),
            scheme.secondary.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ready to test yourself?',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Check what stuck with a quick quiz.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: CockpitSpacing.md),
          _GradientButton(
            icon: Icons.quiz_outlined,
            label: 'Start Quiz',
            onTap: onStart,
            expand: false,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Related concepts
// ---------------------------------------------------------------------------

class _RelatedConcepts extends StatelessWidget {
  const _RelatedConcepts({required this.related, required this.onTap});
  final List<Topic> related;
  final ValueChanged<Topic> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Related Concepts',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: CockpitSpacing.md),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: related.length,
            separatorBuilder: (_, _) => const SizedBox(width: CockpitSpacing.md),
            itemBuilder: (context, i) => _RelatedCard(
              topic: related[i],
              nextUp: i == 0,
              onTap: () => onTap(related[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _RelatedCard extends StatelessWidget {
  const _RelatedCard({
    required this.topic,
    required this.nextUp,
    required this.onTap,
  });
  final Topic topic;
  final bool nextUp;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CockpitRadii.md),
      child: Container(
        width: 120,
        padding: const EdgeInsets.all(CockpitSpacing.md),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(CockpitRadii.md),
          border: Border.all(
            color: nextUp
                ? scheme.primary.withValues(alpha: 0.4)
                : scheme.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (nextUp)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(CockpitRadii.sm),
                ),
                child: Text(
                  'Next Up',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 9,
                  ),
                ),
              )
            else
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.account_tree_outlined,
                    size: 18, color: scheme.primary),
              ),
            const Spacer(),
            Text(
              topic.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700, height: 1.1),
            ),
            const SizedBox(height: 2),
            Text(
              '${topic.estimatedStudyTimeMinutes} min',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Lesson navigation
// ---------------------------------------------------------------------------

class _LessonNav extends StatelessWidget {
  const _LessonNav({
    required this.current,
    required this.index,
    required this.total,
    required this.onPrev,
    required this.onNext,
  });
  final String current;
  final int index;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        CockpitSpacing.md,
        CockpitSpacing.sm,
        CockpitSpacing.md,
        CockpitSpacing.md,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          _NavButton(
            icon: Icons.arrow_back,
            label: 'Previous',
            onTap: onPrev,
            trailing: false,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  current,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${index + 1} of $total',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          _NavButton(
            icon: Icons.arrow_forward,
            label: 'Next',
            onTap: onNext,
            trailing: true,
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.trailing,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onTap != null;
    final color = enabled ? scheme.onSurface : scheme.onSurfaceVariant.withValues(alpha: 0.4);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.md,
          vertical: CockpitSpacing.sm,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(CockpitRadii.pill),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!trailing) Icon(icon, size: 16, color: color),
            if (!trailing) const SizedBox(width: CockpitSpacing.xs),
            Text(label, style: theme.textTheme.labelMedium?.copyWith(color: color)),
            if (trailing) const SizedBox(width: CockpitSpacing.xs),
            if (trailing) Icon(icon, size: 16, color: color),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: theme.colorScheme.onSurface),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.expand = true,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final violet = _shiftHue(scheme.primary, -28);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CockpitRadii.pill),
            gradient: LinearGradient(colors: [scheme.secondary, violet]),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: expand ? 0 : CockpitSpacing.lg,
            ),
            child: SizedBox(
              height: 48,
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.white, size: 18),
                  const SizedBox(width: CockpitSpacing.sm),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CockpitRadii.pill),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
            child: SizedBox(
              height: 48,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: scheme.onSurface),
                  const SizedBox(width: CockpitSpacing.sm),
                  Text(label,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _difficultyLabel(int difficulty) {
  if (difficulty <= 2) return 'Beginner';
  if (difficulty == 3) return 'Intermediate';
  return 'Advanced';
}

/// Rotates a color's hue to build a same-family gradient companion.
Color _shiftHue(Color base, double degrees) {
  final hsl = HSLColor.fromColor(base);
  final h = (hsl.hue + degrees) % 360;
  return hsl.withHue(h < 0 ? h + 360 : h).toColor();
}
