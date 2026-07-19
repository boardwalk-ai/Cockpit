import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../domain/entities/studio.dart';
import '../../domain/entities/topic.dart';
import '../format.dart';
import '../widgets/studio_scaffold.dart';

/// Screen 1 — Study Studio Home. The gateway into the module: pick an existing
/// studio or build a new one. Faithful to the company mockup (Outfit type,
/// gradient hero, Continue Learning rail, studio list with mastery rings, an AI
/// recommendation, and the shared bottom nav).
class StudyHomePage extends ConsumerWidget {
  const StudyHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studios = ref.watch(studioListProvider);

    return StudioShell(
      selectedIndex: 1,
      child: SafeArea(
        bottom: false,
        child: studios.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (list) => isDesktop(context)
              ? _HomeDesktop(studios: list)
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: _HomeBody(studios: list),
                  ),
                ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Desktop / web layout — nav rail (from StudioShell) + two-column content.
// ---------------------------------------------------------------------------

class _HomeDesktop extends StatelessWidget {
  const _HomeDesktop({required this.studios});

  final List<Studio> studios;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byRecent = [...studios]..sort((a, b) {
        final da = a.lastStudied ?? a.updatedAt;
        final db = b.lastStudied ?? b.updatedAt;
        return db.compareTo(da);
      });

    // Viewport-fit: the header + hero stay pinned; the two-column region fills
    // the remaining height and only the "Your Studios" grid scrolls internally,
    // so the page itself never scrolls on desktop.
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 28, 40, 28),
      child: ContentColumn(
        maxWidth: 1180,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Study Studio',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: CockpitSpacing.xs),
                      Text(
                        'Turn your notes, lectures, and textbooks into an '
                        'AI-powered learning environment.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: CockpitSpacing.lg),
                _CircleIconButton(
                  icon: Icons.notifications_none_rounded,
                  onTap: () {},
                  showDot: true,
                ),
              ],
            ),
            const SizedBox(height: CockpitSpacing.lg),
            _NewStudioHero(onTap: () => context.go('/study/upload')),
            const SizedBox(height: CockpitSpacing.xl),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (byRecent.isNotEmpty) ...[
                          _DeskSection(
                            title: 'Continue Learning',
                            action: 'View all',
                            onAction: () {},
                          ),
                          const SizedBox(height: CockpitSpacing.md),
                          SizedBox(
                            height: 172,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: EdgeInsets.zero,
                              itemCount: byRecent.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: CockpitSpacing.md),
                              itemBuilder: (_, i) => _ContinueCard(
                                studio: byRecent[i],
                                accent: _accentFor(i),
                              ),
                            ),
                          ),
                          const SizedBox(height: CockpitSpacing.lg),
                        ],
                        _DeskSection(title: 'Your Studios'),
                        const SizedBox(height: CockpitSpacing.md),
                        Expanded(
                          child: GridView.builder(
                            padding: const EdgeInsets.only(
                                bottom: CockpitSpacing.sm),
                            itemCount: studios.length,
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 380,
                              mainAxisSpacing: CockpitSpacing.md,
                              crossAxisSpacing: CockpitSpacing.md,
                              mainAxisExtent: 116,
                            ),
                            itemBuilder: (_, i) => _StudioRow(
                              studio: studios[i],
                              accent: _accentFor(i),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: CockpitSpacing.xl),
                  SizedBox(
                    width: 340,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _DeskSection(title: 'Recommended for you'),
                        const SizedBox(height: CockpitSpacing.md),
                        _RecommendationCard(studios: studios, padded: false),
                      ],
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

class _DeskSection extends StatelessWidget {
  const _DeskSection({required this.title, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.studios});

  final List<Studio> studios;

  @override
  Widget build(BuildContext context) {
    // Most-recently-studied first drives the "Continue Learning" rail.
    final byRecent = [...studios]..sort((a, b) {
        final da = a.lastStudied ?? a.updatedAt;
        final db = b.lastStudied ?? b.updatedAt;
        return db.compareTo(da);
      });

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const SizedBox(height: CockpitSpacing.sm),
        const _Header(),
        const SizedBox(height: CockpitSpacing.xl),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
          child: _NewStudioHero(onTap: () => context.go('/study/upload')),
        ),
        if (byRecent.isNotEmpty) ...[
          const SizedBox(height: CockpitSpacing.xl),
          _SectionHeader(
            title: 'Continue Learning',
            trailing: TextButton(
              onPressed: () {},
              child: const Text('View all'),
            ),
          ),
          const SizedBox(height: CockpitSpacing.md),
          SizedBox(
            height: 172,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
              itemCount: byRecent.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: CockpitSpacing.md),
              itemBuilder: (_, i) {
                final s = byRecent[i];
                return _ContinueCard(studio: s, accent: _accentFor(i));
              },
            ),
          ),
        ],
        const SizedBox(height: CockpitSpacing.xl),
        _SectionHeader(
          title: 'Your Studios',
          trailing: TextButton.icon(
            onPressed: () {},
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.expand_more, size: 18),
            label: const Text('Recent'),
          ),
        ),
        const SizedBox(height: CockpitSpacing.sm),
        if (studios.isEmpty)
          const Padding(
            padding: EdgeInsets.all(CockpitSpacing.xl),
            child: Text('No studios yet — build your first one above.'),
          )
        else
          for (var i = 0; i < studios.length; i++)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CockpitSpacing.lg,
                0,
                CockpitSpacing.lg,
                CockpitSpacing.md,
              ),
              child: _StudioRow(studio: studios[i], accent: _accentFor(i)),
            ),
        const SizedBox(height: CockpitSpacing.sm),
        _RecommendationCard(studios: studios),
        const SizedBox(height: CockpitSpacing.xl),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Study Studio',
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: CockpitSpacing.xs),
                Text(
                  'Turn your notes, lectures, and textbooks into an '
                  'AI-powered learning environment.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: CockpitSpacing.md),
          _CircleIconButton(
            icon: Icons.notifications_none_rounded,
            onTap: () {},
            showDot: true,
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.showDot = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 22, color: theme.colorScheme.onSurface),
            if (showDot)
              Positioned(
                top: 11,
                right: 12,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.colorScheme.surface,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// New Study Studio hero
// ---------------------------------------------------------------------------

class _NewStudioHero extends StatelessWidget {
  const _NewStudioHero({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Derive a violet companion from the brand primary so the gradient tracks
    // rebrands instead of hard-coding hexes.
    final violet = _shiftHue(scheme.primary, -28);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CockpitRadii.xl),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CockpitRadii.xl),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [violet, scheme.primary],
            ),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          padding: const EdgeInsets.all(CockpitSpacing.lg),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 30),
              ),
              const SizedBox(width: CockpitSpacing.lg),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'New Study Studio',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Upload materials and let AI build your '
                      'personalized study space',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: CockpitSpacing.sm),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Continue Learning card
// ---------------------------------------------------------------------------

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.studio, required this.accent});

  final Studio studio;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final pct = (studio.overallMastery * 100).round();
    // Deep, saturated version of the accent for the poster-like card.
    final top = Color.lerp(accent, Colors.black, 0.35)!;
    final bottom = Color.lerp(accent, Colors.black, 0.62)!;
    final subtitle =
        studio.topics.isNotEmpty ? studio.topics.first.title : studio.subject;

    return GestureDetector(
      onTap: () => context.go('/study/${studio.id}'),
      child: Container(
        width: 168,
        padding: const EdgeInsets.all(CockpitSpacing.lg),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(CockpitRadii.xl),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [top, bottom],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(CockpitRadii.sm),
                  ),
                  child: Icon(_iconFor(studio.subject),
                      color: Colors.white, size: 20),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CockpitSpacing.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(CockpitRadii.pill),
                  ),
                  child: Text(
                    '$pct%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              studio.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: CockpitSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(CockpitRadii.pill),
              child: LinearProgressIndicator(
                value: studio.overallMastery.clamp(0, 1).toDouble(),
                minHeight: 5,
                backgroundColor: Colors.white.withValues(alpha: 0.25),
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Your Studios row
// ---------------------------------------------------------------------------

class _StudioRow extends StatelessWidget {
  const _StudioRow({required this.studio, required this.accent});

  final Studio studio;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CockpitCard(
      onTap: () => context.go('/study/${studio.id}'),
      padding: const EdgeInsets.all(CockpitSpacing.md),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(CockpitRadii.md),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accent, _shiftHue(accent, -24)],
              ),
            ),
            child: Icon(_iconFor(studio.subject), color: Colors.white, size: 26),
          ),
          const SizedBox(width: CockpitSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  studio.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.category_outlined,
                        size: 13, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 3),
                    Text('${studio.topicCount} Topics',
                        style: theme.textTheme.bodySmall),
                    Text('  •  ',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                    Icon(Icons.style_outlined,
                        size: 13, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text('${studio.flashcardCount} Cards',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Last studied ${relativeDay(studio.lastStudied).toLowerCase()}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          ProgressRing(value: studio.overallMastery, color: accent, size: 50),
          Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AI Recommendation
// ---------------------------------------------------------------------------

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.studios, this.padded = true});

  final List<Studio> studios;
  final bool padded;

  /// The weakest topic across all studios is the natural "review next".
  ({Studio studio, Topic topic})? _pickWeakest() {
    ({Studio studio, Topic topic})? best;
    for (final s in studios) {
      for (final t in s.topics) {
        if (best == null || t.mastery < best.topic.mastery) {
          best = (studio: s, topic: t);
        }
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final pick = _pickWeakest();
    if (pick == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final topic = pick.topic;

    return Padding(
      padding: padded
          ? const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg)
          : EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.all(CockpitSpacing.lg),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(CockpitRadii.lg),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.smart_toy_outlined,
                  color: scheme.primary, size: 24),
            ),
            const SizedBox(width: CockpitSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI Recommendation',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Review ${topic.title}',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "You haven't reviewed this topic recently.",
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: CockpitSpacing.sm),
                  Row(
                    children: [
                      Icon(Icons.schedule,
                          size: 14, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        'Estimated time: ${topic.estimatedStudyTimeMinutes} min',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () => context.go(
                          '/study/${pick.studio.id}/teach/${topic.id}',
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: CockpitSpacing.lg,
                            vertical: CockpitSpacing.sm,
                          ),
                        ),
                        child: const Text('Start'),
                      ),
                    ],
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
// Shared bits
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: CockpitSpacing.lg, right: CockpitSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// Decorative accent palette for studio thumbnails / rings. Presentation-only —
// not a brand token — so studios read as visually distinct like the mockup.
const List<Color> _studioAccents = [
  Color(0xFF7C3AED), // violet
  Color(0xFF2563EB), // blue
  Color(0xFF059669), // emerald
  Color(0xFFEA580C), // orange
  Color(0xFFDB2777), // pink
];

Color _accentFor(int index) => _studioAccents[index % _studioAccents.length];

IconData _iconFor(String subject) {
  final s = subject.toLowerCase();
  if (s.contains('bio')) return Icons.biotech_outlined;
  if (s.contains('chem')) return Icons.science_outlined;
  if (s.contains('history')) return Icons.account_balance_outlined;
  if (s.contains('math') || s.contains('calc')) return Icons.functions;
  if (s.contains('baggage') || s.contains('bag')) return Icons.luggage_outlined;
  if (s.contains('network') || s.contains('computer')) return Icons.hub_outlined;
  return Icons.menu_book_outlined;
}

/// Rotates a color's hue while keeping saturation/lightness — used to build
/// two-stop gradients that stay in the same family as a base accent.
Color _shiftHue(Color base, double degrees) {
  final hsl = HSLColor.fromColor(base);
  final h = (hsl.hue + degrees) % 360;
  return hsl.withHue(h < 0 ? h + 360 : h).toColor();
}
