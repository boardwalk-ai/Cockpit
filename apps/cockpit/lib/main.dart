import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:study_studio/study_studio.dart';

import 'app.dart';
import 'modules/module_auth.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // No-op unless the Firebase config is injected via --dart-define; then the app
  // signs in against Octopilot's Firebase project.
  await initStudioFirebase();
  runApp(ProviderScope(overrides: moduleAuthOverrides, child: const CockpitApp()));
}
