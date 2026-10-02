import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'auth_service.dart';

/// Real [AuthService] backed by Firebase Auth (Octopilot's Firebase project).
///
/// Enabled when Firebase is up (see [initStudioFirebase]); otherwise the app
/// uses [StubAuthService]. The ID token it returns is sent to the backends as
/// `Authorization: Bearer …` and verified there.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService([FirebaseAuth? auth])
      : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  /// `GoogleSignIn.initialize` may run only once per app.
  static Future<void>? _googleReady;

  @override
  Future<String?> idToken() async => _auth.currentUser?.getIdToken();

  @override
  bool get isSignedIn => _auth.currentUser != null;

  @override
  Stream<bool> authStateChanges() =>
      _auth.authStateChanges().map((user) => user != null);

  /// Google is Octopilot's primary provider. The web uses Firebase's popup;
  /// Android and iOS use the native account picker, whose client IDs come
  /// from the bundled `google-services.json` / `GoogleService-Info.plist`.
  ///
  /// Returns normally if the user backs out of the picker.
  @override
  Future<void> signIn() async {
    if (kIsWeb) {
      await _auth.signInWithPopup(GoogleAuthProvider());
      return;
    }

    final google = GoogleSignIn.instance;
    await (_googleReady ??= google.initialize());
    final GoogleSignInAccount account;
    try {
      account = await google.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return;
      rethrow;
    }
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw StateError('Google returned no ID token');
    }
    await _auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: idToken),
    );
  }

  @override
  Future<void> signOut() async {
    if (!kIsWeb) {
      // So the next sign-in asks which account again.
      await (_googleReady ??= GoogleSignIn.instance.initialize());
      await GoogleSignIn.instance.signOut();
    }
    await _auth.signOut();
  }
}
