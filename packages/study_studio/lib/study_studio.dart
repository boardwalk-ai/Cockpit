/// Study Studio — the detachable AI study-environment module for Cockpit.
///
/// The shell needs [StudyStudioModule]; [authServiceProvider] / [AuthService]
/// are exported so other modules (OctoNotes) reuse the app's one sign-in.
library;

export 'src/application/providers.dart' show authServiceProvider;
export 'src/data/auth/auth_service.dart' show AuthService;
export 'src/firebase_bootstrap.dart' show initStudioFirebase;
export 'src/study_studio_module.dart';
