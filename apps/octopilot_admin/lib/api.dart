import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// The test environment's admin API (`backend-rs/crates/admin-api`).
const adminApiUrl = String.fromEnvironment(
  'ADMIN_API_URL',
  defaultValue: 'https://gw-staging.octopilothub.com/control',
);

class ApiError implements Exception {
  ApiError(this.status, this.message, [this.code]);
  final int status;
  final String message;
  final String? code;
  @override
  String toString() => message;
}

class AdminUser {
  AdminUser(Map<String, dynamic> j)
    : id = j['id'] as String?,
      email = (j['email'] as String?) ?? '',
      name = j['name'] as String?,
      photoUrl = j['photoUrl'] as String?,
      credits = (j['credits'] as num?)?.toInt() ?? 0,
      invited = j['invited'] == true,
      admin = j['admin'] == true,
      note = j['note'] as String?,
      phones = (j['phones'] as num?)?.toInt() ?? 0,
      phonesSeen = (j['phonesSeen'] as num?)?.toInt() ?? 0;

  /// Null for an invited email that hasn't signed in yet.
  final String? id;
  final String email;
  final String? name;
  final String? photoUrl;
  final int credits;
  final bool invited;
  final bool admin;
  final String? note;

  /// Phones that can get announcements, and every phone ever seen.
  final int phones;
  final int phonesSeen;
}

/// One install of the test app, as it last reported itself.
class Phone {
  Phone(Map<String, dynamic> j)
    : status = j['status'] as String,
      error = j['error'] as String?,
      manufacturer = j['manufacturer'] as String?,
      model = j['model'] as String?,
      osVersion = j['osVersion'] as String?,
      appVersion = j['appVersion'] as String?,
      ip = j['ip'] as String?,
      lastSeen = DateTime.tryParse(j['lastSeen'] as String? ?? '');

  /// registered | permission_denied | token_error | signed_out
  final String status;
  final String? error;
  final String? manufacturer;
  final String? model;
  final String? osVersion;
  final String? appVersion;
  final String? ip;
  final DateTime? lastSeen;
}

class Flag {
  Flag(Map<String, dynamic> j)
    : key = j['key'] as String,
      enabled = j['enabled'] == true,
      emails = [for (final e in (j['emails'] as List? ?? const [])) '$e'],
      description = j['description'] as String?,
      updatedBy = j['updatedBy'] as String?;

  final String key;
  final bool enabled;
  final List<String> emails;
  final String? description;
  final String? updatedBy;
}

class Setting {
  Setting(Map<String, dynamic> j)
    : key = j['key'] as String,
      value = j['value'] as String?;
  final String key;
  final String? value;
}

class AuditEntry {
  AuditEntry(Map<String, dynamic> j)
    : admin = j['admin'] as String,
      action = j['action'] as String,
      target = j['target'] as String?,
      detail = j['detail'],
      at = DateTime.tryParse(j['at'] as String? ?? '');
  final String admin;
  final String action;
  final String? target;
  final Object? detail;
  final DateTime? at;
}

class AdminApi {
  AdminApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<Object?> callJson(String method, String path, [Object? body]) =>
      _call(method, path, body);

  Future<Object?> _call(String method, String path, [Object? body]) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) throw ApiError(401, 'Signed out.');
    final req = http.Request(method, Uri.parse('$adminApiUrl$path'))
      ..headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final res = await http.Response.fromStream(
      await _client.send(req).timeout(const Duration(seconds: 20)),
    );
    if (res.statusCode == 204) return null;
    final Object? data = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 400) {
      final m = data is Map ? data : const {};
      throw ApiError(
        res.statusCode,
        (m['error'] ?? m['message'] ?? 'Error ${res.statusCode}').toString(),
        m['code'] as String?,
      );
    }
    return data;
  }

  Future<String> me() async =>
      ((await _call('GET', '/v1/admin/me')) as Map)['email'] as String;

  Future<(bool openAccess, List<AdminUser>)> users([String q = '']) async {
    final j =
        (await _call('GET', '/v1/admin/users?q=${Uri.encodeQueryComponent(q)}'))
            as Map<String, dynamic>;
    return (
      j['openAccess'] == true,
      [
        for (final u in j['users'] as List)
          AdminUser(u as Map<String, dynamic>),
      ],
    );
  }

  Future<void> allow(String email, {String? note}) =>
      _call('POST', '/v1/admin/allowlist', {'email': email, 'note': note});

  Future<void> disallow(String email) =>
      _call('DELETE', '/v1/admin/allowlist/${Uri.encodeComponent(email)}');

  Future<int> moveCredits(String userId, int delta, String reason) async =>
      (((await _call('POST', '/v1/admin/users/$userId/credits', {
                    'delta': delta,
                    'reason': reason,
                  }))
                  as Map)['balance']
              as num)
          .toInt();

  Future<List<Flag>> flags() async => [
    for (final f in (await _call('GET', '/v1/admin/flags')) as List)
      Flag(f as Map<String, dynamic>),
  ];

  Future<void> putFlag(
    String key, {
    required bool enabled,
    List<String>? emails,
    String? description,
  }) => _call('PUT', '/v1/admin/flags/$key', {
    'enabled': enabled,
    'emails': ?emails,
    'description': ?description,
  });

  Future<List<Setting>> settings() async => [
    for (final s in (await _call('GET', '/v1/admin/settings')) as List)
      Setting(s as Map<String, dynamic>),
  ];

  Future<void> putSetting(String key, String? value) =>
      _call('PUT', '/v1/admin/settings/$key', {'value': value});

  Future<List<AuditEntry>> audit() async => [
    for (final a in (await _call('GET', '/v1/admin/audit?limit=200')) as List)
      AuditEntry(a as Map<String, dynamic>),
  ];
}

class SentNotice {
  SentNotice(Map<String, dynamic> j)
    : title = j['title'] as String,
      body = j['body'] as String,
      image = j['image'] as String?,
      audience = (j['audience'] as Map?)?['kind'] as String? ?? '',
      devices = (j['devices'] as num?)?.toInt() ?? 0,
      sent = (j['sent'] as num?)?.toInt() ?? 0,
      failed = (j['failed'] as num?)?.toInt() ?? 0,
      at = DateTime.tryParse(j['at'] as String? ?? '');
  final String title;
  final String body;
  final String? image;
  final String audience;
  final int devices;
  final int sent;
  final int failed;
  final DateTime? at;
}

extension Notifications on AdminApi {
  /// Puts a picture on the server; its public URL comes back.
  Future<String> uploadImage(List<int> bytes, String mime) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    final res = await http
        .post(
          Uri.parse('$adminApiUrl/v1/admin/media'),
          headers: {'Authorization': 'Bearer $token', 'Content-Type': mime},
          body: bytes,
        )
        .timeout(const Duration(seconds: 60));
    final j = res.body.isEmpty ? const {} : jsonDecode(res.body) as Map;
    if (res.statusCode >= 400) {
      throw ApiError(res.statusCode, '${j['error'] ?? 'Upload failed'}');
    }
    return j['url'] as String;
  }

  /// Sends now. [audience]: `{kind: me|all}` or `{kind: emails, emails: [...]}`.
  Future<Map<String, dynamic>> notify({
    required String title,
    required String body,
    String? image,
    required Map<String, Object> audience,
  }) async =>
      (await callJson('POST', '/v1/admin/notifications', {
            'title': title,
            'body': body,
            'image': ?image,
            'audience': audience,
          }))
          as Map<String, dynamic>;

  Future<List<SentNotice>> sentNotices() async => [
    for (final n in (await callJson('GET', '/v1/admin/notifications')) as List)
      SentNotice(n as Map<String, dynamic>),
  ];
}

extension Phones on AdminApi {
  Future<List<Phone>> phones(String email) async => [
    for (final p
        in (await callJson(
              'GET',
              '/v1/admin/devices?email=${Uri.encodeQueryComponent(email)}',
            ))
            as List)
      Phone(p as Map<String, dynamic>),
  ];
}
