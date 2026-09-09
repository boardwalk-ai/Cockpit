import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';

import '../../domain/materials_controller.dart';
import '../../domain/materials_models.dart';
import '../../domain/notes_controller.dart';

/// Panel 8 — Materials & Slides (split-view). View lecture materials beside
/// notes, follow the professor's slide, and trace links to notes / transcript.
/// The original source is never modified (spec §2).
class MaterialsPanel extends StatelessWidget {
  const MaterialsPanel({
    super.key,
    required this.controller,
    required this.notes,
    required this.onClose,
    required this.onAnnotate,
    required this.onOpenTranscript,
  });

  final MaterialsController controller;
  final NotesController notes;
  final VoidCallback onClose;
  final VoidCallback onAnnotate;
  final VoidCallback onOpenTranscript;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(controller: controller, onClose: onClose),
            Divider(height: 1, color: scheme.outlineVariant),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ThumbnailStrip(controller: controller),
                  VerticalDivider(width: 1, color: scheme.outlineVariant),
                  Expanded(
                    child: _PreviewColumn(
                      controller: controller,
                      notes: notes,
                      onAnnotate: onAnnotate,
                      onOpenTranscript: onOpenTranscript,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ===========================================================================
// Header
// ===========================================================================
class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.onClose});
  final MaterialsController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final m = controller.current;
    return Padding(
      padding: const EdgeInsets.fromLTRB(CockpitSpacing.lg, CockpitSpacing.md,
          CockpitSpacing.md, CockpitSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(m.displayName, style: theme.textTheme.titleMedium),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Row(
            children: [
              _FileSelector(controller: controller),
              const SizedBox(width: CockpitSpacing.md),
              Text('Slide ${controller.currentPageNumber} of ${m.pageCount}',
                  style: theme.textTheme.bodySmall),
              const SizedBox(width: CockpitSpacing.sm),
              _RoundBtn(
                  icon: Icons.chevron_left_rounded, onTap: controller.prev),
              _RoundBtn(
                  icon: Icons.chevron_right_rounded, onTap: controller.next),
            ],
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Row(
            children: [
              _FollowLectureToggle(controller: controller),
              const SizedBox(width: CockpitSpacing.md),
              if (controller.page.activeWindow != null)
                Text('Active ${controller.page.activeWindow}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              const Spacer(),
              Icon(Icons.verified_user_rounded,
                  size: 15, color: CockpitColors.brand.success),
              const SizedBox(width: CockpitSpacing.xs),
              Text('Original Source Preserved',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    onChanged: controller.setQuery,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search in document',
                      prefixIcon: const Icon(Icons.search_rounded, size: 16),
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(CockpitRadii.sm),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: CockpitSpacing.sm),
              _RoundBtn(icon: Icons.fullscreen_rounded, onTap: () {}),
              const SizedBox(width: CockpitSpacing.sm),
              OutlinedButton.icon(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(color: scheme.outlineVariant)),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add Material'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FileSelector extends StatelessWidget {
  const _FileSelector({required this.controller});
  final MaterialsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PopupMenuButton<int>(
      tooltip: 'Switch material',
      onSelected: controller.selectMaterial,
      itemBuilder: (context) => [
        for (var i = 0; i < controller.materials.length; i++)
          PopupMenuItem(
            value: i,
            child: Row(children: [
              Icon(controller.materials[i].type.icon, size: 16),
              const SizedBox(width: CockpitSpacing.sm),
              Text(controller.materials[i].filename),
            ]),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: CockpitSpacing.sm, vertical: CockpitSpacing.xs),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(CockpitRadii.sm),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(controller.current.type.icon,
                size: 15, color: scheme.primary),
            const SizedBox(width: CockpitSpacing.xs),
            Text(controller.current.filename,
                style: theme.textTheme.labelMedium),
            const Icon(Icons.arrow_drop_down_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}

class _FollowLectureToggle extends StatelessWidget {
  const _FollowLectureToggle({required this.controller});
  final MaterialsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final on = controller.followLecture;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(
          value: on,
          onChanged: controller.setFollowLecture,
          activeThumbColor: Colors.white,
          activeTrackColor: CockpitColors.brand.success,
        ),
        const SizedBox(width: CockpitSpacing.xs),
        Text('Following Lecture',
            style: theme.textTheme.labelMedium?.copyWith(
              color: on ? CockpitColors.brand.success : scheme.onSurfaceVariant,
            )),
      ],
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
      onPressed: onTap,
    );
  }
}

// ===========================================================================
// Thumbnails
// ===========================================================================
class _ThumbnailStrip extends StatelessWidget {
  const _ThumbnailStrip({required this.controller});
  final MaterialsController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pages = controller.visiblePages;
    return Container(
      width: 104,
      color: scheme.surface,
      child: ListView.builder(
        padding: const EdgeInsets.all(CockpitSpacing.sm),
        itemCount: pages.length,
        itemBuilder: (context, i) {
          final p = pages[i];
          final active = p.number == controller.currentPageNumber;
          return Padding(
            padding: const EdgeInsets.only(bottom: CockpitSpacing.md),
            child: InkWell(
              onTap: () => controller.goToPage(p.number),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${p.number}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: active
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                          fontWeight: active ? FontWeight.w700 : null)),
                  const SizedBox(height: 2),
                  AspectRatio(
                    aspectRatio: 4 / 3,
                    child: Container(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(CockpitRadii.sm),
                        border: Border.all(
                          color: active ? scheme.primary : scheme.outlineVariant,
                          width: active ? 2 : 1,
                        ),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Stack(
                        children: [
                          Center(
                            child: Text(p.title,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 6,
                                    color: scheme.onSurfaceVariant)),
                          ),
                          if (p.hasTranscriptLink || p.noteBlockLinks > 0)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Icon(Icons.link_rounded,
                                  size: 9, color: scheme.primary),
                            ),
                          if (p.hasPencilAnnotation)
                            Positioned(
                              left: 0,
                              bottom: 0,
                              child: Icon(Icons.edit_rounded,
                                  size: 9, color: scheme.tertiary),
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
    );
  }
}

// ===========================================================================
// Preview + actions + connections
// ===========================================================================
class _PreviewColumn extends StatelessWidget {
  const _PreviewColumn({
    required this.controller,
    required this.notes,
    required this.onAnnotate,
    required this.onOpenTranscript,
  });
  final MaterialsController controller;
  final NotesController notes;
  final VoidCallback onAnnotate;
  final VoidCallback onOpenTranscript;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = controller.page;
    return ListView(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      children: [
        Stack(
          children: [
            _SlidePreview(page: p),
            if (!controller.followLecture)
              Positioned(
                right: CockpitSpacing.sm,
                top: CockpitSpacing.sm,
                child: _ReturnToLive(onTap: controller.returnToLiveSlide),
              ),
          ],
        ),
        const SizedBox(height: CockpitSpacing.md),
        _ActionsRow(
          controller: controller,
          notes: notes,
          onAnnotate: onAnnotate,
        ),
        const SizedBox(height: CockpitSpacing.md),
        _Breadcrumb(path: controller.current.deckPath),
        const SizedBox(height: CockpitSpacing.md),
        if (p.hasTranscriptLink)
          _RelatedTranscript(page: p, onOpen: onOpenTranscript),
        const SizedBox(height: CockpitSpacing.sm),
        Row(
          children: [
            Icon(Icons.link_rounded, size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: CockpitSpacing.xs),
            Text('Linked to ${p.noteBlockLinks} note blocks',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }
}

/// A stylized slide preview. Slide 7 renders a schematic Electron Transport
/// Chain; other slides show a titled placeholder (no real image needed here).
class _SlidePreview extends StatelessWidget {
  const _SlidePreview({required this.page});
  final SlidePage page;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A light "paper" surface for the slide, readable in dark + light themes.
    const paper = Color(0xFFFDFBF6);
    const ink = Color(0xFF1B1813);
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: Container(
        decoration: BoxDecoration(
          color: paper,
          borderRadius: BorderRadius.circular(CockpitRadii.md),
          border: Border.all(color: const Color(0xFFDED6C6)),
        ),
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.all(CockpitSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(page.title,
                style: theme.textTheme.titleLarge?.copyWith(
                    color: ink, fontWeight: FontWeight.w800)),
            if (page.number == 7)
              Text('Oxidative Phosphorylation',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: const Color(0xFF6E675B))),
            const SizedBox(height: CockpitSpacing.md),
            Expanded(
              child: page.number == 7
                  ? const _EtcDiagram()
                  : Center(
                      child: Icon(Icons.image_outlined,
                          size: 40, color: const Color(0xFFC9C0AE)),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A simple schematic of the electron transport chain (evokes the mock's slide
/// without embedding an image).
class _EtcDiagram extends StatelessWidget {
  const _EtcDiagram();

  @override
  Widget build(BuildContext context) {
    const complexes = [
      (Color(0xFF9B7BC0), 'I'),
      (Color(0xFF4FA3D1), 'Q'),
      (Color(0xFF4FB6A6), 'III'),
      (Color(0xFFE0A94F), 'IV'),
      (Color(0xFF9B7BC0), 'ATP\nsynthase'),
    ];
    return LayoutBuilder(builder: (context, c) {
      return Column(
        children: [
          // H+ arrows
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < 5; i++)
                const Text('H⁺',
                    style: TextStyle(
                        color: Color(0xFFCF4646),
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 2),
          // membrane band with complexes
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF3ECDD),
                borderRadius: BorderRadius.circular(6),
                border: Border.symmetric(
                    horizontal: BorderSide(color: const Color(0xFFD9CBAE), width: 6)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final (color, label) in complexes)
                    Container(
                      width: 34,
                      height: 46,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: CockpitSpacing.sm),
          const Text('½ O₂ + 2H⁺ → H₂O          ADP + Pi → ATP',
              style: TextStyle(color: Color(0xFF1B1813), fontSize: 11)),
        ],
      );
    });
  }
}

class _ReturnToLive extends StatelessWidget {
  const _ReturnToLive({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary,
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: CockpitSpacing.md, vertical: CockpitSpacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sync_rounded, size: 14, color: Colors.white),
              const SizedBox(width: CockpitSpacing.xs),
              Text('Return to Live Slide',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionsRow extends StatelessWidget {
  const _ActionsRow({
    required this.controller,
    required this.notes,
    required this.onAnnotate,
  });
  final MaterialsController controller;
  final NotesController notes;
  final VoidCallback onAnnotate;

  @override
  Widget build(BuildContext context) {
    final slideLabel = 'Slide ${controller.currentPageNumber}';
    final material = controller.current.displayName;
    void snack(String m) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));

    return Row(
      children: [
        Expanded(
          child: _Action(
            icon: Icons.link_rounded,
            label: 'Link to Note',
            onTap: () {
              notes.addFromSlide(material, slideLabel);
              snack('Linked $material · $slideLabel to Typewriter');
            },
          ),
        ),
        const SizedBox(width: CockpitSpacing.sm),
        Expanded(
          child: _Action(
            icon: Icons.edit_outlined,
            label: 'Annotate',
            onTap: onAnnotate,
          ),
        ),
        const SizedBox(width: CockpitSpacing.sm),
        Expanded(
          child: _Action(
            icon: Icons.auto_awesome_rounded,
            label: 'Ask AI',
            onTap: () => snack('Slide sent to AI (Panel 9)'),
          ),
        ),
        const SizedBox(width: CockpitSpacing.sm),
        Expanded(
          child: _Action(
            icon: Icons.format_quote_rounded,
            label: 'Add Excerpt',
            onTap: () {
              notes.addFromSlide(material, slideLabel,
                  excerpt: controller.page.ocrText.isNotEmpty
                      ? '"${controller.page.title}"'
                      : '"${controller.page.title}"');
              snack('Excerpt added to Typewriter');
            },
          ),
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(CockpitRadii.sm),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: CockpitSpacing.sm, vertical: CockpitSpacing.sm),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(CockpitRadii.sm),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: scheme.onSurfaceVariant),
            const SizedBox(width: CockpitSpacing.xs),
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium),
            ),
          ],
        ),
      ),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Icon(Icons.folder_outlined, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: CockpitSpacing.sm),
        Expanded(
          child: Text(path,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}

class _RelatedTranscript extends StatelessWidget {
  const _RelatedTranscript({required this.page, required this.onOpen});
  final SlidePage page;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Related Transcript', style: theme.textTheme.labelMedium),
          const SizedBox(height: CockpitSpacing.sm),
          Row(
            children: [
              Text(page.transcriptTime!,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700)),
              const SizedBox(width: CockpitSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: CockpitSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: CockpitColors.brand.info.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(CockpitRadii.sm),
                ),
                child: Text('Professor',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: CockpitColors.brand.info)),
              ),
              const SizedBox(width: CockpitSpacing.sm),
              Expanded(
                child: Text('The net result is two ATP and two NADH.',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall),
              ),
              const SizedBox(width: CockpitSpacing.sm),
              OutlinedButton.icon(
                onPressed: onOpen,
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(color: scheme.outlineVariant)),
                icon: const Icon(Icons.play_circle_outline_rounded, size: 16),
                label: const Text('Open in Transcript'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
