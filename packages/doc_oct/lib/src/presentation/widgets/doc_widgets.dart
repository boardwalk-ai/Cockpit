import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';

import '../../theme/doc_tokens.dart';

/// Borderless building blocks for Doc Oct — grouping via whitespace + subtle
/// background, never outlines or shadows. Mirrors OctoNotes' `octo_widgets`,
/// kept local so Doc Oct stays self-contained.

/// A small, muted, letter-spaced section label — the docs-style "eyebrow" that
/// opens every section (the workhorse of grouping).
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
        letterSpacing: 1.2,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// The one sanctioned subtle background — a soft rounded fill, no border, no
/// shadow. For things that should feel slightly raised (a highlighted item).
class DocSurface extends StatelessWidget {
  const DocSurface({
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

/// An interactive row with no border — affordance comes from a hover fill (and
/// an optional selected red tint), never an outline or divider.
class DocHoverRow extends StatelessWidget {
  const DocHoverRow({
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

/// A subtle, borderless pill chip (tags, meta).
class DocChip extends StatelessWidget {
  const DocChip(this.label, {super.key, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onColor = color ?? theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CockpitSpacing.md,
        vertical: CockpitSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color == null
            ? theme.colorScheme.surfaceContainerHighest
            : color!.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: onColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// The citation style, shown the borderless way: a small colored dot + label.
class StyleTag extends StatelessWidget {
  const StyleTag(this.style, {super.key, this.dense = false});
  final FormatStyle style;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: dense ? 7 : 8,
          height: dense ? 7 : 8,
          decoration: BoxDecoration(color: style.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: CockpitSpacing.sm),
        Text(
          dense ? style.short : style.label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// A citation style's logo: a small rounded-square badge in the style's colour
/// (lit gradient, hairline highlight) carrying its initial in the document
/// serif — the face the papers themselves are set in. Dimmed when [active] is
/// false (e.g. an unselected pill); glows softly when active.
class StyleMonogram extends StatelessWidget {
  const StyleMonogram(
    this.style, {
    super.key,
    this.size = 20,
    this.active = true,
  });

  final FormatStyle style;
  final double size;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = style.color;
    final tone = active ? c : Color.lerp(c, const Color(0xFF8A8F8F), 0.5)!;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(tone, Colors.white, 0.22)!,
            Color.lerp(tone, Colors.black, 0.2)!,
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: active ? 0.22 : 0.1),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: c.withValues(alpha: active ? 0.45 : 0),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        style.abbr,
        style: TextStyle(
          fontFamily: 'packages/doc_oct/Tinos',
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.62,
          height: 1,
          color: Colors.white.withValues(alpha: active ? 1 : 0.8),
        ),
      ),
    );
  }
}
