import 'dart:async';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ghostwriter/ghostwriter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_studio/study_studio.dart' show StudyPush;

/// GhostWriter's view of the app's push notifications: Firebase Cloud
/// Messaging on Android and iOS. Null on the web, on desktop, and on a build
/// with no Firebase config, where GhostWriter then runs without notifications.
final ghostWriterPushProvider = Provider<GwPush?>((ref) {
  if (kIsWeb || Firebase.apps.isEmpty) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => FirebaseGwPush('android'),
    TargetPlatform.iOS => FirebaseGwPush('ios'),
    _ => null,
  };
});

/// The same Firebase messaging, for Study Studio (one install id, one token).
final studyPushImplProvider = Provider<StudyPush?>(
  (ref) => switch (ref.watch(ghostWriterPushProvider)) {
    final StudyPush push => push,
    _ => null,
  },
);

/// Where a tapped notification asks to go (`data.link`, e.g. `/study/<id>`;
/// an announcement from the admin app opens Home).
Stream<String> notificationLinks(GwPush? push) => push == null
    ? const Stream.empty()
    : push.opened
          .map(
            (data) =>
                data['type'] == 'announcement' ? '/' : (data['link'] ?? ''),
          )
          .where((link) => link == '/' || link.startsWith('/study/'));

class FirebaseGwPush implements GwPush, StudyPush {
  FirebaseGwPush(this.platform);

  static const _deviceIdKey = 'ghostwriter.deviceId';

  @override
  final String platform;

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  @override
  Future<String> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_deviceIdKey);
    if (saved != null) return saved;
    final id = _uuid();
    await prefs.setString(_deviceIdKey, id);
    return id;
  }

  @override
  Future<String?> token({required bool ask}) async {
    final settings = ask
        ? await _messaging.requestPermission()
        : await _messaging.getNotificationSettings();
    final allowed =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!allowed) return null;
    // On iOS the FCM token only exists once Apple has given its own.
    if (platform == 'ios' && await _messaging.getAPNSToken() == null) {
      return null;
    }
    return _messaging.getToken();
  }

  @override
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;

  /// The notification that launched the app, if one did (asked once).
  late final Future<RemoteMessage?> _launch = _messaging.getInitialMessage();

  /// Every listener (GhostWriter, the app's links) gets the launch
  /// notification and each one tapped after; each takes its own.
  @override
  late final Stream<Map<String, String>> opened = Stream.multi((out) async {
    final launch = await _launch;
    if (launch != null) out.add(_data(launch));
    final taps = FirebaseMessaging.onMessageOpenedApp
        .map(_data)
        .listen(out.add, onError: out.addError);
    out.onCancel = taps.cancel;
  });

  static Map<String, String> _data(RemoteMessage message) => {
    for (final entry in message.data.entries) entry.key: '${entry.value}',
  };

  /// A random (version 4) UUID.
  static String _uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
