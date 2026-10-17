import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_providers.dart';

/// This install as an OctoNotes device: an id made once and kept, registered
/// with the backend (`POST /v1/devices`) so it can host or record sessions.
class ThisDevice {
  const ThisDevice({required this.id, required this.name, required this.platform});

  final String id;
  final String name;
  final String platform;

  static const _key = 'octonotes.deviceId';

  static String get _platform => kIsWeb
      ? 'web'
      : switch (defaultTargetPlatform) {
          TargetPlatform.android => 'android',
          TargetPlatform.iOS => 'ios',
          TargetPlatform.macOS => 'macos',
          TargetPlatform.windows => 'windows',
          _ => 'linux',
        };

  static String get _name => switch (_platform) {
        'android' => 'Android phone',
        'ios' => 'iPhone',
        'web' => 'Browser',
        'macos' => 'Mac',
        'windows' => 'Windows PC',
        _ => 'Computer',
      };

  static Future<String> _id() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null) return saved;
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    final id = '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
    await prefs.setString(_key, id);
    return id;
  }
}

/// This device, registered when there's a backend (once per app run).
final thisDeviceProvider = FutureProvider<ThisDevice>((ref) async {
  final device = ThisDevice(
    id: await ThisDevice._id(),
    name: ThisDevice._name,
    platform: ThisDevice._platform,
  );
  final api = ref.watch(octoNotesApiProvider);
  if (api != null) {
    await api.registerDevice(device.id, device.name, device.platform);
  }
  return device;
});
