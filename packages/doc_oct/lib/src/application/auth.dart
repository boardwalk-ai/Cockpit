import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

/// Firebase web config, injected at build time (same Octopilot project the
/// FastAPI verifies against). When absent, the app runs signed-out (Stub).
class DocFirebaseConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  static bool get configured =>
      apiKey.isNotEmpty && appId.isNotEmpty && projectId.isNotEmpty;
}

/// The signed-in account (a thin view over the Firebase user).
class DocUser {
  const DocUser({required this.uid, this.email, this.name, this.photoUrl});
  final String uid;
  final String? email;
  final String? name;
  final String? photoUrl;
}

/// Auth boundary: the ID token (sent as `Authorization: Bearer …`), the current
/// user, a change stream, and Google sign-in/out.
abstract interface class DocAuth {
  Future<String?> idToken();
  DocUser? get currentUser;
  Stream<DocUser?> userChanges();
  Future<void> signIn();
  Future<void> signOut();
}

/// Real auth over Firebase (Google popup on web). Firebase must already be
/// initialized (main calls `initStudioFirebase`).
class FirebaseDocAuth implements DocAuth {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  DocUser? _map(User? u) => u == null
      ? null
      : DocUser(
          uid: u.uid, email: u.email, name: u.displayName, photoUrl: u.photoURL);

  @override
  Future<String?> idToken() async => _auth.currentUser?.getIdToken();

  @override
  DocUser? get currentUser => _map(_auth.currentUser);

  @override
  Stream<DocUser?> userChanges() => _auth.userChanges().map(_map);

  @override
  Future<void> signIn() async {
    final provider = GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'select_account'});
    await _auth.signInWithPopup(provider);
  }

  @override
  Future<void> signOut() => _auth.signOut();
}

/// Signed-out default (Firebase not configured).
class StubDocAuth implements DocAuth {
  const StubDocAuth();
  @override
  Future<String?> idToken() async => null;
  @override
  DocUser? get currentUser => null;
  @override
  Stream<DocUser?> userChanges() => Stream.value(null);
  @override
  Future<void> signIn() async {}
  @override
  Future<void> signOut() async {}
}

DocAuth createDocAuth() =>
    DocFirebaseConfig.configured ? FirebaseDocAuth() : const StubDocAuth();
