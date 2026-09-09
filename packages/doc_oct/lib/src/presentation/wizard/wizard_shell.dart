import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';

import '../widgets/doc_widgets.dart';

/// The wizard frame, restyled borderless. Keeps the web's two-part composition —
/// a left context rail (brand · eyebrow · display headline · step tracker) and a
/// right content column — but strips the grid, glows and number watermark; the
/// charcoal page + whitespace do the work.
class WizardShell extends StatelessWidget {
  const WizardShell({
    super.key,
    required this.step,
    required this.eyebrow,
    required this.headline,
    required this.child,
    this.onBack,
    this.scroll = false,
  });

  /// 1..3
  final int step;
  final String eyebrow;

  /// Rich display headline (may carry a red span).
  final Widget headline;
  final Widget child;
  final VoidCallback? onBack;

  /// When true the content column can overflow and scrolls (top-aligned)
  /// instead of vertically centering — used by the taller Analysis step.
  final bool scroll;

  static const _labels = ['Topic', 'Setup', 'Analysis'];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final rail = Padding(
      padding: EdgeInsets.all(wide ? CockpitSpacing.xxxl : CockpitSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _BrandLockup(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.4,
                    ),
              ),
              const SizedBox(height: CockpitSpacing.lg),
              DefaultTextStyle.merge(
                style: (wide
                        ? Theme.of(context).textTheme.displaySmall
                        : Theme.of(context).textTheme.headlineMedium)
                    ?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.04,
                  letterSpacing: -0.5,
                ),
                child: headline,
              ),
            ],
          ),
          _StepTracker(step: step, label: _labels[step - 1]),
        ],
      ),
    );

    // Vertically center the content only when it fits (wide, non-scroll);
    // otherwise top-align so it can grow and scroll.
    final centered = wide && !scroll;
    final content = Padding(
      padding: EdgeInsets.all(wide ? CockpitSpacing.xxxl : CockpitSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: centered ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment:
            centered ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          if (onBack != null) ...[
            _BackButton(onTap: onBack!),
            const SizedBox(height: CockpitSpacing.xl),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: child,
          ),
        ],
      ),
    );

    if (!wide) {
      return ListView(
        children: [rail, content],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: rail),
        Expanded(
          child: scroll ? SingleChildScrollView(child: content) : content,
        ),
      ],
    );
  }
}

class _BrandLockup extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(CockpitRadii.sm),
          ),
          alignment: Alignment.center,
          child: const Text('O',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15)),
        ),
        const SizedBox(width: CockpitSpacing.sm),
        Text(
          'OCTOPILOT · DOC OCT',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                letterSpacing: 2.2,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

class _StepTracker extends StatelessWidget {
  const _StepTracker({required this.step, required this.label});
  final int step;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget dot(int n) {
      final active = n == step;
      final done = n < step;
      return Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? scheme.primary
              : done
                  ? scheme.onSurface.withValues(alpha: 0.14)
                  : Colors.transparent,
        ),
        child: done
            ? Icon(Icons.check_rounded,
                size: 14, color: scheme.onSurface.withValues(alpha: 0.7))
            : Text(
                '$n',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: active
                      ? Colors.white
                      : scheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
      );
    }

    return Row(
      children: [
        for (var n = 1; n <= 3; n++) ...[
          dot(n),
          if (n < 3)
            Container(
              width: 26,
              height: 1,
              margin:
                  const EdgeInsets.symmetric(horizontal: CockpitSpacing.sm),
              color: n < step
                  ? scheme.primary.withValues(alpha: 0.5)
                  : scheme.onSurface.withValues(alpha: 0.1),
            ),
        ],
        const SizedBox(width: CockpitSpacing.md),
        Text(label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                )),
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DocHoverRow(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.sm, vertical: CockpitSpacing.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chevron_left_rounded,
              size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 2),
          Text('Back',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
