import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';

/// The single primary action per wizard step — a red pill with a trailing
/// arrow. Red is the one functional accent (per DESIGN.md); one per screen.
class WizardPrimaryButton extends StatelessWidget {
  const WizardPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.dense = false,
  });

  final String label;
  final VoidCallback? onPressed;

  /// A smaller variant for inline placement (e.g. the Analysis "Continue").
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.primary,
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: dense ? CockpitSpacing.lg : CockpitSpacing.xl,
            vertical: dense ? CockpitSpacing.sm : CockpitSpacing.md,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: (dense
                        ? theme.textTheme.labelLarge
                        : theme.textTheme.titleSmall)
                    ?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: CockpitSpacing.sm),
              Icon(Icons.arrow_forward_rounded,
                  size: dense ? 16 : 18, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
