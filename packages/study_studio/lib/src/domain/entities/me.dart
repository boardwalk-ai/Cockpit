/// The signed-in user, as surfaced in the app chrome (profile + Octocredits).
///
/// Identity + credits are owned by Octopilot (shared backend); the app reads
/// them via `GET /me`. This is the start of auth — the header reflects who is
/// signed in and their credit balance.
class Me {
  const Me({
    required this.id,
    this.email,
    this.displayName,
    this.credits,
    this.photoUrl,
  });

  final String id;
  final String? email;
  final String? displayName;
  final int? credits;

  /// The account photo (Google sign-in), for the header's profile button.
  final String? photoUrl;

  /// Initials for the avatar fallback (e.g. "DT" from a name/email).
  String get initials {
    final source = (displayName?.trim().isNotEmpty ?? false)
        ? displayName!.trim()
        : (email ?? '').trim();
    if (source.isEmpty) return '?';
    final parts = source.split(RegExp(r'[\s@._-]+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.elementAt(1)[0]).toUpperCase();
  }
}
