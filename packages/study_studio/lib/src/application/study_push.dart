import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/repositories/studio_repository.dart';
import '../domain/study_plan.dart';
import 'providers.dart';

/// The push notifications Study Studio needs from its host app (the app
/// owns the messaging plugin), like [StudyVoice] for the microphone.
abstract interface class StudyPush {
  /// `android`, `ios` or `web`.
  String get platform;

  /// An id made once for this install and kept.
  Future<String> deviceId();

  /// The token the server pushes to, or null when notifications are not
  /// allowed. With [ask] the user is asked for permission if they haven't
  /// decided yet.
  Future<String?> token({required bool ask});

  /// A new token, whenever the platform replaces the old one.
  Stream<String> get tokenRefreshes;
}

/// None unless the host app overrides it (the web, tests: no push).
final studyPushProvider = Provider<StudyPush?>((ref) => null);

/// Keeps the server's record of this phone up to date while someone is
/// signed in, and tells it the study plans it reminds about.
final studyPushLinkProvider = Provider<StudyPushLink?>((ref) {
  final push = ref.watch(studyPushProvider);
  if (push == null) return null;
  final link = StudyPushLink(push, () => ref.read(studioRepositoryProvider));
  ref.onDispose(link.dispose);
  return link;
});

class StudyPushLink {
  StudyPushLink(this.push, this._repo, {int Function()? tzMinutes})
    : _tz = tzMinutes ?? (() => DateTime.now().timeZoneOffset.inMinutes);

  final StudyPush push;
  final StudioRepository Function() _repo;
  final int Function() _tz;

  StreamSubscription<String>? _refreshes;
  String? _registered;

  /// Starts listening; registers the phone if notifications are already
  /// allowed (the user isn't asked here). Call once signed in.
  void start() {
    _refreshes ??= push.tokenRefreshes.listen(
      (token) => unawaited(_register(token, force: true)),
    );
    unawaited(sync(ask: false));
  }

  /// Registers this phone. With [ask], asks for permission first if the
  /// user hasn't decided: when they start a build or turn on reminders.
  Future<void> sync({required bool ask}) async {
    try {
      final token = await push.token(ask: ask);
      if (token != null) await _register(token);
    } on Object {
      // No notifications this time; the app works without them.
    }
  }

  Future<void> _register(String token, {bool force = false}) async {
    if (token == _registered && !force) return;
    try {
      await _repo().registerDevice(
        id: await push.deviceId(),
        token: token,
        platform: push.platform,
        tzMinutes: _tz(),
      );
      _registered = token;
    } on Object {
      // Tried again on the next sync (an older server doesn't know devices).
    }
  }

  /// The studio's plan, for its reminders. Asks for notifications when the
  /// user has just chosen a reminder time.
  Future<void> savePlan(
    String studioId,
    PlanSettings settings, {
    required bool chosen,
  }) async {
    if (chosen && settings.remind != null) await sync(ask: true);
    try {
      await _repo().savePlan(studioId, settings.toApi(_tz()));
    } on Object {
      // Sent again the next time the plan opens.
    }
  }

  /// No more notifications on this phone. Call before signing out, while
  /// the sign-in still works.
  Future<void> unregister() async {
    _registered = null;
    try {
      await _repo().removeDevice(await push.deviceId());
    } on Object {
      // The server forgets the phone when its token dies.
    }
  }

  void dispose() => _refreshes?.cancel();
}
