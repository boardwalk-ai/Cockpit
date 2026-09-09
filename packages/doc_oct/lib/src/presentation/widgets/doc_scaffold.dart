import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';

/// Borderless page frame for every Doc Oct screen: paints the page surface and
/// floats the shared [ThemeSwitcher] (light · system · dark) in the bottom-right
/// corner — present on every page.
class DocScaffold extends StatelessWidget {
  const DocScaffold({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: Stack(
        children: [
          Positioned.fill(child: child),
          const Positioned(
            right: CockpitSpacing.xl,
            bottom: CockpitSpacing.lg,
            child: SafeArea(child: ThemeSwitcher()),
          ),
        ],
      ),
    );
  }
}
