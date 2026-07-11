import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/studio.dart';
import '../format.dart';

class StudioCard extends StatelessWidget {
  const StudioCard({super.key, required this.studio});

  final Studio studio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mastery = (studio.overallMastery * 100).round();

    return CockpitCard(
      onTap: () => context.go('/study/${studio.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(studio.title, style: theme.textTheme.titleMedium),
                    Text(
                      studio.subject,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$v — coming soon')),
                ),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'Rename', child: Text('Rename')),
                  PopupMenuItem(value: 'Duplicate', child: Text('Duplicate')),
                  PopupMenuItem(value: 'Export notes', child: Text('Export notes')),
                  PopupMenuItem(value: 'Rebuild Studio', child: Text('Rebuild Studio')),
                  PopupMenuItem(value: 'Delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.lg),
          Wrap(
            spacing: CockpitSpacing.xl,
            runSpacing: CockpitSpacing.md,
            children: [
              StatTile(value: '${studio.topicCount}', label: 'Topics'),
              StatTile(value: '${studio.flashcardCount}', label: 'Flashcards'),
              StatTile(value: '${studio.quizCount}', label: 'Quiz Qs'),
              StatTile(value: '${studio.weakTopics.length}', label: 'Weak'),
            ],
          ),
          const SizedBox(height: CockpitSpacing.lg),
          MasteryBar(value: studio.overallMastery, label: '$mastery% mastered'),
          const SizedBox(height: CockpitSpacing.md),
          Row(
            children: [
              Icon(Icons.schedule, size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: CockpitSpacing.xs),
              Text(
                'Last studied: ${relativeDay(studio.lastStudied)}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => context.go('/study/${studio.id}'),
                child: const Text('Continue'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
