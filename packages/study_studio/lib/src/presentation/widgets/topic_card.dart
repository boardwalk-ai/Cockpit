import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/topic.dart';

class TopicCard extends StatelessWidget {
  const TopicCard({super.key, required this.topic});

  final Topic topic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CockpitCard(
      onTap: () => context.go('/study/${topic.studioId}/topics/${topic.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(topic.title, style: theme.textTheme.titleSmall)),
              if (topic.isWeak)
                const TagChip(label: 'Weak', icon: Icons.warning_amber_rounded),
            ],
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Row(
            children: [
              Text('Difficulty', style: theme.textTheme.labelSmall),
              const SizedBox(width: CockpitSpacing.xs),
              StarMeter(value: topic.difficulty),
              const SizedBox(width: CockpitSpacing.lg),
              Text('Importance', style: theme.textTheme.labelSmall),
              const SizedBox(width: CockpitSpacing.xs),
              StarMeter(value: topic.importance),
            ],
          ),
          const SizedBox(height: CockpitSpacing.md),
          MasteryBar(value: topic.mastery, label: 'Mastery'),
          if (topic.relatedTopicIds.isNotEmpty) ...[
            const SizedBox(height: CockpitSpacing.sm),
            Text(
              '${topic.relatedTopicIds.length} related topic(s)',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
