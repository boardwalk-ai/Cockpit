import 'package:doc_oct/doc_oct.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:study_studio/study_studio.dart';

/// Standalone Doc Oct web entrypoint (octopilotai.app). Runs the Doc Oct app on
/// its own, wired to the Rust backend via --dart-define=DOC_OCT_API=… and, when
/// the Firebase config is injected, the shared Octopilot auth.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initStudioFirebase(); // no-op unless FIREBASE_* defines are provided
  await WizardSession.init();
  // Wire the Firebase ID token into Doc Oct's API client so authed calls
  // (credits, saving) carry it.
  setAuthTokenSource(createDocAuth().idToken);
  runApp(const ProviderScope(child: DocOctApp()));
}
