/// The auth OctoNotes needs from the host app: an ID token for API calls and
/// a signal when the signed-in user changes.
///
/// OctoNotes never talks to Firebase itself. The Cockpit shell overrides
/// `notesAuthProvider` with an adapter over the app's shared sign-in, so every
/// module uses the same Firebase session.
abstract interface class NotesAuth {
  /// Current Firebase ID token, or null when signed out.
  Future<String?> idToken();

  bool get isSignedIn;

  /// Emits whenever sign-in state changes (sign in, sign out, token restored).
  Stream<bool> authStateChanges();
}

/// Default when the host provides no auth: always signed out. Against a dev
/// backend with auth disabled, requests still work (it trusts `X-User-Id`).
class SignedOutNotesAuth implements NotesAuth {
  const SignedOutNotesAuth();

  @override
  Future<String?> idToken() async => null;

  @override
  bool get isSignedIn => false;

  @override
  Stream<bool> authStateChanges() => Stream<bool>.value(false);
}
