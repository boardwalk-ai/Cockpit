import 'package:cockpit_core/cockpit_core.dart';
import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  static const _swatches = [
    Color(0xFF4F46E5), // indigo
    Color(0xFF0EA5E9), // sky
    Color(0xFF16A34A), // green
    Color(0xFFDC2626), // red
    Color(0xFFEA580C), // orange
    Color(0xFF7C3AED), // violet
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(featureFlagsProvider);
    final themeState = ref.watch(themeControllerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(CockpitSpacing.lg),
        children: [
          const SectionHeader(title: 'Modules'),
          CockpitCard(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              title: const Text('Study Studio'),
              subtitle: const Text('study_studio_enabled — detach the whole module'),
              value: flags.studyStudioEnabled,
              onChanged: (v) =>
                  ref.read(featureFlagsProvider.notifier).setStudyStudioEnabled(v),
            ),
          ),
          const SizedBox(height: CockpitSpacing.xl),
          const SectionHeader(title: 'Global controls · Theme'),
          CockpitCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Appearance', style: theme.textTheme.titleSmall),
                const SizedBox(height: CockpitSpacing.sm),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode)),
                    ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode)),
                  ],
                  selected: {themeState.mode},
                  onSelectionChanged: (s) =>
                      ref.read(themeControllerProvider.notifier).setMode(s.first),
                ),
                const SizedBox(height: CockpitSpacing.lg),
                Text('Primary color', style: theme.textTheme.titleSmall),
                const SizedBox(height: CockpitSpacing.sm),
                Wrap(
                  spacing: CockpitSpacing.md,
                  children: [
                    for (final c in _swatches)
                      InkWell(
                        borderRadius: BorderRadius.circular(CockpitRadii.pill),
                        onTap: () =>
                            ref.read(themeControllerProvider.notifier).setPrimary(c),
                        child: CircleAvatar(
                          backgroundColor: c,
                          radius: 18,
                          child: themeState.colors.primary == c
                              ? const Icon(Icons.check, color: Colors.white, size: 18)
                              : null,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: CockpitSpacing.xl),
          Text(
            'Tip: these controls live in cockpit_ui (tokens) and cockpit_core (flags). '
            'Later they can be driven by the backend GET /config.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
