import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'application/config.dart';

/// Initializes Firebase. On the web it needs the injected config; on Android
/// and iOS it reads the app's `google-services.json` /
/// `GoogleService-Info.plist` (kept out of git). Safe to call unconditionally
/// from the host app's `main()` — when neither is present it does nothing, so
/// the app runs without any Firebase setup (offline/dev).
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await initStudioFirebase();
///   runApp(const ProviderScope(child: CockpitApp()));
/// }
/// ```
Future<void> initStudioFirebase() async {
  if (!StudioConfig.firebaseConfigured) {
    if (kIsWeb) return;
    try {
      await Firebase.initializeApp();
    } catch (error) {
      // No platform config bundled: stay in dev mode.
      debugPrint('Firebase not configured on this build: $error');
    }
    return;
  }
  final projectId = StudioConfig.firebaseProjectId;
  await Firebase.initializeApp(
    options: FirebaseOptions(
      apiKey: StudioConfig.firebaseApiKey,
      appId: StudioConfig.firebaseAppId,
      projectId: projectId,
      messagingSenderId: StudioConfig.firebaseMessagingSenderId,
      authDomain: StudioConfig.firebaseAuthDomain.isNotEmpty
          ? StudioConfig.firebaseAuthDomain
          : '$projectId.firebaseapp.com',
      storageBucket: StudioConfig.firebaseStorageBucket.isNotEmpty
          ? StudioConfig.firebaseStorageBucket
          : '$projectId.appspot.com',
    ),
  );

  if (!kIsWeb) return;

  // FlutterFire initializes Auth with IndexedDB-first. That search also
  // *migrates* a Next.js localStorage session into IndexedDB — so we must
  // wait for that restore, then put the session back in localStorage where
  // OctopilotWeb can still see it.
  final auth = FirebaseAuth.instance;
  await auth.authStateChanges().first;
  await auth.setPersistence(Persistence.LOCAL);
}

/// Whether Firebase is up, from the injected config or the platform files.
bool get studioFirebaseReady {
  if (StudioConfig.firebaseConfigured) return true;
  try {
    return Firebase.apps.isNotEmpty;
  } catch (_) {
    return false;
  }
}
