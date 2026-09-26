import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:octo_notes/octo_notes.dart';
import 'package:study_studio/study_studio.dart';

/// Hands every module the app's single Firebase sign-in (owned by Study
/// Studio's [AuthService]), so OctoNotes and Study Studio share one session and
/// one OctoCredits identity.
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
}
