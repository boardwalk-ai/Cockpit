import 'package:cockpit_module/cockpit_module.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../home/cockpit_home_page.dart';
import '../modules/registered_modules.dart';
import '../settings/settings_page.dart';

/// Builds the app router from the shell routes plus every active module's route
/// subtree. Rebuilds when the active module set changes (e.g. a feature flag is
/// toggled), so detaching a module also removes its routes.
final routerProvider = Provider<GoRouter>((ref) {
  final modules = ref.watch(activeModulesProvider);
  final registry = ModuleRegistry(modules);

  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const CockpitHomePage()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
      ...registry.allRoutes(),
    ],
  );
});
