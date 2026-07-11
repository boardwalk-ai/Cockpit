import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/source.dart';

/// Screen 2 — Create a New Study Studio.
///
/// The bridge between "I want to study" and "AI is building my environment".
/// Deliberately not a generic document picker: the drop zone converges into an
/// AI orb and the "AI Will Build For You" grid previews what uploading unlocks.
/// Faithful to the company mockup (Outfit type, gradient CTA, no bottom nav so
/// the creation flow stays focused).
class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadedFile {
  const _UploadedFile({required this.name, required this.type, required this.meta});
  final String name;
  final SourceFileType type;
  final String meta;
}

class _UploadPageState extends State<UploadPage> {
  final _nameController = TextEditingController();
  final _files = <_UploadedFile>[];

  // Realistic stand-ins for a real picker (swap for `file_picker` later).
  static const _samples = <_UploadedFile>[
    _UploadedFile(name: 'Lecture 5.pdf', type: SourceFileType.pdf, meta: '124 pages • 8.4 MB'),
    _UploadedFile(name: 'Midterm Slides.pptx', type: SourceFileType.pptx, meta: '58 slides • 12.7 MB'),
    _UploadedFile(name: 'Lecture Recording.mp3', type: SourceFileType.audio, meta: '1 hr 42 min • 96.3 MB'),
    _UploadedFile(name: 'Chapter Notes.docx', type: SourceFileType.docx, meta: '18 pages • 1.2 MB'),
    _UploadedFile(name: 'Whiteboard.png', type: SourceFileType.image, meta: 'Image • 3.1 MB'),
  ];

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _addFile() {
    setState(() => _files.add(_samples[_files.length % _samples.length]));
  }

  @override
  Widget build(BuildContext context) {
    final canBuild = _files.isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                _TopBar(onBack: () => context.go('/study')),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      CockpitSpacing.lg,
                      CockpitSpacing.sm,
                      CockpitSpacing.lg,
                      CockpitSpacing.xxl,
                    ),
                    children: [
                      _SectionLabel('Studio Name'),
                      const SizedBox(height: CockpitSpacing.sm),
                      _StudioNameField(controller: _nameController),
                      const SizedBox(height: CockpitSpacing.xl),
                      _DropZone(onTap: _addFile),
                      if (_files.isNotEmpty) ...[
                        const SizedBox(height: CockpitSpacing.xl),
                        Row(
                          children: [
                            Expanded(
                              child: _SectionLabel('Uploaded Files (${_files.length})'),
                            ),
                            TextButton(
                              onPressed: () => setState(_files.clear),
                              child: const Text('Clear All'),
                            ),
                          ],
                        ),
                        const SizedBox(height: CockpitSpacing.xs),
                        for (var i = 0; i < _files.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: CockpitSpacing.sm),
                            child: _FileCard(
                              file: _files[i],
                              onRemove: () => setState(() => _files.removeAt(i)),
                            ),
                          ),
                      ],
                      const SizedBox(height: CockpitSpacing.xl),
                      _SectionLabel('AI Will Build For You'),
                      const SizedBox(height: CockpitSpacing.md),
                      const _AiWillBuildGrid(),
                    ],
                  ),
                ),
                _BuildBar(
                  enabled: canBuild,
                  onBuild: () => context.go('/study/build/job1'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CockpitSpacing.md,
        CockpitSpacing.sm,
        CockpitSpacing.md,
        0,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _CircleIconButton(icon: Icons.arrow_back_ios_new, onTap: onBack),
              Expanded(
                child: Text(
                  'Create Study Studio',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 44), // balances the back button
            ],
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
            child: Text(
              "Upload anything. We'll transform it into an "
              'interactive AI study environment.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: CockpitSpacing.sm),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});
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

// ---------------------------------------------------------------------------
// Studio Name
// ---------------------------------------------------------------------------

class _StudioNameField extends StatelessWidget {
  const _StudioNameField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CockpitSpacing.md,
        vertical: CockpitSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(CockpitRadii.sm),
            ),
            child: Icon(Icons.auto_awesome, size: 18, color: scheme.primary),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          Expanded(
            child: TextField(
              controller: controller,
              maxLength: 100,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
              decoration: const InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                hintText: 'e.g. Computer Networks Final Exam',
              ),
              style: theme.textTheme.bodyLarge,
            ),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          Text(
            '${controller.text.characters.length}/100',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Drop zone + AI orb
// ---------------------------------------------------------------------------

class _DropZone extends StatelessWidget {
  const _DropZone({required this.onTap});
  final VoidCallback onTap;

  static const _formats = <(IconData, String)>[
    (Icons.picture_as_pdf_outlined, 'PDF'),
    (Icons.description_outlined, 'DOCX'),
    (Icons.slideshow_outlined, 'PPTX'),
    (Icons.image_outlined, 'Images'),
    (Icons.graphic_eq, 'Audio'),
    (Icons.videocam_outlined, 'Video'),
    (Icons.notes_outlined, 'Text'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CockpitRadii.xl),
      child: DottedBorder(
        radius: CockpitRadii.xl,
        color: scheme.primary.withValues(alpha: 0.45),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CockpitRadii.xl),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                scheme.primary.withValues(alpha: 0.05),
                scheme.primary.withValues(alpha: 0.02),
              ],
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: CockpitSpacing.lg,
            vertical: CockpitSpacing.xl,
          ),
          child: Column(
            children: [
              _OrbCluster(),
              const SizedBox(height: CockpitSpacing.lg),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: theme.textTheme.titleMedium,
                  children: [
                    TextSpan(
                      text: 'Drag & Drop',
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(
                      text: ' or ',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    TextSpan(
                      text: 'Tap to Upload',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: CockpitSpacing.md),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: CockpitSpacing.sm,
                runSpacing: CockpitSpacing.sm,
                children: [
                  for (final (icon, label) in _formats)
                    _FormatChip(icon: icon, label: label),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The glowing AI core with material icons converging toward it. On Screen 3
/// the same orb stays on screen and generates study objects around itself.
class _OrbCluster extends StatelessWidget {
  const _OrbCluster();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final violet = _shiftHue(scheme.primary, -28);
    return SizedBox(
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned(left: 4, top: 6, child: _SatIcon(Icons.picture_as_pdf, Color(0xFFE5484D))),
          const Positioned(left: 18, bottom: 4, child: _SatIcon(Icons.image, Color(0xFF30A46C))),
          const Positioned(left: 0, top: 54, child: _SatIcon(Icons.description, Color(0xFF3B82F6))),
          const Positioned(right: 4, top: 6, child: _SatIcon(Icons.slideshow, Color(0xFFF76808))),
          const Positioned(right: 0, top: 54, child: _SatIcon(Icons.graphic_eq, Color(0xFF8B5CF6))),
          const Positioned(right: 18, bottom: 4, child: _SatIcon(Icons.videocam, Color(0xFF3B82F6))),
          // The AI core.
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [violet, scheme.primary],
              ),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.45),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 34),
          ),
        ],
      ),
    );
  }
}

class _SatIcon extends StatelessWidget {
  const _SatIcon(this.icon, this.color);
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(CockpitRadii.sm),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

class _FormatChip extends StatelessWidget {
  const _FormatChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CockpitSpacing.md,
        vertical: CockpitSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: CockpitSpacing.xs),
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Uploaded file card
// ---------------------------------------------------------------------------

class _FileCard extends StatelessWidget {
  const _FileCard({required this.file, required this.onRemove});
  final _UploadedFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, color) = _fileVisual(file.type);
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(CockpitRadii.sm),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: CockpitSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  file.meta,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          Icon(Icons.check_circle, size: 18, color: scheme.tertiary),
          const SizedBox(width: 2),
          Text(
            'Ready',
            style: theme.textTheme.labelMedium?.copyWith(color: scheme.tertiary),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, size: 18, color: scheme.onSurfaceVariant),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AI Will Build For You
// ---------------------------------------------------------------------------

class _AiFeature {
  const _AiFeature(this.icon, this.color, this.title, this.desc);
  final IconData icon;
  final Color color;
  final String title;
  final String desc;
}

class _AiWillBuildGrid extends StatelessWidget {
  const _AiWillBuildGrid();

  static const _features = <_AiFeature>[
    _AiFeature(Icons.menu_book_rounded, Color(0xFF3B82F6), 'Topics', 'Organized into key topics'),
    _AiFeature(Icons.bookmark_rounded, Color(0xFF30A46C), 'Definitions', 'Clear explanations and key terms'),
    _AiFeature(Icons.forum_rounded, Color(0xFF8B5CF6), 'AI Tutor', 'Ask anything, get answers'),
    _AiFeature(Icons.style_rounded, Color(0xFFF76808), 'Flashcards', 'Smart flashcards for retention'),
    _AiFeature(Icons.help_rounded, Color(0xFFE5484D), 'Quizzes', 'Practice with AI-generated questions'),
    _AiFeature(Icons.view_in_ar_rounded, Color(0xFF30A46C), 'Scenarios', 'Real-world application practice'),
    _AiFeature(Icons.hub_rounded, Color(0xFF8B5CF6), 'Knowledge Graph', 'Visual connections between concepts'),
    _AiFeature(Icons.psychology_rounded, Color(0xFFF5A623), 'Memory Hooks', 'Mnemonics & memory aids'),
    _AiFeature(Icons.gps_fixed_rounded, Color(0xFFE5484D), 'Weak Topic Detection', 'AI identifies what you need to review'),
    _AiFeature(Icons.insights_rounded, Color(0xFF3B82F6), 'Visual Explanations', 'Diagrams, charts & visuals'),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _features.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        mainAxisSpacing: CockpitSpacing.sm,
        crossAxisSpacing: CockpitSpacing.sm,
        mainAxisExtent: 138,
      ),
      itemBuilder: (context, i) => _FeatureCard(_features[i]),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard(this.feature);
  final _AiFeature feature;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: feature.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(feature.icon, color: feature.color, size: 20),
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Text(
            feature.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: Text(
              feature.desc,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Build CTA
// ---------------------------------------------------------------------------

class _BuildBar extends StatelessWidget {
  const _BuildBar({required this.enabled, required this.onBuild});
  final bool enabled;
  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final violet = _shiftHue(scheme.primary, -28);

    return Container(
      padding: const EdgeInsets.fromLTRB(
        CockpitSpacing.lg,
        CockpitSpacing.md,
        CockpitSpacing.lg,
        CockpitSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: enabled ? 1 : 0.5,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: enabled ? onBuild : null,
                borderRadius: BorderRadius.circular(CockpitRadii.pill),
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(CockpitRadii.pill),
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [scheme.secondary, violet],
                    ),
                    boxShadow: enabled
                        ? [
                            BoxShadow(
                              color: scheme.primary.withValues(alpha: 0.35),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ]
                        : null,
                  ),
                  child: const SizedBox(
                    height: 54,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                        SizedBox(width: CockpitSpacing.sm),
                        Text(
                          'Build Study Studio',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.schedule, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: CockpitSpacing.xs),
              Text(
                enabled
                    ? 'Estimated build time: 30–90 seconds'
                    : 'Add at least one file to build',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

(IconData, Color) _fileVisual(SourceFileType type) => switch (type) {
      SourceFileType.pdf => (Icons.picture_as_pdf, const Color(0xFFE5484D)),
      SourceFileType.docx => (Icons.description, const Color(0xFF3B82F6)),
      SourceFileType.pptx => (Icons.slideshow, const Color(0xFFF76808)),
      SourceFileType.txt => (Icons.notes, const Color(0xFF6B7280)),
      SourceFileType.image => (Icons.image, const Color(0xFF30A46C)),
      SourceFileType.audio => (Icons.graphic_eq, const Color(0xFF8B5CF6)),
      SourceFileType.video => (Icons.videocam, const Color(0xFF3B82F6)),
    };

/// Rotates a color's hue to build a same-family gradient companion.
Color _shiftHue(Color base, double degrees) {
  final hsl = HSLColor.fromColor(base);
  final h = (hsl.hue + degrees) % 360;
  return hsl.withHue(h < 0 ? h + 360 : h).toColor();
}

/// A rounded-rect dashed border (Flutter has no built-in one).
class DottedBorder extends StatelessWidget {
  const DottedBorder({
    super.key,
    required this.child,
    required this.color,
    this.radius = 12,
    this.dash = 6,
    this.gap = 4,
    this.strokeWidth = 1.5,
  });

  final Widget child;
  final Color color;
  final double radius;
  final double dash;
  final double gap;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRRectPainter(
        color: color,
        radius: radius,
        dash: dash,
        gap: gap,
        strokeWidth: strokeWidth,
      ),
      child: child,
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({
    required this.color,
    required this.radius,
    required this.dash,
    required this.gap,
    required this.strokeWidth,
  });

  final Color color;
  final double radius;
  final double dash;
  final double gap;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dash;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.dash != dash ||
      old.gap != gap ||
      old.strokeWidth != strokeWidth;
}
