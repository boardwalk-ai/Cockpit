import 'dart:async';
import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../access/app_access.dart' show controlApiUrl;

/// Where this phone stands with notifications.
enum PushState {
  /// Not checked yet, or signed out.
  unknown,

  /// The server has this phone's token: announcements reach it.
  registered,

  /// Notifications aren't allowed yet; asking can turn them on.
  needsPermission,

  /// Turned off for good in the phone's settings; only Settings can fix it.
  blocked,

  /// Allowed, but no token or the server couldn't be told. Retried.
  failed,
}

/// Keeps the server's record of this phone exact (`PUT /v1/app/devices` on
/// the admin API): on sign-in, every time the app comes to the front, and
/// whenever the push token changes. A phone that *can't* get notifications
/// is reported too, with why, so the admin app shows every phone's real
/// state. A failure is retried until it works.
class DeviceRegistrar with WidgetsBindingObserver {
  DeviceRegistrar({
    required this.idToken,
    required this.deviceId,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final Future<String?> Function() idToken;

  /// The install id (made once, kept).
  final Future<String> Function() deviceId;
  final http.Client _client;

  final ValueNotifier<PushState> state = ValueNotifier(PushState.unknown);

  /// The last reason it didn't work, for the screen and the server.
  String? lastError;

  bool _signedIn = false;
  bool _observing = false;
  StreamSubscription<String>? _refreshes;
  Future<void>? _running;
  bool _again = false;
  Timer? _retry;
  int _failures = 0;
  Map<String, String?>? _device;

  static bool get supported =>
      controlApiUrl.isNotEmpty &&
      !kIsWeb &&
      Firebase.apps.isNotEmpty &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Signed in: register now and keep it so.
  void start() {
    if (!supported) return;
    _signedIn = true;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _refreshes ??= FirebaseMessaging.instance.onTokenRefresh.listen(
      (_) => unawaited(sync()),
    );
    unawaited(sync());
  }

  /// Signing out (call while the sign-in still works): this phone stops
  /// getting the account's announcements.
  Future<void> signOut() async {
    _signedIn = false;
    _retry?.cancel();
    state.value = PushState.unknown;
    if (!supported) return;
    try {
      final token = await idToken();
      if (token == null) return;
      await _client
          .delete(
            Uri.parse('$controlApiUrl/v1/app/devices/${await deviceId()}'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 8));
    } on Object catch (e) {
      debugPrint('push: sign-out report failed: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Settings (permission may have changed), or just reopened:
    // the server learns the phone is alive, and anything new.
    if (state == AppLifecycleState.resumed && _signedIn) unawaited(sync());
  }

  /// Asks for notifications (the system dialog), or opens the app's
  /// settings when Android won't ask again. Then registers.
  Future<void> askPermission() async {
    if (state.value == PushState.blocked) {
      await openAppSettings();
      return; // Registered on return (resumed).
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await FirebaseMessaging.instance.requestPermission();
    } else {
      await Permission.notification.request();
    }
    await sync();
  }

  /// One check at a time; a call during one runs once more after it.
  Future<void> sync() {
    if (_running != null) {
      _again = true;
      return _running!;
    }
    return _running = _sync().whenComplete(() {
      _running = null;
      if (_again) {
        _again = false;
        unawaited(sync());
      }
    });
  }

  Future<void> _sync() async {
    if (!_signedIn) return;
    final perm = await Permission.notification.status;
    if (!perm.isGranted && !perm.isProvisional) {
      final blocked = perm.isPermanentlyDenied || perm.isRestricted;
      lastError = 'notifications not allowed ($perm)';
      state.value = blocked ? PushState.blocked : PushState.needsPermission;
      await _report(status: 'permission_denied', error: lastError);
      return;
    }
    String? token;
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS &&
          await FirebaseMessaging.instance.getAPNSToken() == null) {
        throw StateError('no APNs token yet');
      }
      token = await FirebaseMessaging.instance.getToken().timeout(
        const Duration(seconds: 30),
      );
      if (token == null || token.isEmpty) throw StateError('FCM gave no token');
    } on Object catch (e) {
      lastError = 'token: $e';
      state.value = PushState.failed;
      await _report(status: 'token_error', error: lastError);
      _scheduleRetry();
      return;
    }
    if (await _report(status: 'registered', token: token)) {
      lastError = null;
      _failures = 0;
      state.value = PushState.registered;
    } else {
      state.value = PushState.failed;
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (!_signedIn) return;
    const waits = [5, 15, 60, 300];
    final wait = waits[_failures.clamp(0, waits.length - 1)];
    _failures++;
    _retry?.cancel();
    _retry = Timer(Duration(seconds: wait), () => unawaited(sync()));
  }

  /// Tells the server; true when it took it.
  Future<bool> _report({
    required String status,
    String? token,
    String? error,
  }) async {
    try {
      final auth = await idToken();
      if (auth == null) return false;
      final res = await _client
          .put(
            Uri.parse('$controlApiUrl/v1/app/devices'),
            headers: {
              'Authorization': 'Bearer $auth',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'id': await deviceId(),
              'token': token,
              'status': status,
              'error': error,
              ...await _deviceInfo(),
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return true;
      lastError = 'server ${res.statusCode}: ${res.body}';
    } on Object catch (e) {
      lastError = 'server unreachable: $e';
    }
    debugPrint('push: report failed: $lastError');
    return false;
  }

  Future<Map<String, String?>> _deviceInfo() async {
    if (_device != null) return _device!;
    final info = DeviceInfoPlugin();
    final app = await PackageInfo.fromPlatform();
    final version = '${app.version}+${app.buildNumber}';
    if (defaultTargetPlatform == TargetPlatform.android) {
      final a = await info.androidInfo;
      return _device = {
        'platform': 'android',
        'manufacturer': a.manufacturer,
        'model': a.model,
        'osVersion': 'Android ${a.version.release} (SDK ${a.version.sdkInt})',
        'appVersion': version,
      };
    }
    final i = await info.iosInfo;
    return _device = {
      'platform': 'ios',
      'manufacturer': 'Apple',
      'model': i.utsname.machine,
      'osVersion': '${i.systemName} ${i.systemVersion}',
      'appVersion': version,
    };
  }

  void dispose() {
    _retry?.cancel();
    _refreshes?.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    state.dispose();
  }
}
