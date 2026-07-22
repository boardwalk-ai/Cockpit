import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../widgets/studio_palette.dart';
import '../widgets/studio_scaffold.dart';

/// Screen 14 — Ask AI.
///
/// Uses presentation-only mock data, as requested by the internship brief.
/// The layout follows the supplied design with a conversation area, AI context,
/// visual references, performance insights, prompts, and a message composer.
class AskAiPage extends ConsumerStatefulWidget {
  const AskAiPage({required this.studioId, super.key});

  final String studioId;

  @override
  ConsumerState<AskAiPage> createState() => _AskAiPageState();
}

class _AskAiPageState extends ConsumerState<AskAiPage> {
  final TextEditingController _controller = TextEditingController();

  String _question = 'Why is Routing considered difficult?';

  void _submitQuestion([String? prompt]) {
    final value = (prompt ?? _controller.text).trim();

    if (value.isEmpty) return;

    setState(() {
      _question = value;
      _controller.clear();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final studioTitle =
        ref.watch(studioProvider(widget.studioId)).valueOrNull?.title ??
        'Study Studio';

    return StudioShell(
      selectedIndex: 1,
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 1000;

            return Padding(
              padding: EdgeInsets.fromLTRB(
                desktop ? 32 : 16,
                16,
                desktop ? 32 : 16,
                16,
              ),
              child: ContentColumn(
                maxWidth: 1240,
                child: Column(
                  children: [
                    _Header(studioId: widget.studioId, title: studioTitle),
                    const SizedBox(height: CockpitSpacing.md),
                    Expanded(
                      child: desktop
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 7,
                                  child: _ConversationPanel(
                                    question: _question,
                                    controller: _controller,
                                    onSubmit: _submitQuestion,
                                  ),
                                ),
                                const SizedBox(width: CockpitSpacing.lg),
                                const SizedBox(
                                  width: 310,
                                  child: _ContextSidebar(),
                                ),
                              ],
                            )
                          : _ConversationPanel(
                              question: _question,
                              controller: _controller,
                              onSubmit: _submitQuestion,
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.studioId, required this.title});

  final String studioId;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      children: [
        _CircleButton(
          icon: Icons.arrow_back_ios_new_rounded,
          onTap: () => context.go('/study/$studioId'),
        ),
        const SizedBox(width: CockpitSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.auto_awesome, size: 15, color: scheme.primary),
                  const SizedBox(width: 5),
                  Text(
                    'Ask AI',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Text(
                'Powered by your Study Studio',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        _CircleButton(icon: Icons.bookmark_border_rounded, onTap: () {}),
        const SizedBox(width: CockpitSpacing.sm),
        _CircleButton(icon: Icons.more_horiz_rounded, onTap: () {}),
      ],
    );
  }
}

class _ConversationPanel extends StatelessWidget {
  const _ConversationPanel({
    required this.question,
    required this.controller,
    required this.onSubmit,
  });

  final String question;
  final TextEditingController controller;
  final ValueChanged<String?> onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: CockpitSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WelcomeCard(onPrompt: onSubmit),
                const SizedBox(height: CockpitSpacing.lg),
                _UserQuestion(question: question),
                const SizedBox(height: CockpitSpacing.md),
                const _AiAnswerCard(),
                const SizedBox(height: CockpitSpacing.lg),
                _FollowUpPrompts(onPrompt: onSubmit),
              ],
            ),
          ),
        ),
        const SizedBox(height: CockpitSpacing.sm),
        _MessageComposer(
          controller: controller,
          onSubmit: () => onSubmit(null),
        ),
      ],
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.onPrompt});

  final ValueChanged<String?> onPrompt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final prompts = [
      (Icons.menu_book_rounded, StudyPalette.violet, 'Explain\nRouting'),
      (
        Icons.compare_arrows_rounded,
        StudyPalette.success,
        'Compare\nTCP/IP and OSI',
      ),
      (Icons.lightbulb_rounded, StudyPalette.info, 'Give me an\nexample'),
      (
        Icons.help_rounded,
        StudyPalette.danger,
        'Why did I miss\nthis question?',
      ),
    ];

    return _SurfaceCard(
      child: Column(
        children: [
          Row(
            children: [
              const _RobotAvatar(size: 68),
              const SizedBox(width: CockpitSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'What would you like to understand?',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'I can explain concepts, solve doubts, compare ideas, '
                      'create examples, and much more!',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 620;

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: prompts.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: narrow ? 2 : 4,
                  mainAxisSpacing: CockpitSpacing.sm,
                  crossAxisSpacing: CockpitSpacing.sm,
                  mainAxisExtent: 128,
                ),
                itemBuilder: (context, index) {
                  final prompt = prompts[index];

                  return _PromptCard(
                    icon: prompt.$1,
                    color: prompt.$2,
                    label: prompt.$3,
                    onTap: () => onPrompt(prompt.$3.replaceAll('\n', ' ')),
                  );
                },
              );
            },
          ),
          const SizedBox(height: CockpitSpacing.md),
          TextField(
            onSubmitted: onPrompt,
            decoration: InputDecoration(
              hintText: 'Ask anything about your course...',
              prefixIcon: const Icon(Icons.attach_file_rounded),
              suffixIcon: Container(
                margin: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mic_none_rounded, color: Colors.white),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CockpitRadii.pill),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CockpitRadii.pill),
                borderSide: BorderSide(
                  color: scheme.primary.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(CockpitRadii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        child: Ink(
          padding: const EdgeInsets.all(CockpitSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CockpitRadii.md),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: CockpitSpacing.sm),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserQuestion extends StatelessWidget {
  const _UserQuestion({required this.question});

  final String question;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CircleAvatar(radius: 21, child: Icon(Icons.person_rounded)),
        const SizedBox(width: CockpitSpacing.sm),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: CockpitSpacing.lg,
                  vertical: CockpitSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(CockpitRadii.lg),
                ),
                child: Text(
                  question,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '9:41 AM',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AiAnswerCard extends StatelessWidget {
  const _AiAnswerCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _RobotAvatar(size: 46),
              const SizedBox(width: CockpitSpacing.sm),
              Expanded(
                child: Text(
                  'Great question! Routing is difficult because it involves '
                  'multiple layers of decision-making and dynamic networks.',
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                ),
              ),
            ],
          ),
          const Divider(height: CockpitSpacing.xl),
          _SectionTitle(
            icon: Icons.auto_awesome,
            title: 'Explanation',
            color: scheme.primary,
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Text(
            'Routing requires understanding how data moves between networks, '
            'choosing the best path based on metrics, and handling changes in '
            'network topology. Unlike switching within a local network, routing '
            'depends on logical addressing, routing tables, protocols, and policies.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: CockpitSpacing.lg),
          const _MaterialsSection(),
          const SizedBox(height: CockpitSpacing.lg),
          const _RelatedConcepts(),
          const SizedBox(height: CockpitSpacing.lg),
          const _PracticeGrid(),
          const Divider(height: CockpitSpacing.xl),
          Row(
            children: [
              Text(
                '9:41 AM',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.thumb_up_alt_outlined, size: 18),
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.thumb_down_alt_outlined, size: 18),
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.copy_rounded, size: 18),
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.more_horiz_rounded, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MaterialsSection extends StatelessWidget {
  const _MaterialsSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          icon: Icons.library_books_outlined,
          title: 'From Your Materials',
          color: StudyPalette.violet,
        ),
        const SizedBox(height: CockpitSpacing.sm),
        _SourceTile(
          icon: Icons.menu_book_rounded,
          color: StudyPalette.success,
          title: 'Lecture 5 – Routing Basics',
          subtitle:
              '“Routers make decisions based on routing tables and metrics.”',
          tag: 'Slide 14',
        ),
        const SizedBox(height: CockpitSpacing.sm),
        _SourceTile(
          icon: Icons.auto_stories_rounded,
          color: StudyPalette.violet,
          title: 'Chapter 8 – Network Layer',
          subtitle:
              '“Routing protocols exchange information to determine the best path.”',
          tag: 'Page 212',
        ),
        const SizedBox(height: CockpitSpacing.sm),
        _SourceTile(
          icon: Icons.help_rounded,
          color: StudyPalette.danger,
          title: 'Quiz – Question 7 Explanation',
          subtitle: '“Routing uses Layer 3 information to forward packets.”',
          tag: 'Review',
        ),
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.tag,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String tag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        borderRadius: BorderRadius.circular(CockpitRadii.md),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: CockpitSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          Chip(label: Text(tag)),
        ],
      ),
    );
  }
}

class _RelatedConcepts extends StatelessWidget {
  const _RelatedConcepts();

  @override
  Widget build(BuildContext context) {
    const concepts = [
      'Subnetting',
      'TCP/IP Model',
      'Routers',
      'Routing Protocols',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          icon: Icons.hub_rounded,
          title: 'Related Concepts',
          color: StudyPalette.success,
        ),
        const SizedBox(height: CockpitSpacing.sm),
        Wrap(
          spacing: CockpitSpacing.sm,
          runSpacing: CockpitSpacing.sm,
          children: [
            for (final concept in concepts)
              ActionChip(
                avatar: const Icon(Icons.hub_outlined, size: 16),
                label: Text(concept),
                onPressed: () {},
              ),
          ],
        ),
      ],
    );
  }
}

class _PracticeGrid extends StatelessWidget {
  const _PracticeGrid();

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        Icons.school_rounded,
        StudyPalette.violet,
        'Teach Me',
        'Deep dive into topic',
      ),
      (
        Icons.style_rounded,
        StudyPalette.warning,
        'Flashcards',
        'Review key points',
      ),
      (
        Icons.help_rounded,
        StudyPalette.success,
        'Quiz Me',
        'Test understanding',
      ),
      (
        Icons.track_changes_rounded,
        StudyPalette.danger,
        'Scenario Mode',
        'Apply in situations',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          icon: Icons.fitness_center_rounded,
          title: 'Suggested Practice',
          color: StudyPalette.violet,
        ),
        const SizedBox(height: CockpitSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: constraints.maxWidth < 560 ? 2 : 4,
                mainAxisSpacing: CockpitSpacing.sm,
                crossAxisSpacing: CockpitSpacing.sm,
                mainAxisExtent: 110,
              ),
              itemBuilder: (context, index) {
                final item = items[index];

                return _PracticeCard(
                  icon: item.$1,
                  color: item.$2,
                  title: item.$3,
                  subtitle: item.$4,
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _PracticeCard extends StatelessWidget {
  const _PracticeCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(CockpitRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const Spacer(),
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _FollowUpPrompts extends StatelessWidget {
  const _FollowUpPrompts({required this.onPrompt});

  final ValueChanged<String?> onPrompt;

  @override
  Widget build(BuildContext context) {
    const prompts = [
      'Show me an animation',
      'Give another example',
      'Explain simply',
      'Compare with TCP/IP',
      'Quiz me on this',
      'Create flashcards',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Try asking follow-up questions',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: CockpitSpacing.sm),
        Wrap(
          spacing: CockpitSpacing.sm,
          runSpacing: CockpitSpacing.sm,
          children: [
            for (final prompt in prompts)
              ActionChip(
                avatar: const Icon(Icons.auto_awesome, size: 15),
                label: Text(prompt),
                onPressed: () => onPrompt(prompt),
              ),
          ],
        ),
      ],
    );
  }
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({required this.controller, required this.onSubmit});

  final TextEditingController controller;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        _CircleButton(icon: Icons.add_rounded, onTap: () {}),
        const SizedBox(width: CockpitSpacing.sm),
        Expanded(
          child: TextField(
            controller: controller,
            onSubmitted: (_) => onSubmit(),
            decoration: InputDecoration(
              hintText: 'Ask anything about your course...',
              suffixIcon: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mic_none_rounded),
                  SizedBox(width: CockpitSpacing.md),
                  Icon(Icons.camera_alt_outlined),
                  SizedBox(width: CockpitSpacing.md),
                ],
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CockpitRadii.pill),
              ),
            ),
          ),
        ),
        const SizedBox(width: CockpitSpacing.sm),
        Material(
          color: scheme.primary,
          shape: const CircleBorder(),
          child: IconButton(
            onPressed: onSubmit,
            icon: const Icon(Icons.send_rounded, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _ContextSidebar extends StatelessWidget {
  const _ContextSidebar();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle(
                  icon: Icons.psychology_outlined,
                  title: 'AI Context',
                  color: StudyPalette.violet,
                ),
                const SizedBox(height: CockpitSpacing.md),
                const Text(
                  'Current Focus',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: CockpitSpacing.sm),
                const _InfoRow(
                  icon: Icons.router_rounded,
                  color: StudyPalette.violet,
                  title: 'Routing',
                ),
                const SizedBox(height: CockpitSpacing.lg),
                const Text(
                  'Using from your Studio',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: CockpitSpacing.sm),
                const _InfoRow(
                  icon: Icons.menu_book_rounded,
                  color: StudyPalette.success,
                  title: 'Lecture 5',
                  subtitle: 'Routing Basics',
                ),
                const _InfoRow(
                  icon: Icons.slideshow_rounded,
                  color: StudyPalette.warning,
                  title: 'Slides 12–18',
                ),
                const _InfoRow(
                  icon: Icons.auto_stories_rounded,
                  color: StudyPalette.violet,
                  title: 'Chapter 8',
                  subtitle: 'Network Layer',
                ),
                const _InfoRow(
                  icon: Icons.trending_up_rounded,
                  color: StudyPalette.danger,
                  title: 'Quiz Results',
                  subtitle: '68% in Routing',
                ),
                const _InfoRow(
                  icon: Icons.style_rounded,
                  color: StudyPalette.info,
                  title: 'Flashcards',
                  subtitle: '42 cards reviewed',
                ),
                const SizedBox(height: CockpitSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {},
                    child: const Text('View All Sources'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: CockpitSpacing.md),
          const _VisualReferenceCard(),
          const SizedBox(height: CockpitSpacing.md),
          const _PerformanceCard(),
        ],
      ),
    );
  }
}

class _VisualReferenceCard extends StatelessWidget {
  const _VisualReferenceCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Visual Reference',
            style: TextStyle(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CockpitSpacing.sm),
          const Text(
            'How Routers Work',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: CockpitSpacing.md),
          Container(
            height: 130,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(CockpitRadii.md),
            ),
            child: CustomPaint(
              painter: _NetworkPainter(
                lineColor: scheme.primary.withValues(alpha: 0.55),
              ),
              child: const Center(child: Icon(Icons.cloud_rounded, size: 46)),
            ),
          ),
          const SizedBox(height: CockpitSpacing.md),
          Text(
            'Key Idea',
            style: TextStyle(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Routers use routing tables to decide the best path based on metrics.',
          ),
        ],
      ),
    );
  }
}

class _PerformanceCard extends StatelessWidget {
  const _PerformanceCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Performance',
            style: TextStyle(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CockpitSpacing.md),
          Row(
            children: [
              SizedBox(
                width: 74,
                height: 74,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: 0.68,
                      strokeWidth: 7,
                      backgroundColor: scheme.primary.withValues(alpha: 0.12),
                    ),
                    const Text(
                      '68%',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: CockpitSpacing.md),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mastery in Routing',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Needs improvement',
                      style: TextStyle(color: StudyPalette.danger),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.lg),
          Text(
            'Common Mistakes',
            style: TextStyle(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CockpitSpacing.sm),
          const Text('• Confusing routing with switching'),
          const Text('• Misunderstanding default gateways'),
          const Text('• Incorrect next hop selection'),
          const SizedBox(height: CockpitSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {},
              child: const Text('Review Mistakes'),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.xs),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: CockpitSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.color,
  });

  final IconData icon;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: CockpitSpacing.sm),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}

class _RobotAvatar extends StatelessWidget {
  const _RobotAvatar({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [scheme.primary, StudyPalette.violetDeep],
        ),
      ),
      child: Icon(
        Icons.smart_toy_rounded,
        color: Colors.white,
        size: size * 0.52,
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: const CircleBorder(),
      child: IconButton(onPressed: onTap, icon: Icon(icon, size: 19)),
    );
  }
}

class _NetworkPainter extends CustomPainter {
  const _NetworkPainter({required this.lineColor});

  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 2;

    final left = Offset(size.width * 0.18, size.height * 0.67);
    final center = Offset(size.width * 0.5, size.height * 0.45);
    final right = Offset(size.width * 0.82, size.height * 0.67);

    canvas.drawLine(left, center, paint);
    canvas.drawLine(center, right, paint);
    canvas.drawLine(left, right, paint);

    canvas.drawCircle(left, 10, paint);
    canvas.drawCircle(right, 10, paint);
  }

  @override
  bool shouldRepaint(covariant _NetworkPainter oldDelegate) {
    return oldDelegate.lineColor != lineColor;
  }
}
