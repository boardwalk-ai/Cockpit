import 'dart:async';

import '../gw_push.dart';
import 'gw_session.dart';

/// Keeps the server's record of this phone up to date, and opens the right
/// essay when a notification is tapped.
class GwPushLink {
  GwPushLink(this.push, this.session);

  final GwPush push;
  final GwSession session;

  StreamSubscription<String>? _refreshes;
  StreamSubscription<Map<String, String>>? _opened;
  String? _registered;

  /// Starts listening. Registers the phone now if notifications are already
  /// allowed; the user is not asked yet.
  void start() {
    _refreshes ??= push.tokenRefreshes.listen(
      (token) => unawaited(_register(token)),
    );
    _opened ??= push.opened.listen(_open);
    unawaited(sync(ask: false));
  }

  /// Registers this phone. With [ask], asks for permission first if the user
  /// has not decided: call it when a run starts, which is when a
  /// notification becomes useful.
  Future<void> sync({required bool ask}) async {
    try {
      final token = await push.token(ask: ask);
      if (token != null) await _register(token);
    } catch (_) {
      // No notifications this time; the app works without them.
    }
  }

  Future<void> _register(String token) async {
    if (token == _registered) return;
    try {
      await session.api.putDevice(await push.deviceId(), token, push.platform);
      _registered = token;
    } catch (_) {
      // Tried again on the next sync.
    }
  }

  /// Stops notifications for this phone. Call before signing out, while the
  /// sign-in still works.
  Future<void> unregister() async {
    _registered = null;
    try {
      await session.api.deleteDevice(await push.deviceId());
    } catch (_) {
      // The server forgets the phone when its token dies.
    }
  }

  void _open(Map<String, String> data) {
    final project = data['projectId'];
    if (project == null || project.isEmpty) return;
    if (project == session.projectId) {
      session.reconnect();
    } else {
      unawaited(session.openProject(project));
    }
  }

  void dispose() {
    _refreshes?.cancel();
    _opened?.cancel();
  }
}
