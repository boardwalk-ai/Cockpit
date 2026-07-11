import 'package:cockpit_core/cockpit_core.dart';
import 'package:cockpit_module/cockpit_module.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:study_studio/study_studio.dart';

/// The set of modules currently mounted in the super-app, after applying
/// feature flags. This is the single place that knows which modules exist —
/// add new modules here, each gated by its flag.
///
/// `study_studio` is gated by `study_studio_enabled` (the detach switch). Flip
/// the flag and the module's tile + routes disappear; remove the import and the
/// package dependency and the shell still compiles (it only depends on the
/// CockpitModule interface).
final activeModulesProvider = Provider<List<CockpitModule>>((ref) {
  final flags = ref.watch(featureFlagsProvider);
  return [
    if (flags.studyStudioEnabled) const StudyStudioModule(),
  ];
});
