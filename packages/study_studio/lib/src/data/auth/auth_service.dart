/// Auth boundary for the app.
///
/// The backend accepts a Firebase ID token as `Authorization: Bearer …` and
/// verifies it against Octopilot's Firebase project. This interface provides
/// that token to the API client.
///
/// Today it's [StubAuthService] (no token → the backend uses the dev X-User-Id
/// header). To turn on real auth, add `firebase_core` + `firebase_auth`, drop in
/// a `FirebaseAuthService implements AuthService` that returns
/// `FirebaseAuth.instance.currentUser?.getIdToken()`, and point
/// `authServiceProvider` at it. No API-client or page changes needed — the
/// SseClient already sends the token when this returns non-null.
/// Who's signed in, as the sign-in itself knows it (Google): shown straight
/// away, before any server answers, and the same in every module.
class AuthProfile {
  const AuthProfile({this.name, this.email, this.photoUrl});
  final String? name;
  final String? email;
  final String? photoUrl;

  /// One or two letters for an avatar without a photo.
  String get initials {
    final words = (name?.trim().isNotEmpty == true ? name! : (email ?? '').split('@').first).trim().split(RegExp(r'[\s@._-]+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    return (words.length == 1 ? words.first[0] : '${words.first[0]}${words.last[0]}').toUpperCase();
  }
}

abstract interface class AuthService {
  /// Current Firebase ID token, or null when signed out / in dev mode.
  Future<String?> idToken();

  /// Whether a user is currently signed in.
  bool get isSignedIn;

  /// The signed-in person (name, email, photo), or null when signed out.
  AuthProfile? get profile;

  /// Emits whenever the auth state changes (sign in / out / token refresh).
  /// `true` when signed in. Data providers watch this to refetch user-scoped
  /// data with the new token — otherwise a fetch made while signed out (e.g. the
  /// studio list on first load) stays stale after sign-in.
  Stream<bool> authStateChanges();

  Future<void> signIn();

  Future<void> signOut();
}

/// Offline default: no token, no session. The backend falls back to X-User-Id.
class StubAuthService implements AuthService {
  const StubAuthService();

  @override
  Future<String?> idToken() async => null;

  @override
  bool get isSignedIn => false;

  @override
  AuthProfile? get profile => null;

  @override
  Stream<bool> authStateChanges() => Stream.value(false);

  @override
  Future<void> signIn() async {}

  @override
  Future<void> signOut() async {}
}
