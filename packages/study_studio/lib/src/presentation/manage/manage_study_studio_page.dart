import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/studio_scaffold.dart';

/// Screen 15 — Manage Study Studio.
///
/// Uses presentation-only mock data and follows the supplied design:
/// studio summary, material upload, AI preview, timeline, merge preview,
/// export tools, AI settings, and the final update action.
class ManageStudyStudioPage extends StatefulWidget {
  const ManageStudyStudioPage({required this.studioId, super.key});

  final String studioId;

  @override
  State<ManageStudyStudioPage> createState() => _ManageStudyStudioPageState();
}

class _ManageStudyStudioPageState extends State<ManageStudyStudioPage> {
  bool automaticUpdates = true;
  bool autoCreateFlashcards = true;
  bool autoCreateQuizzes = true;
  bool voiceSummaries = false;

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return StudioShell(
      selectedIndex: 1,
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 900;

            return Padding(
              padding: EdgeInsets.fromLTRB(
                desktop ? 32 : 16,
                16,
                desktop ? 32 : 16,
                20,
              ),
              child: ContentColumn(
                maxWidth: 1180,
                child: Column(
                  children: [
                    _Header(studioId: widget.studioId),
                    const SizedBox(height: CockpitSpacing.md),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(
                          bottom: CockpitSpacing.xl,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _StudioOverview(
                              onAddMaterials: () =>
                                  _showMessage('Add materials selected'),
                            ),
                            const SizedBox(height: CockpitSpacing.md),
                            _NumberedSection(
                              number: 1,
                              title: 'Add New Materials',
                              subtitle:
                                  'Upload new content to expand your Study Studio.',
                              child: _UploadMaterials(
                                onTap: (type) => _showMessage('$type selected'),
                              ),
                            ),
                            const SizedBox(height: CockpitSpacing.md),
                            const _NumberedSection(
                              number: 2,
                              title: 'AI Preview',
                              badge: 'Smart Analysis',
                              subtitle:
                                  'Our AI has analyzed your files and predicts these updates.',
                              child: _AiPreview(),
                            ),
                            const SizedBox(height: CockpitSpacing.md),
                            const _NumberedSection(
                              number: 3,
                              title: 'Studio Timeline',
                              subtitle:
                                  'Your Study Studio has evolved over time.',
                              child: _Timeline(),
                            ),
                            const SizedBox(height: CockpitSpacing.md),
                            const _NumberedSection(
                              number: 4,
                              title: 'AI Merge Preview',
                              subtitle:
                                  'New content is intelligently merged with your existing knowledge.',
                              child: _MergePreview(),
                            ),
                            const SizedBox(height: CockpitSpacing.md),
                            desktop
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: _NumberedSection(
                                          number: 5,
                                          title: 'Export & Share',
                                          child: _ExportShare(
                                            onTap: _showMessage,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: CockpitSpacing.md),
                                      Expanded(
                                        child: _NumberedSection(
                                          number: 6,
                                          title: 'AI Settings',
                                          child: _AiSettings(
                                            automaticUpdates: automaticUpdates,
                                            autoCreateFlashcards:
                                                autoCreateFlashcards,
                                            autoCreateQuizzes:
                                                autoCreateQuizzes,
                                            voiceSummaries: voiceSummaries,
                                            onAutomaticUpdates: (value) {
                                              setState(() {
                                                automaticUpdates = value;
                                              });
                                            },
                                            onAutoCreateFlashcards: (value) {
                                              setState(() {
                                                autoCreateFlashcards = value;
                                              });
                                            },
                                            onAutoCreateQuizzes: (value) {
                                              setState(() {
                                                autoCreateQuizzes = value;
                                              });
                                            },
                                            onVoiceSummaries: (value) {
                                              setState(() {
                                                voiceSummaries = value;
                                              });
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    children: [
                                      _NumberedSection(
                                        number: 5,
                                        title: 'Export & Share',
                                        child: _ExportShare(
                                          onTap: _showMessage,
                                        ),
                                      ),
                                      const SizedBox(height: CockpitSpacing.md),
                                      _NumberedSection(
                                        number: 6,
                                        title: 'AI Settings',
                                        child: _AiSettings(
                                          automaticUpdates: automaticUpdates,
                                          autoCreateFlashcards:
                                              autoCreateFlashcards,
                                          autoCreateQuizzes: autoCreateQuizzes,
                                          voiceSummaries: voiceSummaries,
                                          onAutomaticUpdates: (value) {
                                            setState(() {
                                              automaticUpdates = value;
                                            });
                                          },
                                          onAutoCreateFlashcards: (value) {
                                            setState(() {
                                              autoCreateFlashcards = value;
                                            });
                                          },
                                          onAutoCreateQuizzes: (value) {
                                            setState(() {
                                              autoCreateQuizzes = value;
                                            });
                                          },
                                          onVoiceSummaries: (value) {
                                            setState(() {
                                              voiceSummaries = value;
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                            const SizedBox(height: CockpitSpacing.md),
                            _UpdateBanner(
                              onUpdate: () =>
                                  _showMessage('Study Studio update started'),
                            ),
                          ],
                        ),
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
  const _Header({required this.studioId});

  final String studioId;

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
                'Computer Networks Final Exam',
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
                    'Manage Study Studio',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Text(
                'Your AI learning environment grows with your course.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        _CircleButton(icon: Icons.history_rounded, onTap: () {}),
        const SizedBox(width: CockpitSpacing.sm),
        _CircleButton(icon: Icons.more_horiz_rounded, onTap: () {}),
      ],
    );
  }
}

class _StudioOverview extends StatelessWidget {
  const _StudioOverview({required this.onAddMaterials});

  final VoidCallback onAddMaterials;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return _SurfaceCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;

          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: CockpitSpacing.sm,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(CockpitRadii.pill),
                ),
                child: Text(
                  'Current Studio',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: CockpitSpacing.sm),
              Text(
                'Computer Networks\nFinal Exam',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Current Knowledge Base',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: CockpitSpacing.md),
              Wrap(
                spacing: CockpitSpacing.sm,
                runSpacing: CockpitSpacing.sm,
                children: const [
                  _MetricCard(
                    icon: Icons.auto_stories_rounded,
                    color: Color(0xFF8B5CF6),
                    value: '23',
                    label: 'Topics',
                  ),
                  _MetricCard(
                    icon: Icons.style_rounded,
                    color: Color(0xFF10B981),
                    value: '42',
                    label: 'Flashcards',
                  ),
                  _MetricCard(
                    icon: Icons.quiz_rounded,
                    color: Color(0xFFF59E0B),
                    value: '18',
                    label: 'Quizzes',
                  ),
                  _MetricCard(
                    icon: Icons.hub_rounded,
                    color: Color(0xFF7C3AED),
                    value: '126',
                    label: 'Connections',
                  ),
                ],
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _BooksIllustration(),
                const SizedBox(height: CockpitSpacing.md),
                details,
                const SizedBox(height: CockpitSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onAddMaterials,
                    icon: const Icon(Icons.add),
                    label: const Text('Add New Materials'),
                  ),
                ),
              ],
            );
          }

          return Row(
            children: [
              const _BooksIllustration(),
              const SizedBox(width: CockpitSpacing.xl),
              Expanded(child: details),
              const SizedBox(width: CockpitSpacing.lg),
              FilledButton.icon(
                onPressed: onAddMaterials,
                icon: const Icon(Icons.add),
                label: const Text('Add New Materials'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BooksIllustration extends StatelessWidget {
  const _BooksIllustration();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CockpitRadii.xl),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: 0.05),
            scheme.primary.withValues(alpha: 0.20),
          ],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.auto_stories_rounded, size: 78, color: scheme.primary),
          Positioned(
            top: 18,
            right: 20,
            child: Icon(Icons.auto_awesome, color: scheme.primary),
          ),
          Positioned(
            bottom: 18,
            left: 20,
            child: Icon(Icons.bubble_chart_rounded, color: scheme.secondary),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 132,
      padding: const EdgeInsets.all(CockpitSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(CockpitRadii.md),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(width: CockpitSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NumberedSection extends StatelessWidget {
  const _NumberedSection({
    required this.number,
    required this.title,
    required this.child,
    this.subtitle,
    this.badge,
  });

  final int number;
  final String title;
  final String? subtitle;
  final String? badge;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$number. $title',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: CockpitSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CockpitSpacing.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(CockpitRadii.pill),
                  ),
                  child: Text(
                    badge!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: CockpitSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _UploadMaterials extends StatelessWidget {
  const _UploadMaterials({required this.onTap});

  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.picture_as_pdf_rounded, Color(0xFFEF4444), 'PDF'),
      (Icons.slideshow_rounded, Color(0xFFF59E0B), 'Slides'),
      (Icons.description_rounded, Color(0xFF3B82F6), 'Word'),
      (Icons.image_rounded, Color(0xFF10B981), 'Image'),
      (Icons.graphic_eq_rounded, Color(0xFF8B5CF6), 'Audio'),
      (Icons.play_circle_rounded, Color(0xFFEC4899), 'Video'),
      (Icons.sticky_note_2_rounded, Color(0xFFFBBF24), 'Notes'),
    ];

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.35),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        children: [
          Wrap(
            spacing: CockpitSpacing.sm,
            runSpacing: CockpitSpacing.sm,
            alignment: WrapAlignment.center,
            children: [
              for (final item in items)
                _UploadType(
                  icon: item.$1,
                  color: item.$2,
                  label: item.$3,
                  onTap: () => onTap(item.$3),
                ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.md),
          Text(
            'Drag & drop files here or click to browse',
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Supports PDF, PPT, DOCX, Images, Audio, Video and more',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadType extends StatelessWidget {
  const _UploadType({
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
          width: 92,
          height: 82,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CockpitRadii.md),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 27),
              const SizedBox(height: 5),
              Text(
                label,
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

class _AiPreview extends StatelessWidget {
  const _AiPreview();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(CockpitSpacing.md),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(CockpitRadii.md),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 720;

              final file = Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(CockpitRadii.sm),
                    ),
                    child: const Icon(
                      Icons.picture_as_pdf_rounded,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                  const SizedBox(width: CockpitSpacing.sm),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lecture 6.pdf',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text('22.4 MB • 35 pages'),
                    ],
                  ),
                  const SizedBox(width: CockpitSpacing.sm),
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF10B981),
                  ),
                ],
              );

              final predictions = Wrap(
                spacing: CockpitSpacing.sm,
                runSpacing: CockpitSpacing.sm,
                children: const [
                  _Prediction(
                    icon: Icons.auto_stories_rounded,
                    color: Color(0xFF8B5CF6),
                    value: '+4',
                    label: 'Topics',
                  ),
                  _Prediction(
                    icon: Icons.style_rounded,
                    color: Color(0xFF10B981),
                    value: '+18',
                    label: 'Flashcards',
                  ),
                  _Prediction(
                    icon: Icons.quiz_rounded,
                    color: Color(0xFFF59E0B),
                    value: '+9',
                    label: 'Quiz Questions',
                  ),
                  _Prediction(
                    icon: Icons.hub_rounded,
                    color: Color(0xFF7C3AED),
                    value: '+21',
                    label: 'Connections',
                  ),
                ],
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    file,
                    const SizedBox(height: CockpitSpacing.md),
                    Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          color: scheme.primary,
                          size: 17,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Expected Additions',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: CockpitSpacing.sm),
                    predictions,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: file),
                  const Icon(Icons.arrow_forward_rounded),
                  const SizedBox(width: CockpitSpacing.md),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              color: scheme.primary,
                              size: 17,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Expected Additions',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: CockpitSpacing.sm),
                        predictions,
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: CockpitSpacing.sm),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(CockpitSpacing.sm),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(CockpitRadii.sm),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.verified_user_rounded,
                color: Color(0xFF10B981),
                size: 17,
              ),
              SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Your existing data and mastery progress will remain intact.',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Prediction extends StatelessWidget {
  const _Prediction({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(CockpitSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(CockpitRadii.sm),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline();

  @override
  Widget build(BuildContext context) {
    const versions = [
      ('v1.0', 'Sep 12', 'Course\nIntroduction', '12 Topics Added'),
      ('v2.0', 'Sep 28', 'Lecture 3\n& Notes', '+8 Topics Added'),
      ('v3.0', 'Oct 12', 'Midterm\nReview', '+15 Topics Added'),
      ('v4.0', 'Current', 'Lecture 5\n& Labs', '+11 Topics Added'),
      ('vNext', '', 'Lecture 6\n(Preparing)', 'Estimated Updates'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < versions.length; i++) ...[
            _TimelineCard(
              version: versions[i].$1,
              date: versions[i].$2,
              title: versions[i].$3,
              subtitle: versions[i].$4,
              current: i == 3,
              future: i == 4,
            ),
            if (i < versions.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: CockpitSpacing.xs),
                child: Icon(Icons.more_horiz_rounded, color: Color(0xFF8B5CF6)),
              ),
          ],
        ],
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({
    required this.version,
    required this.date,
    required this.title,
    required this.subtitle,
    required this.current,
    required this.future,
  });

  final String version;
  final String date;
  final String title;
  final String subtitle;
  final bool current;
  final bool future;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 150,
      height: 150,
      padding: const EdgeInsets.all(CockpitSpacing.md),
      decoration: BoxDecoration(
        color: current
            ? scheme.primary.withValues(alpha: 0.08)
            : scheme.surface,
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        border: Border.all(
          color: current ? scheme.primary : scheme.outlineVariant,
          style: future ? BorderStyle.solid : BorderStyle.solid,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                version,
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(date, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const Spacer(),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _MergePreview extends StatelessWidget {
  const _MergePreview();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;

        const existing = _MergeCard(
          title: 'Existing Knowledge',
          subtitle: '23 Topics',
          child: _NetworkGraphic(),
        );

        const newLecture = _MergeCard(
          title: 'New Lecture',
          subtitle: 'Lecture 6.pdf',
          child: Icon(
            Icons.description_rounded,
            size: 64,
            color: Color(0xFF8B5CF6),
          ),
        );

        const updated = _MergeCard(
          title: 'Updated Knowledge Graph',
          subtitle: 'More connections • Stronger understanding',
          child: _NetworkGraphic(dense: true),
        );

        if (compact) {
          return const Column(
            children: [
              existing,
              Padding(
                padding: EdgeInsets.all(CockpitSpacing.sm),
                child: Icon(Icons.add_rounded),
              ),
              newLecture,
              Padding(
                padding: EdgeInsets.all(CockpitSpacing.sm),
                child: Icon(Icons.drag_handle_rounded),
              ),
              updated,
            ],
          );
        }

        return const Row(
          children: [
            Expanded(child: existing),
            Padding(
              padding: EdgeInsets.all(CockpitSpacing.md),
              child: Icon(Icons.add_rounded),
            ),
            Expanded(child: newLecture),
            Padding(
              padding: EdgeInsets.all(CockpitSpacing.md),
              child: Icon(Icons.drag_handle_rounded),
            ),
            Expanded(child: updated),
          ],
        );
      },
    );
  }
}

class _MergeCard extends StatelessWidget {
  const _MergeCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      padding: const EdgeInsets.all(CockpitSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Spacer(),
          child,
          const Spacer(),
        ],
      ),
    );
  }
}

class _NetworkGraphic extends StatelessWidget {
  const _NetworkGraphic({this.dense = false});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 150,
      height: 82,
      child: CustomPaint(
        painter: _NetworkPainter(color: scheme.primary, dense: dense),
      ),
    );
  }
}

class _ExportShare extends StatelessWidget {
  const _ExportShare({required this.onTap});

  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.note_rounded, Color(0xFF8B5CF6), 'Export Notes', 'PDF/MD'),
      (Icons.style_rounded, Color(0xFF10B981), 'Export Flashcards', 'Anki/CSV'),
      (
        Icons.share_rounded,
        Color(0xFF3B82F6),
        'Share Study Studio',
        'Invite others',
      ),
      (
        Icons.slideshow_rounded,
        Color(0xFFF59E0B),
        'Generate Study Guide',
        'AI Summary',
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: CockpitSpacing.sm,
        crossAxisSpacing: CockpitSpacing.sm,
        mainAxisExtent: 118,
      ),
      itemBuilder: (context, index) {
        final item = items[index];

        return Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(CockpitRadii.md),
          child: InkWell(
            onTap: () => onTap(item.$3),
            borderRadius: BorderRadius.circular(CockpitRadii.md),
            child: Ink(
              padding: const EdgeInsets.all(CockpitSpacing.sm),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(CockpitRadii.md),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(item.$1, color: item.$2),
                  const Spacer(),
                  Text(
                    item.$3,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(item.$4, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AiSettings extends StatelessWidget {
  const _AiSettings({
    required this.automaticUpdates,
    required this.autoCreateFlashcards,
    required this.autoCreateQuizzes,
    required this.voiceSummaries,
    required this.onAutomaticUpdates,
    required this.onAutoCreateFlashcards,
    required this.onAutoCreateQuizzes,
    required this.onVoiceSummaries,
  });

  final bool automaticUpdates;
  final bool autoCreateFlashcards;
  final bool autoCreateQuizzes;
  final bool voiceSummaries;

  final ValueChanged<bool> onAutomaticUpdates;
  final ValueChanged<bool> onAutoCreateFlashcards;
  final ValueChanged<bool> onAutoCreateQuizzes;
  final ValueChanged<bool> onVoiceSummaries;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SettingTile(
          icon: Icons.notifications_active_outlined,
          title: 'Automatic Updates',
          subtitle: 'Notify me when new content is added',
          value: automaticUpdates,
          onChanged: onAutomaticUpdates,
        ),
        _SettingTile(
          icon: Icons.style_outlined,
          title: 'Auto-create Flashcards',
          subtitle: 'Generate from new materials',
          value: autoCreateFlashcards,
          onChanged: onAutoCreateFlashcards,
        ),
        _SettingTile(
          icon: Icons.quiz_outlined,
          title: 'Auto-create Quizzes',
          subtitle: 'Generate quiz questions automatically',
          value: autoCreateQuizzes,
          onChanged: onAutoCreateQuizzes,
        ),
        _SettingTile(
          icon: Icons.graphic_eq_rounded,
          title: 'Enable Voice Summaries',
          subtitle: 'Create audio summaries for new content',
          value: voiceSummaries,
          onChanged: onVoiceSummaries,
        ),
      ],
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.xs),
      child: Row(
        children: [
          Icon(icon, color: scheme.primary, size: 20),
          const SizedBox(width: CockpitSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({required this.onUpdate});

  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return _SurfaceCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 650;

          final text = Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [scheme.primary, const Color(0xFF7C3AED)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.smart_toy_rounded,
                  color: Colors.white,
                  size: 31,
                ),
              ),
              const SizedBox(width: CockpitSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ready to expand your knowledge?',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Adding new materials will make your Study Studio '
                      'smarter and your understanding deeper.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final button = Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primary, const Color(0xFF9333EA)],
              ),
              borderRadius: BorderRadius.circular(CockpitRadii.md),
            ),
            child: FilledButton.icon(
              onPressed: onUpdate,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(
                  horizontal: CockpitSpacing.xl,
                  vertical: CockpitSpacing.lg,
                ),
              ),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Update Study Studio'),
            ),
          );

          if (compact) {
            return Column(
              children: [
                text,
                const SizedBox(height: CockpitSpacing.md),
                SizedBox(width: double.infinity, child: button),
                const SizedBox(height: 5),
                Text(
                  'This may take a few minutes',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: text),
              const SizedBox(width: CockpitSpacing.xl),
              Column(
                children: [
                  button,
                  const SizedBox(height: 5),
                  Text(
                    'This may take a few minutes',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          );
        },
      ),
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
  const _NetworkPainter({required this.color, required this.dense});

  final Color color;
  final bool dense;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..strokeWidth = 1.5;

    final nodePaint = Paint()..color = color;

    final points = dense
        ? <Offset>[
            Offset(size.width * 0.10, size.height * 0.55),
            Offset(size.width * 0.25, size.height * 0.25),
            Offset(size.width * 0.40, size.height * 0.62),
            Offset(size.width * 0.52, size.height * 0.35),
            Offset(size.width * 0.66, size.height * 0.68),
            Offset(size.width * 0.82, size.height * 0.28),
            Offset(size.width * 0.92, size.height * 0.58),
          ]
        : <Offset>[
            Offset(size.width * 0.12, size.height * 0.55),
            Offset(size.width * 0.32, size.height * 0.25),
            Offset(size.width * 0.50, size.height * 0.65),
            Offset(size.width * 0.70, size.height * 0.30),
            Offset(size.width * 0.88, size.height * 0.55),
          ];

    for (var i = 0; i < points.length - 1; i++) {
      canvas.drawLine(points[i], points[i + 1], linePaint);
    }

    if (dense) {
      canvas.drawLine(points[0], points[3], linePaint);
      canvas.drawLine(points[1], points[4], linePaint);
      canvas.drawLine(points[2], points[5], linePaint);
      canvas.drawLine(points[3], points[6], linePaint);
    }

    for (final point in points) {
      canvas.drawCircle(point, 5, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _NetworkPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.dense != dense;
  }
}
