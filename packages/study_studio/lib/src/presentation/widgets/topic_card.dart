import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/topic.dart';
import 'mobile_layout.dart';

class TopicCard extends StatefulWidget {
  const TopicCard({super.key, required this.topic});

  final Topic topic;

  @override
  State<TopicCard> createState() => _TopicCardState();
}

class _TopicCardState extends State<TopicCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topic = widget.topic;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: _isHovered
              ? [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.18),
                    blurRadius: 12,
                    spreadRadius: 0.5,
                  ),
                ]
              : const [],
        ),
        child: CockpitCard(
          onTap: () =>
              context.go('/study/${topic.studioId}/topics/${topic.id}'),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: _isHovered
                  ? theme.colorScheme.primary.withValues(alpha: 0.035)
                  : Colors.transparent,
            ),
            padding: const EdgeInsets.all(CockpitSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        topic.title,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    if (topic.isWeak)
                      const TagChip(
                        label: 'Weak',
                        icon: Icons.warning_amber_rounded,
                      ),
                  ],
                ),
                const SizedBox(height: CockpitSpacing.sm),
                MobileWrap(
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
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
