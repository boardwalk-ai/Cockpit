import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/doc_theme.dart';
import '../../theme/doc_tokens.dart';
import '../../theme/theme_controller.dart';

/// App shell for every Doc Oct screen: paints the canvas and floats the
/// **theme switcher** in the bottom-right corner (present on every page).
class DocScaffold extends StatelessWidget {
  const DocScaffold({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = DocTheme.surfacesOf(context);
    return Scaffold(
      backgroundColor: s.canvas,
      body: Stack(
        children: [
          Positioned.fill(child: child),
          const Positioned(
            right: DocSpacing.xl,
            bottom: DocSpacing.xl,
            child: SafeArea(child: DocThemeSwitcher()),
          ),
        ],
      ),
    );
  }
}

/// A floating pill that toggles light/dark. Borderless — a glass surface on a
/// soft shadow, with a sliding thumb between a sun and a moon.
class DocThemeSwitcher extends ConsumerWidget {
  const DocThemeSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(docThemeControllerProvider);
    final isDark = mode == ThemeMode.dark;
    final s = DocTheme.surfacesOf(context);
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(DocRadii.pill),
        onTap: () => ref.read(docThemeControllerProvider.notifier).toggle(),
        child: Container(
          width: 96,
          height: 46,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: s.surfaceHigh,
            borderRadius: BorderRadius.circular(DocRadii.pill),
            boxShadow: s.shadowLift,
          ),
          child: Stack(
            children: [
              // sliding thumb
              AnimatedAlign(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                alignment:
                    isDark ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.45),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(
                    isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                    size: 19,
                    color: Colors.white,
                  ),
                ),
              ),
              // static icons underneath
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _ghostIcon(Icons.light_mode_rounded, !isDark, scheme),
                  _ghostIcon(Icons.dark_mode_rounded, isDark, scheme),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ghostIcon(IconData icon, bool active, ColorScheme scheme) => SizedBox(
        width: 36,
        height: 36,
        child: Icon(
          icon,
          size: 18,
          color: active
              ? Colors.transparent
              : scheme.onSurfaceVariant.withValues(alpha: 0.55),
        ),
      );
}
