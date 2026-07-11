import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Module / feature toggles for the super-app.
///
/// `studyStudioEnabled` is the detach switch from the brief
/// (`study_studio_enabled = yes/no`). Add more module flags here as the
/// Cockpit grows.
@immutable
class FeatureFlags {
  const FeatureFlags({
    this.studyStudioEnabled = true,
  });

  final bool studyStudioEnabled;

  FeatureFlags copyWith({bool? studyStudioEnabled}) {
    return FeatureFlags(
      studyStudioEnabled: studyStudioEnabled ?? this.studyStudioEnabled,
    );
  }
}

/// Runtime-mutable flags. Seed from [FeatureFlags] defaults; can later be
/// hydrated from backend RemoteConfig (`GET /config`) or local overrides.
class FeatureFlagsController extends Notifier<FeatureFlags> {
  @override
  FeatureFlags build() => const FeatureFlags();

  void setStudyStudioEnabled(bool value) =>
      state = state.copyWith(studyStudioEnabled: value);

  void replace(FeatureFlags flags) => state = flags;
}

final featureFlagsProvider =
    NotifierProvider<FeatureFlagsController, FeatureFlags>(FeatureFlagsController.new);
