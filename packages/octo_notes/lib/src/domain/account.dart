import 'package:flutter/widgets.dart';

/// The signed-in account and its central OctoCredits balance (`GET /v1/me`).
///
/// OctoCredits is one balance shared by OctoNotes, Study Studio and
/// OctopilotWeb. [registered] is false when the Firebase account has no
/// Octopilot account yet; then [octoCredits] is null.
@immutable
class NotesAccount {
  const NotesAccount({
    required this.uid,
    required this.registered,
    this.email,
    this.userId,
    this.name,
    this.photoUrl,
    this.plan,
    this.octoCredits,
  });

  factory NotesAccount.fromJson(Map<String, dynamic> json) => NotesAccount(
        uid: json['uid'] as String,
        registered: json['registered'] as bool? ?? false,
        email: json['email'] as String?,
        userId: json['userId'] as String?,
        name: json['name'] as String?,
        photoUrl: json['photoUrl'] as String?,
        plan: json['plan'] as String?,
        octoCredits: (json['octoCredits'] as num?)?.toInt(),
      );

  /// Shown when OctoNotes runs without a backend.
  static const guest = NotesAccount(uid: 'guest', registered: false, name: 'Guest');

  final String uid;
  final bool registered;
  final String? email;
  final String? userId;
  final String? name;
  final String? photoUrl;
  final String? plan;
  final int? octoCredits;

  /// Name, else the part of the email before `@`, else "Guest".
  String get displayName {
    if (name != null && name!.trim().isNotEmpty) return name!.trim();
    if (email != null && email!.contains('@')) return email!.split('@').first;
    return 'Guest';
  }

  String get initial => displayName.characters.first.toUpperCase();
}
