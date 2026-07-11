import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../domain/entities/studio.dart';
import '../../domain/entities/topic.dart';

class TopicDetailPage extends ConsumerWidget {
  const TopicDetailPage({super.key, required this.studioId, required this.topicId});

  final String studioId;
  final String topicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(studioProvider(studioId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Topic'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/study/$studioId/topics'),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (studio) {
          final topic = studio.topics.firstWhere((t) => t.id == topicId);
          return _Body(studio: studio, topic: topic, ref: ref);
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.studio, required this.topic, required this.ref});
  final Studio studio;
  final Topic topic;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = '/study/${studio.id}';

    Topic? byId(String id) {
      for (final t in studio.topics) {
        if (t.id == id) return t;
      }
      return null;
    }

    return ListView(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      children: [
        Text(topic.title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: CockpitSpacing.sm),
        Wrap(
          spacing: CockpitSpacing.lg,
          runSpacing: CockpitSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Importance ', style: theme.textTheme.labelSmall),
              StarMeter(value: topic.importance),
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Difficulty ', style: theme.textTheme.labelSmall),
              StarMeter(value: topic.difficulty),
            ]),
            TagChip(label: '${(topic.mastery * 100).round()}% mastery'),
          ],
        ),
        const SizedBox(height: CockpitSpacing.lg),
        Wrap(
          spacing: CockpitSpacing.sm,
          runSpacing: CockpitSpacing.sm,
          children: [
            FilledButton.icon(
              onPressed: () => context.go('$base/teach/${topic.id}'),
              icon: const Icon(Icons.school, size: 18),
              label: const Text('Teach Me This'),
            ),
            OutlinedButton.icon(
              onPressed: () => context.go('$base/quiz?topicId=${topic.id}'),
              icon: const Icon(Icons.quiz, size: 18),
              label: const Text('Quiz Me on This'),
            ),
            OutlinedButton.icon(
              onPressed: () => context.go('$base/flashcards?topicId=${topic.id}'),
              icon: const Icon(Icons.style, size: 18),
              label: const Text('Make Flashcards'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                await ref
                    .read(studioRepositoryProvider)
                    .markReviewed(studio.id, topic.id);
                ref.invalidate(studioProvider(studio.id));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Marked as reviewed')),
                  );
                }
              },
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Mark as Reviewed'),
            ),
          ],
        ),
        const Divider(height: CockpitSpacing.xxl),
        _Section(title: 'Definition', body: topic.definition),
        _Section(title: 'Simple Explanation', body: topic.simpleExplanation),
        _Section(title: 'Detailed Explanation', body: topic.detailedExplanation),
        _Section(title: 'Why It Matters', body: topic.whyItMatters),
        if (topic.examples.isNotEmpty)
          _BulletSection(title: 'Examples', items: topic.examples),
        if (topic.commonMistakes.isNotEmpty)
          _BulletSection(title: 'Common Mistakes', items: topic.commonMistakes),
        if (topic.prerequisites.isNotEmpty)
          _BulletSection(title: 'Prerequisites', items: topic.prerequisites),
        if (topic.relatedTopicIds.isNotEmpty) ...[
          const SectionHeader(title: 'Related Topics'),
          Wrap(
            spacing: CockpitSpacing.sm,
            runSpacing: CockpitSpacing.sm,
            children: [
              for (final id in topic.relatedTopicIds)
                if (byId(id) case final t?)
                  TagChip(
                    label: t.title,
                    icon: Icons.link,
                    onTap: () => context.go('$base/topics/${t.id}'),
                  ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.xl),
        ],
        if (topic.sources.isNotEmpty) ...[
          const SectionHeader(title: 'Source References'),
          for (final s in topic.sources)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: Text('${s.fileName}${s.page != null ? ' · p.${s.page}' : ''}'),
              subtitle: Text('"${s.snippet}"'),
              trailing: TextButton(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('View Source: ${s.fileName}')),
                ),
                child: const Text('View Source'),
              ),
            ),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: CockpitSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: CockpitSpacing.xs),
          Text(body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _BulletSection extends StatelessWidget {
  const _BulletSection({required this.title, required this.items});
  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: CockpitSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: CockpitSpacing.xs),
          for (final i in items)
            Padding(
              padding: const EdgeInsets.only(bottom: CockpitSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(child: Text(i, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
