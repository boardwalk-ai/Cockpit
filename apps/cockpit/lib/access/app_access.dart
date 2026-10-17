import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// The test environment's admin API (`backend-rs/crates/admin-api`), e.g.
/// `https://gw-staging.octopilothub.com/control`. Empty: no gate (dev).
const controlApiUrl = String.fromEnvironment('CONTROL_API_URL');

/// Whether this account is let in, which parts of the app are on, and its
/// OctoCredits — as the admin app last set them.
@immutable
class AppAccess {
  const AppAccess({
    required this.invited,
    required this.flags,
    this.email,
    this.credits,
  });

  factory AppAccess.fromJson(Map<String, dynamic> j) => AppAccess(
    invited: j['invited'] == true,
    email: j['email'] as String?,
    credits: (j['credits'] as num?)?.toInt(),
    flags: {
      for (final e in ((j['flags'] as Map?) ?? const {}).entries)
        '${e.key}': e.value == true,
    },
  );

  final bool invited;
  final String? email;
  final int? credits;
  final Map<String, bool> flags;

  /// A flag the server hasn't sent counts as on.
  bool on(String flag) => flags[flag] ?? true;

  @override
  bool operator ==(Object other) =>
      other is AppAccess &&
      other.invited == invited &&
      other.email == email &&
      other.credits == credits &&
      mapEquals(other.flags, flags);

  @override
  int get hashCode => Object.hash(invited, email, credits, flags.length);
}

/// Asks the admin API every few seconds while signed in, so an admin's
/// change (an invitation, a flag, credits) shows up in the app at once.
class AppAccessWatcher {
  AppAccessWatcher({required this.idToken, http.Client? client})
    : _client = client ?? http.Client();

  final Future<String?> Function() idToken;
  final http.Client _client;

  /// Null while signed out, unknown, or without a gate.
  final ValueNotifier<AppAccess?> access = ValueNotifier(null);

  Timer? _timer;

  bool get enabled => controlApiUrl.isNotEmpty;

  void start() {
    if (!enabled) return;
    _timer?.cancel();
    _check();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _check());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    access.value = null;
  }

  Future<void> _check() async {
    try {
      final token = await idToken();
      if (token == null) return;
      final res = await _client
          .get(
            Uri.parse('$controlApiUrl/v1/app/access'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return;
      access.value = AppAccess.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>,
      );
    } on Object {
      // Offline for a moment: keep the last answer.
    }
  }

  void dispose() {
    _timer?.cancel();
    access.dispose();
  }
}
