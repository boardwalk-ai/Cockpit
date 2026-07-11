import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'routing/app_router.dart';

/// Root of the Octopilot Cockpit super-app. Wires the global theme controls and
/// the module-aware router.
class CockpitApp extends ConsumerWidget {
  const CockpitApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeControllerProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Octopilot Cockpit',
      debugShowCheckedModeBanner: false,
      theme: themeState.light,
      darkTheme: themeState.dark,
      themeMode: themeState.mode,
      routerConfig: router,
    );
  }
}
