import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Borderless building blocks for OctoNotes. Grouping via whitespace + subtle
/// background, never outlines — see `../../theme/octo_notes_theme.dart`.

/// A floating light / system / dark theme switcher (bottom-right). Drives the
/// app-wide [themeControllerProvider], so it re-skins the whole super-app.
class OctoThemeSwitcher extends ConsumerWidget {
  const OctoThemeSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeControllerProvider).mode;
    final ctrl = ref.read(themeControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    Widget btn(IconData icon, ThemeMode m, String tip) {
      final active = mode == m;
      return IconButton(
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        onPressed: () => ctrl.setMode(m),
        icon: Icon(
          icon,
          size: 18,
          color: active ? scheme.primary : scheme.onSurfaceVariant,
        ),
      );
    }

    // Boxless: just the icons, no pill/frame.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.light_mode, ThemeMode.light, 'Light'),
        btn(Icons.settings, ThemeMode.system, 'System'),
        btn(Icons.dark_mode, ThemeMode.dark, 'Dark'),
      ],
    );
  }
}

/// A small, muted, letter-spaced section label (the docs-style "eyebrow").
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 1.0,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// A soft grouping surface — subtle fill, rounded, **no border**. The one bit of
/// background we allow, for things that should feel slightly raised.
class OctoSurface extends StatelessWidget {
  const OctoSurface({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(CockpitSpacing.lg),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(CockpitRadii.lg);
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// An interactive row with no border — grouping/affordance comes from a subtle
/// hover (and an optional selected tint), never an outline.
class OctoHoverRow extends StatelessWidget {
  const OctoHoverRow({
    super.key,
    required this.child,
    this.onTap,
    this.selected = false,
    this.padding = const EdgeInsets.symmetric(
      horizontal: CockpitSpacing.md,
      vertical: CockpitSpacing.md,
    ),
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool selected;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(CockpitRadii.md);
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.10)
          : Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        hoverColor: scheme.onSurface.withValues(alpha: 0.05),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// A subtle, borderless pill chip (topics, tags).
class OctoChip extends StatelessWidget {
  const OctoChip(this.label, {super.key});
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
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
      ),
      child: Text(label,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}

/// The solid red "LIVE" badge — a filled pill, no ring.
class LiveDot extends StatelessWidget {
  const LiveDot({super.key, this.label = 'LIVE'});
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CockpitSpacing.md,
        vertical: CockpitSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, size: 8, color: Colors.white),
          const SizedBox(width: CockpitSpacing.xs),
          Text(label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  )),
        ],
      ),
    );
  }
}

/// A stand-in audio waveform — a row of bars at varying heights.
class Waveform extends StatelessWidget {
  const Waveform({super.key, this.width = 200});
  final double width;

  static const _heights = <double>[
    8, 16, 24, 14, 30, 20, 36, 12, 26, 18, 34, 10, 22, 28, 16, 32, 14, 24, 8, 20,
  ];

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 40,
      width: width,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final h in _heights)
            Container(
              width: 3,
              height: h,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(CockpitRadii.pill),
              ),
            ),
        ],
      ),
    );
  }
}
