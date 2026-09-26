import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../modules/registered_modules.dart';
import '../widgets/account_button.dart';
import '../widgets/responsive.dart';

/// Where each app lives when it is hosted on its own subdomain
/// (`--dart-define=OCTONOTES_URL=https://notes.octopilothub.com` …). Unset =
/// open the module inside this app (local dev).
const _appUrls = <String, String>{
  'octo_notes': String.fromEnvironment('OCTONOTES_URL'),
  'study_studio': String.fromEnvironment('STUDY_STUDIO_URL'),
};

void _open(BuildContext context, String moduleId, String rootPath) {
  final url = _appUrls[moduleId] ?? '';
  if (url.isEmpty) {
    context.go(rootPath);
  } else {
    launchUrl(Uri.parse(url), webOnlyWindowName: '_self');
  }
}

/// Cockpit Home — the super-app launcher. One tile per active module.
class CockpitHomePage extends ConsumerWidget {
  const CockpitHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modules = ref.watch(activeModulesProvider);
    final theme = Theme.of(context);
    final desktop = isAppDesktop(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Octopilot Cockpit'),
        actions: [
          const AccountButton(),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      body: modules.isEmpty
          ? EmptyState(
              icon: Icons.extension_off_outlined,
              title: 'No modules enabled',
              message: 'Enable a module in Settings to get started.',
              action: FilledButton(
                onPressed: () => context.go('/settings'),
                child: const Text('Open Settings'),
              ),
            )
          : ListView(
              padding: desktop
                  ? const EdgeInsets.fromLTRB(
                      CockpitSpacing.xxl,
                      CockpitSpacing.xl,
                      CockpitSpacing.xxl,
                      CockpitSpacing.xl,
                    )
                  : const EdgeInsets.all(CockpitSpacing.lg),
              children: [
                AppContentColumn(
                  maxWidth: 1160,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your apps', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: CockpitSpacing.lg),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 260,
                              mainAxisSpacing: CockpitSpacing.lg,
                              crossAxisSpacing: CockpitSpacing.lg,
                              mainAxisExtent: 150,
                            ),
                        itemCount: modules.length,
                        itemBuilder: (context, index) {
                          final m = modules[index];
                          return CockpitCard(
                            onTap: () => _open(context, m.id, m.rootPath),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  backgroundColor:
                                      (m.accentColor ??
                                              theme.colorScheme.primary)
                                          .withValues(alpha: 0.15),
                                  child: Icon(
                                    m.icon,
                                    color:
                                        m.accentColor ??
                                        theme.colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: CockpitSpacing.md),
                                // Expanded bounds the text block to the leftover
                                // height so a fixed-height grid cell can never
                                // overflow, regardless of column width / wrapping.
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        m.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleMedium,
                                      ),
                                      const SizedBox(
                                        height: CockpitSpacing.xxs,
                                      ),
                                      Text(
                                        m.description,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
