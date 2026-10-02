/// The sign-in GhostWriter needs from its host app. The app owns the one
/// Firebase session and hands GhostWriter this view of it, so every module
/// shares the same account and OctoCredits.
abstract interface class GwAuth {
  /// False when the host has no real sign-in (local dev): GhostWriter then
  /// skips its sign-in screen and calls the API as the dev user.
  bool get enabled;

  bool get isSignedIn;

  /// `true` when signed in; emits on every sign-in and sign-out.
  Stream<bool> authStateChanges();

  /// The Firebase ID token sent to the API, or null when signed out.
  Future<String?> idToken();

  /// Shows the platform's Google sign-in. Returns normally if the user backs
  /// out.
  Future<void> signIn();

  Future<void> signOut();
}
