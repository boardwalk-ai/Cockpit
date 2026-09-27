import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../widgets/studio_scaffold.dart';

class ProgressPage extends ConsumerWidget {
  const ProgressPage({super.key, required this.studioId});
  final String studioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(studioProvider(studioId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Progress'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/study/$studioId'),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => context.go('/study/$studioId/mastery-report'),
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Mastery Report'),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (studio) {
          final sorted = [...studio.topics]
            ..sort((a, b) => a.mastery.compareTo(b.mastery));
          if (isMobilePlatform(context)) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Your progress', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 16),
                CockpitCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Overall mastery',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      MasteryBar(value: studio.overallMastery),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 24,
                        runSpacing: 16,
                        children: [
                          StatTile(
                            value: '${studio.topicCount}',
                            label: 'Topics',
                          ),
                          StatTile(
                            value: '${studio.weakTopics.length}',
                            label: 'Weak',
                          ),
                          StatTile(
                            value:
                                '${studio.topics.where((t) => t.mastery >= .8).length}',
                            label: 'Strong',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const SectionHeader(title: 'By topic (weakest first)'),
                for (final topic in sorted)
                  Card(
                    child: InkWell(
                      onTap: () =>
                          context.go('/study/$studioId/topics/${topic.id}'),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              topic.title,
                              style: theme.textTheme.titleMedium,
                            ),
                            if (topic.isWeak)
                              Text(
                                'Weak',
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            const SizedBox(height: 12),
                            MasteryBar(value: topic.mastery),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.all(CockpitSpacing.lg),
            children: [
              CockpitCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Overall mastery', style: theme.textTheme.titleSmall),
                    const SizedBox(height: CockpitSpacing.md),
                    MasteryBar(value: studio.overallMastery),
                    const SizedBox(height: CockpitSpacing.md),
                    Row(
                      children: [
                        StatTile(
                          value: '${studio.topicCount}',
                          label: 'Topics',
                        ),
                        const SizedBox(width: CockpitSpacing.xl),
                        StatTile(
                          value: '${studio.weakTopics.length}',
                          label: 'Weak',
                        ),
                        const SizedBox(width: CockpitSpacing.xl),
                        StatTile(
                          value:
                              '${studio.topics.where((t) => t.mastery >= 0.8).length}',
                          label: 'Strong',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: CockpitSpacing.xl),
              const SectionHeader(title: 'By topic (weakest first)'),
              for (final t in sorted)
                Padding(
                  padding: const EdgeInsets.only(bottom: CockpitSpacing.lg),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(CockpitRadii.md),
                    onTap: () => context.go('/study/$studioId/topics/${t.id}'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                t.title,
                                style: theme.textTheme.bodyLarge,
                              ),
                            ),
                            if (t.isWeak)
                              Text(
                                'Weak',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: CockpitSpacing.xs),
                        MasteryBar(value: t.mastery),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
