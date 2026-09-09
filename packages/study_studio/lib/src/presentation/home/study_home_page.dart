import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../domain/entities/studio.dart';
import '../../domain/entities/topic.dart';
import '../format.dart';
import '../widgets/studio_scaffold.dart';

/// Screen 1 — Study Studio Home. A dark, editorial "learning cockpit": one red
/// accent over warm near-black surfaces, big display type, a numbered studio
/// index, and a signature black hero slab. Redesigned from the legacy
/// rainbow-gradient mockup.
class StudyHomePage extends ConsumerWidget {
  const StudyHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // EXPERIMENT: the whole first page is wrapped in the shared borderless
    // design system (Poppins · neutral #222323 · no card/divider outlines) to
    // trial the OctoNotes look in Study Studio. Reversible — remove this wrap to
    // revert. Nothing ships until re-deployed.
    return BorderlessTheme.wrap(
      context: context,
      child: Stack(
        children: [
          Positioned.fill(
            child: Builder(builder: (context) => _build(context, ref)),
          ),
          const Positioned(
            right: CockpitSpacing.xl,
            bottom: CockpitSpacing.lg,
            child: ThemeSwitcher(),
          ),
        ],
      ),
    );
  }

  Widget _build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final signedIn = auth.valueOrNull ?? ref.watch(authServiceProvider).isSignedIn;

    // Don't flash a raw API 401 before the user has a session — gate first.
    if (auth.isLoading) {
      return const StudioShell(
        selectedIndex: 1,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!signedIn) {
      return const StudioShell(
        selectedIndex: 1,
        child: SafeArea(child: _SignInGate()),
      );
    }

    final studios = ref.watch(studioListProvider);

    return StudioShell(
      selectedIndex: 1,
      child: SafeArea(
        bottom: false,
        child: studios.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _isUnauthorized(e)
              ? const _SignInGate()
              : Center(child: Text('Error: $e')),
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

bool _isUnauthorized(Object error) {
  final text = error.toString();
  return text.contains('401') || text.toLowerCase().contains('unauthorized');
}

/// Minimal signed-out home: one Sign in action, no raw API error text.
class _SignInGate extends ConsumerStatefulWidget {
  const _SignInGate();

  @override
  ConsumerState<_SignInGate> createState() => _SignInGateState();
}

class _SignInGateState extends ConsumerState<_SignInGate> {
  bool _busy = false;

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authServiceProvider).signIn();
      ref.invalidate(meProvider);
      ref.invalidate(studioListProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Sign in failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: FilledButton.icon(
        onPressed: _busy ? null : _signIn,
        icon: _busy
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.onPrimary,
                ),
              )
            : const Icon(Icons.login_rounded),
        label: Text(_busy ? 'Signing in…' : 'Sign in'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: CockpitSpacing.xl,
            vertical: CockpitSpacing.md,
          ),
          textStyle: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Desktop / web layout — nav rail (from StudioShell) + two-column content.
// Header + hero stay pinned; only the "Your Studios" grid scrolls, so the page
// itself never scrolls at 1280×720.
// ---------------------------------------------------------------------------

class _HomeDesktop extends StatelessWidget {
  const _HomeDesktop({required this.studios});

  final List<Studio> studios;

  @override
  Widget build(BuildContext context) {
    final byRecent = _byRecent(studios);

    return Padding(
        padding: const EdgeInsets.fromLTRB(40, 26, 40, 26),
        child: ContentColumn(
          maxWidth: 1600,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Masthead(),
              const SizedBox(height: CockpitSpacing.md),
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
                            const _SectionLabel(
                              index: '01',
                              title: 'Continue learning',
                              action: 'View all',
                            ),
                            const SizedBox(height: CockpitSpacing.md),
                            _ContinueFeature(studio: _latestCreated(studios)),
                            const SizedBox(height: CockpitSpacing.lg),
                          ],
                          _SectionLabel(
                            index: byRecent.isNotEmpty ? '02' : '01',
                            title: 'Your studios',
                            trailingText: '${studios.length}',
                          ),
                          const SizedBox(height: CockpitSpacing.md),
                          Expanded(
                            child: studios.isEmpty
                                ? const _EmptyStudios()
                                : GridView.builder(
                                    padding: const EdgeInsets.only(
                                        bottom: CockpitSpacing.sm),
                                    itemCount: studios.length,
                                    gridDelegate:
                                        const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 420,
                                      mainAxisSpacing: CockpitSpacing.md,
                                      crossAxisSpacing: CockpitSpacing.md,
                                      mainAxisExtent: 96,
                                    ),
                                    itemBuilder: (_, i) => _StudioRow(
                                      studio: studios[i],
                                      index: i + 1,
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
                          _StatsPanel(studios: studios),
                          const SizedBox(height: CockpitSpacing.lg),
                          const _SectionLabel(
                            index: '·',
                            title: 'Recommended',
                          ),
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

class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.studios});

  final List<Studio> studios;

  @override
  Widget build(BuildContext context) {
    final byRecent = _byRecent(studios);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const SizedBox(height: CockpitSpacing.sm),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
          child: _Masthead(),
        ),
        const SizedBox(height: CockpitSpacing.lg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
          child: _NewStudioHero(onTap: () => context.go('/study/upload')),
        ),
        if (byRecent.isNotEmpty) ...[
          const SizedBox(height: CockpitSpacing.xl),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
            child: _SectionLabel(
              index: '01',
              title: 'Continue learning',
              action: 'View all',
            ),
          ),
          const SizedBox(height: CockpitSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
            child: _ContinueFeature(studio: _latestCreated(studios)),
          ),
        ],
        const SizedBox(height: CockpitSpacing.xl),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
          child: _SectionLabel(
            index: byRecent.isNotEmpty ? '02' : '01',
            title: 'Your studios',
            trailingText: '${studios.length}',
          ),
        ),
        const SizedBox(height: CockpitSpacing.md),
        if (studios.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
            child: SizedBox(height: 180, child: _EmptyStudios()),
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
              child: _StudioRow(studio: studios[i], index: i + 1),
            ),
        const SizedBox(height: CockpitSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
          child: _RecommendationCard(studios: studios),
        ),
        const SizedBox(height: CockpitSpacing.xl),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Masthead
// ---------------------------------------------------------------------------

class _Masthead extends StatelessWidget {
  const _Masthead();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final desktop = isDesktop(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Eyebrow('Your learning cockpit'),
        const SizedBox(height: CockpitSpacing.xs),
        Text(
          'Turn notes into mastery',
          style: (desktop
                  ? theme.textTheme.headlineMedium
                  : theme.textTheme.headlineSmall)
              ?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            height: 1.0,
          ),
        ),
        const SizedBox(height: CockpitSpacing.xs),
        Text(
          'Lectures, notes, and textbooks — rebuilt as a living, '
          'AI-taught curriculum.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

/// Uppercase micro-label in brand red — the editorial signature used to open
/// the header and every section.
class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 16, height: 2, color: c),
        const SizedBox(width: CockpitSpacing.sm),
        Flexible(
          child: Text(
            text.toUpperCase(),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            style: TextStyle(
              color: c,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.4,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// New Study Studio hero — a signature black slab with a red glow.
// ---------------------------------------------------------------------------

class _NewStudioHero extends StatelessWidget {
  const _NewStudioHero({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Hoverable(
      builder: (hovered) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CockpitRadii.xl),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(CockpitSpacing.lg),
            decoration: BoxDecoration(
              // Matte red — flat solid, no gradient, no border.
              color: scheme.primary,
              borderRadius: BorderRadius.circular(CockpitRadii.xl),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary
                      .withValues(alpha: hovered ? 0.38 : 0.20),
                  blurRadius: hovered ? 28 : 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(CockpitRadii.md),
                  ),
                  child: Icon(Icons.add_rounded,
                      color: scheme.primary, size: 30),
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
                          letterSpacing: -0.3,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Upload materials and let AI build your '
                        'personalized study space',
                        style: TextStyle(
                          color: Color(0xFFFFDFDF),
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: CockpitSpacing.md),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white
                        .withValues(alpha: hovered ? 0.30 : 0.16),
                  ),
                  child: const Icon(Icons.arrow_forward_rounded,
                      color: Colors.white, size: 20),
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
// Continue Learning poster
// ---------------------------------------------------------------------------

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.studio});

  final Studio studio;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = (studio.overallMastery.clamp(0, 1) * 100).round();
    final subtitle =
        studio.topics.isNotEmpty ? studio.topics.first.title : studio.subject;

    return _Hoverable(
      builder: (hovered) => GestureDetector(
        onTap: () => context.go('/study/${studio.id}'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 176,
          padding: const EdgeInsets.all(CockpitSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CockpitRadii.xl),
            // Subtle border always; the surface fills in on hover.
            color: hovered ? scheme.surfaceContainerHigh : Colors.transparent,
            border: Border.all(
              color: hovered
                  ? scheme.primary.withValues(alpha: 0.4)
                  : scheme.outlineVariant,
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
                      color: scheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(CockpitRadii.sm),
                    ),
                    child: Icon(_iconFor(studio.subject),
                        color: scheme.primary, size: 19),
                  ),
                  const Spacer(),
                  Text(
                    '$pct%',
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                studio.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: scheme.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: CockpitSpacing.md),
              ClipRRect(
                borderRadius: BorderRadius.circular(CockpitRadii.pill),
                child: LinearProgressIndicator(
                  value: studio.overallMastery.clamp(0, 1).toDouble(),
                  minHeight: 4,
                  backgroundColor: scheme.surfaceContainerHigh,
                  valueColor: AlwaysStoppedAnimation(scheme.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Continue learning = the most-recently-created studio (one card) + a few
/// analytics lines for it.
class _ContinueFeature extends StatelessWidget {
  const _ContinueFeature({required this.studio});
  final Studio studio;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 168,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ContinueCard(studio: studio),
          const SizedBox(width: CockpitSpacing.xl),
          Expanded(child: _ContinueAnalytics(studio: studio)),
        ],
      ),
    );
  }
}

class _ContinueAnalytics extends StatelessWidget {
  const _ContinueAnalytics({required this.studio});
  final Studio studio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pct = (studio.overallMastery.clamp(0, 1) * 100).round();

    Widget line(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: CockpitSpacing.sm),
          child: Row(
            children: [
              Icon(icon, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: CockpitSpacing.sm),
              Text(label,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const Spacer(),
              Text(value,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        );

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(studio.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium),
        const SizedBox(height: CockpitSpacing.md),
        line(Icons.topic_outlined, 'Topics', '${studio.topicCount}'),
        line(Icons.style_outlined, 'Flashcards', '${studio.flashcardCount}'),
        line(Icons.insights_outlined, 'Mastery', '$pct%'),
        line(Icons.schedule, 'Last studied',
            relativeDay(studio.lastStudied)),
      ],
    );
  }
}

Studio _latestCreated(List<Studio> studios) =>
    [...studios].reduce((a, b) => a.createdAt.isAfter(b.createdAt) ? a : b);

// ---------------------------------------------------------------------------
// Your Studios — numbered editorial row
// ---------------------------------------------------------------------------

class _StudioRow extends StatelessWidget {
  const _StudioRow({required this.studio, required this.index});

  final Studio studio;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _Hoverable(
      builder: (hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          // Cardless: transparent until hover — grouping via space + the number.
          color: hovered ? scheme.surfaceContainerHigh : Colors.transparent,
          borderRadius: BorderRadius.circular(CockpitRadii.lg),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => context.go('/study/${studio.id}'),
            borderRadius: BorderRadius.circular(CockpitRadii.lg),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CockpitSpacing.md,
                vertical: CockpitSpacing.md,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    child: Text(
                      index.toString().padLeft(2, '0'),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: CockpitSpacing.sm),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(CockpitRadii.md),
                    ),
                    child: Icon(_iconFor(studio.subject),
                        color: scheme.onSurface, size: 21),
                  ),
                  const SizedBox(width: CockpitSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          studio.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${studio.topicCount} topics · '
                          '${studio.flashcardCount} cards · '
                          '${relativeDay(studio.lastStudied).toLowerCase()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: CockpitSpacing.sm),
                  ProgressRing(
                    value: studio.overallMastery,
                    color: scheme.primary,
                    size: 44,
                    stroke: 4,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stats panel (desktop aside)
// ---------------------------------------------------------------------------

class _StatsPanel extends StatelessWidget {
  const _StatsPanel({required this.studios});
  final List<Studio> studios;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final topics = studios.fold<int>(0, (n, s) => n + s.topicCount);
    final avg = studios.isEmpty
        ? 0
        : (studios.fold<double>(0, (n, s) => n + s.overallMastery) /
                studios.length *
                100)
            .round();

    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          _Stat(value: '${studios.length}', label: 'Studios'),
          _StatDivider(),
          _Stat(value: '$topics', label: 'Topics'),
          _StatDivider(),
          _Stat(value: '$avg%', label: 'Avg mastery', accent: true),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.accent = false});
  final String value;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              color: accent ? scheme.primary : scheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 34,
        margin: const EdgeInsets.symmetric(horizontal: CockpitSpacing.md),
        color: Theme.of(context).colorScheme.outlineVariant,
      );
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
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(CockpitRadii.lg),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: CockpitSpacing.sm, vertical: 3),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(CockpitRadii.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome,
                          size: 12, color: scheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        'AI RECOMMENDATION',
                        style: TextStyle(
                          color: scheme.primary,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: CockpitSpacing.md),
            Text(
              'Review ${topic.title}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'This topic is your weakest — a quick review will move the needle.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant, height: 1.35),
            ),
            const SizedBox(height: CockpitSpacing.md),
            Row(
              children: [
                Icon(Icons.schedule, size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  '${topic.estimatedStudyTimeMinutes} min',
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
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

/// Section header: a numbered index + title, with an optional text action or a
/// small trailing count.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.index,
    required this.title,
    this.action,
    this.trailingText,
  });

  final String index;
  final String title;
  final String? action;
  final String? trailingText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          index,
          style: TextStyle(
            color: scheme.primary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: CockpitSpacing.sm),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
        ),
        if (trailingText != null)
          Text(
            trailingText!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        if (action != null)
          TextButton(
            onPressed: () {},
            style: TextButton.styleFrom(
              foregroundColor: scheme.onSurfaceVariant,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            child: Text(action!),
          ),
      ],
    );
  }
}

class _EmptyStudios extends StatelessWidget {
  const _EmptyStudios();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CockpitSpacing.xl),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_stories_outlined,
              size: 40, color: scheme.onSurfaceVariant),
          const SizedBox(height: CockpitSpacing.md),
          Text(
            'No studios yet',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Build your first one from the panel above.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Wraps a card so it reacts to pointer hover on desktop/web. [builder] gets the
/// current hover state; on touch it simply stays `false`.
class _Hoverable extends StatefulWidget {
  const _Hoverable({required this.builder});
  final Widget Function(bool hovered) builder;

  @override
  State<_Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<_Hoverable> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.012 : 1.0,
        duration: const Duration(milliseconds: 160),
        child: widget.builder(_hovered),
      ),
    );
  }
}

List<Studio> _byRecent(List<Studio> studios) => [...studios]..sort((a, b) {
      final da = a.lastStudied ?? a.updatedAt;
      final db = b.lastStudied ?? b.updatedAt;
      return db.compareTo(da);
    });

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
