import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ghostwriter/ghostwriter.dart';
import 'package:octo_notes/octo_notes.dart';
import 'package:study_studio/study_studio.dart';

/// Hands every module the app's single Firebase sign-in (owned by Study
/// Studio's [AuthService]), so every module shares one session and one
/// OctoCredits identity.
final moduleAuthOverrides = <Override>[
  notesAuthProvider.overrideWith((ref) => _SharedNotesAuth(ref.watch(authServiceProvider))),
];

class _SharedNotesAuth implements NotesAuth {
  const _SharedNotesAuth(this._auth);

  final AuthService _auth;

  @override
  Future<String?> idToken() => _auth.idToken();

  @override
  bool get isSignedIn => _auth.isSignedIn;

  @override
  Stream<bool> authStateChanges() => _auth.authStateChanges();

  @override
  Future<void> signIn() => _auth.signIn();

  @override
  Future<void> signOut() => _auth.signOut();
}

/// GhostWriter's view of the app's sign-in.
final ghostWriterAuthProvider = Provider<GwAuth>(
  (ref) => _SharedGhostWriterAuth(ref.watch(authServiceProvider)),
);

class _SharedGhostWriterAuth implements GwAuth {
  const _SharedGhostWriterAuth(this._auth);

  final AuthService _auth;

  /// Only a real Firebase sign-in needs the sign-in screen; the stub (no
  /// Firebase config on this build) runs as the dev user.
  @override
  bool get enabled => _auth is FirebaseAuthService;

  @override
  Future<String?> idToken() => _auth.idToken();

  @override
  bool get isSignedIn => _auth.isSignedIn;

  @override
  Stream<bool> authStateChanges() => _auth.authStateChanges();

  @override
  Future<void> signIn() => _auth.signIn();

  @override
  Future<void> signOut() => _auth.signOut();
}
