/// The push notifications GhostWriter needs from its host app. The app owns
/// the messaging plugin and hands GhostWriter this view of it, the same way
/// it hands over its sign-in ([GwAuth]).
abstract interface class GwPush {
  /// `android`, `ios` or `web`.
  String get platform;

  /// An id made once for this install and kept.
  Future<String> deviceId();

  /// The token the server pushes to, or null when notifications are not
  /// allowed. With [ask] the user is asked for permission if they have not
  /// decided yet; without it nothing is ever shown.
  Future<String?> token({required bool ask});

  /// A new token, whenever the platform replaces the old one.
  Stream<String> get tokenRefreshes;

  /// The data of each notification the user tapped (`type`, `projectId`,
  /// `runId`), including the one that opened the app.
  Stream<Map<String, String>> get opened;
}
