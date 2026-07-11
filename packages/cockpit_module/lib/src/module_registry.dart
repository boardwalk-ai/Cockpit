import 'package:go_router/go_router.dart';

import 'cockpit_module.dart';

/// Holds the set of *active* modules and aggregates what the shell needs from
/// them (routes today; could add nav entries, deep-link handlers, etc.).
///
/// The app builds this from the registered module list after applying feature
/// flags, so only enabled modules contribute anything.
class ModuleRegistry {
  ModuleRegistry(this.modules);

  final List<CockpitModule> modules;

  /// Flattened routes from every active module.
  List<RouteBase> allRoutes() => [
        for (final module in modules) ...module.routes(),
      ];

  CockpitModule? byId(String id) {
    for (final m in modules) {
      if (m.id == id) return m;
    }
    return null;
  }
}
