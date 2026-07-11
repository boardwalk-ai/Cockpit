import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Contract every pluggable Cockpit module implements.
///
/// The shell knows modules only through this contract — it never imports a
/// module's internals. That's what makes a module **detachable**: gate it with
/// a feature flag (hide), exclude it from the registered list (build), or remove
/// the package dependency entirely (physical) and the shell still compiles.
abstract class CockpitModule {
  const CockpitModule();

  /// Stable id, e.g. `study_studio`.
  String get id;

  /// Display name shown on the Cockpit Home launcher tile.
  String get title;

  /// One-line description for the launcher tile.
  String get description;

  /// Launcher icon.
  IconData get icon;

  /// Optional brand accent for this module's tile.
  Color? get accentColor;

  /// Root route this module owns, e.g. `/study`.
  String get rootPath;

  /// Whether the module is on by default (before any RemoteConfig override).
  bool get enabledByDefault;

  /// The module's go_router subtree, mounted into the app router.
  List<RouteBase> routes();

  /// One-time setup hook (register providers, warm caches). Optional.
  Future<void> init(Ref ref) async {}
}
