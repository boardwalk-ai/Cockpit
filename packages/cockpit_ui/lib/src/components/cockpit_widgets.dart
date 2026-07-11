import 'package:flutter/material.dart';

import '../tokens/spacing_tokens.dart';

/// A bordered surface card with consistent padding and tap support.
class CockpitCard extends StatelessWidget {
  const CockpitCard({
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
    final theme = Theme.of(context);
    return Material(
      color: theme.cardTheme.color,
      shape: (theme.cardTheme.shape as RoundedRectangleBorder?),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Small labelled metric (e.g. "58 Topics").
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.value, required this.label, this.icon});

  final String value;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null)
          Padding(
            padding: const EdgeInsets.only(bottom: CockpitSpacing.xs),
            child: Icon(icon, size: 18, color: theme.colorScheme.primary),
          ),
        Text(value, style: theme.textTheme.titleLarge),
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Section heading with optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: CockpitSpacing.md),
      child: Row(
        children: [
          Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A linear mastery / progress bar with percent label.
class MasteryBar extends StatelessWidget {
  const MasteryBar({super.key, required this.value, this.label});

  /// 0.0 – 1.0
  final double value;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = (value.clamp(0, 1) * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: CockpitSpacing.xs),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label!, style: theme.textTheme.bodySmall),
                Text('$pct%', style: theme.textTheme.labelMedium),
              ],
            ),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(CockpitRadii.pill),
          child: LinearProgressIndicator(
            value: value.clamp(0, 1).toDouble(),
            minHeight: 8,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

/// A circular progress ring with a centered percent label. Used on studio
/// cards to show mastery at a glance.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    this.size = 52,
    this.stroke = 5,
    this.color,
    this.label,
  });

  /// 0.0 – 1.0
  final double value;
  final double size;
  final double stroke;
  final Color? color;

  /// Overrides the default "NN%" label.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = value.clamp(0, 1).toDouble();
    final c = color ?? theme.colorScheme.primary;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: stroke,
              valueColor: AlwaysStoppedAnimation(
                theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: v,
              strokeWidth: stroke,
              strokeCap: StrokeCap.round,
              valueColor: AlwaysStoppedAnimation(c),
            ),
          ),
          Text(
            label ?? '${(v * 100).round()}%',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: size * 0.24,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small rounded tag (related topics, difficulty, etc.).
class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.label, this.onTap, this.color, this.icon});

  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.secondary;
    return InkWell(
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.md,
          vertical: CockpitSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(CockpitRadii.pill),
          border: Border.all(color: c.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: c),
              const SizedBox(width: CockpitSpacing.xs),
            ],
            Text(label, style: theme.textTheme.labelMedium?.copyWith(color: c)),
          ],
        ),
      ),
    );
  }
}

/// A 1–5 star rating used for difficulty / importance.
class StarMeter extends StatelessWidget {
  const StarMeter({super.key, required this.value, this.max = 5, this.color});

  final int value;
  final int max;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.tertiary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < max; i++)
          Icon(i < value ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 16, color: c),
      ],
    );
  }
}

/// Centered empty / placeholder state.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(CockpitSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: CockpitSpacing.lg),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: CockpitSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: CockpitSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
