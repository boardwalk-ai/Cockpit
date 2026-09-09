import 'package:flutter/material.dart';

import '../../theme/doc_theme.dart';
import '../../theme/doc_tokens.dart';

/// A borderless elevated panel — the fundamental building block. No outline:
/// a filled, rounded surface that floats on a soft shadow. Optionally tappable
/// with a hover-lift (raises the surface + shadow) for web/desktop.
class DocPanel extends StatefulWidget {
  const DocPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(DocSpacing.lg),
    this.radius = DocRadii.lg,
    this.onTap,
    this.raised = false,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  /// Start from the raised surface instead of the resting one.
  final bool raised;
  final Color? color;

  @override
  State<DocPanel> createState() => _DocPanelState();
}

class _DocPanelState extends State<DocPanel> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = DocTheme.surfacesOf(context);
    final interactive = widget.onTap != null;
    final lifted = widget.raised || (_hover && interactive);
    final radius = BorderRadius.circular(widget.radius);

    Widget panel = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      transform: lifted && interactive
          ? (Matrix4.identity()..translateByDouble(0.0, -3.0, 0.0, 1.0))
          : Matrix4.identity(),
      decoration: BoxDecoration(
        color: widget.color ?? (lifted ? s.surfaceHigh : s.surface),
        borderRadius: radius,
        boxShadow: lifted ? s.shadowLift : s.shadowSoft,
      ),
      child: Padding(padding: widget.padding, child: widget.child),
    );

    if (!interactive) return panel;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(onTap: widget.onTap, child: panel),
    );
  }
}

/// A soft-tinted pill — used for the citation-style badge and meta tags. Filled
/// tint, no border.
class DocChip extends StatelessWidget {
  const DocChip({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.dense = false,
  });

  final String label;
  final Color? color;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.primary;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? DocSpacing.sm : DocSpacing.md,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(DocRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 12 : 14, color: c),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: c,
              fontSize: dense ? 11 : 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// The colored, rounded style badge (letter on a soft tint) for a citation
/// style — the borderless analogue of the web's square badge.
class DocStyleBadge extends StatelessWidget {
  const DocStyleBadge({super.key, required this.style, this.size = 40});
  final FormatStyle style;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            style.color.withValues(alpha: 0.9),
            Color.lerp(style.color, Colors.black, 0.35)!,
          ],
        ),
        borderRadius: BorderRadius.circular(size * 0.32),
        boxShadow: [
          BoxShadow(
            color: style.color.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        style.abbr,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}

/// Small uppercase section eyebrow used above titles.
class DocEyebrow extends StatelessWidget {
  const DocEyebrow(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 16, height: 2, color: scheme.primary),
        const SizedBox(width: DocSpacing.sm),
        Text(
          text.toUpperCase(),
          style: TextStyle(
            color: scheme.primary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.2,
          ),
        ),
      ],
    );
  }
}
