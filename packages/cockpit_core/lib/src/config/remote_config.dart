import 'feature_flags.dart';

/// Snapshot returned by the backend `GET /config` endpoint: feature flags plus
/// (later) theme tokens. Stubbed for now so the app boots offline.
class RemoteConfig {
  const RemoteConfig({required this.flags});

  final FeatureFlags flags;

  static const RemoteConfig fallback = RemoteConfig(flags: FeatureFlags());
}

/// Abstraction over the config source. Swap [StubRemoteConfigService] for a
/// real implementation that calls `ApiClient` once the backend exists.
abstract interface class RemoteConfigService {
  Future<RemoteConfig> fetch();
}

class StubRemoteConfigService implements RemoteConfigService {
  const StubRemoteConfigService();

  @override
  Future<RemoteConfig> fetch() async => RemoteConfig.fallback;
}
