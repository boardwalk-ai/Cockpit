import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';

import 'motion.dart';

/// How loud a [DocButton] is. One primary per area; tonal for secondary
/// actions that still deserve colour; quiet for everything else.
enum DocButtonKind { primary, tonal, quiet }

/// The editor's button — one height, one type style (the app font, never the
/// browser default), and the shared press/hover feel.
///
/// * primary — lit red: a soft top highlight, a lower edge and a red glow.
/// * tonal   — red label on a faint red tint.
/// * quiet   — hairline outline, neutral label.
class DocButton extends StatelessWidget {
  const DocButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.kind = DocButtonKind.quiet,
    this.busy = false,
    this.expand = false,
    this.height = 32,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final DocButtonKind kind;

  /// Shows a small spinner in place of the icon.
  final bool busy;

  /// Fill the available width (e.g. a panel's main action).
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onTap != null && !busy;
    final radius = BorderRadius.circular(height / 2);
    final red = scheme.primary;

    final (Color fg, Decoration deco) = switch (kind) {
      DocButtonKind.primary => (
        Colors.white,
        BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(red, Colors.white, 0.12)!,
              red,
              Color.lerp(red, Colors.black, 0.14)!,
            ],
            stops: const [0, 0.55, 1],
          ),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
          ),
          boxShadow: [
            BoxShadow(
              color: red.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
      ),
      DocButtonKind.tonal => (
        red,
        BoxDecoration(
          borderRadius: radius,
          color: red.withValues(alpha: 0.12),
          border: Border.all(color: red.withValues(alpha: 0.28)),
        ),
      ),
      DocButtonKind.quiet => (
        scheme.onSurface.withValues(alpha: 0.85),
        BoxDecoration(
          borderRadius: radius,
          color: scheme.onSurface.withValues(alpha: 0.03),
          border: Border.all(color: scheme.onSurface.withValues(alpha: 0.12)),
        ),
      ),
    };

    final label = Text(
      this.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelLarge?.copyWith(
        color: fg,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
    );

    return Pressable(
      enabled: enabled,
      glowColor: kind == DocButtonKind.primary ? red : null,
      borderRadius: radius,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: onTap == null ? 0.45 : 1,
        child: DecoratedBox(
          decoration: deco,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: enabled ? onTap : null,
              borderRadius: radius,
              child: SizedBox(
                height: height,
                width: expand ? double.infinity : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CockpitSpacing.md,
                  ),
                  child: Row(
                    mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (busy)
                        SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: fg,
                          ),
                        )
                      else if (icon != null)
                        Icon(icon, size: 15, color: fg),
                      if (busy || icon != null) const SizedBox(width: 7),
                      Flexible(child: label),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
