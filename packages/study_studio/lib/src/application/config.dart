/// Runtime configuration for the Study Studio module.
///
/// The backend base URL is injected at build/run time:
///
/// ```bash
/// flutter run -d chrome --dart-define=STUDY_API_BASE_URL=http://localhost:8100
/// # production:      --dart-define=STUDY_API_BASE_URL=https://api.octopilot.ai
/// ```
///
/// When it is empty (the default), the app runs fully offline against the
/// in-memory mock repository — so tests and design work need no server. When it
/// is set, the app pulls everything from the server backend over SSE.
class StudioConfig {
  const StudioConfig._();

  static const String apiBaseUrl =
      String.fromEnvironment('STUDY_API_BASE_URL', defaultValue: '');

  /// Dev/user identity header until real auth (octopilot session/JWT) lands.
  static const String devUserId = String.fromEnvironment(
    'STUDY_USER_ID',
    defaultValue: '11111111-1111-1111-1111-111111111111',
  );

  static bool get hasApiBackend => apiBaseUrl.isNotEmpty;

  /// Octopilot's API, which sells OctoCredits (Stripe Checkout).
  static const String billingBaseUrl = String.fromEnvironment(
    'BILLING_API_BASE_URL',
    defaultValue: 'https://octopilotai.app/backend/api/v1',
  );

  // --- Firebase (reuse Octopilot's Firebase project) -----------------------
  // Copy these from Octopilot's Firebase Web app config and pass as
  // --dart-define=FIREBASE_API_KEY=… etc. When unset, the app stays in the
  // offline/dev auth mode (StubAuthService).
  static const String firebaseApiKey =
      String.fromEnvironment('FIREBASE_API_KEY', defaultValue: '');
  static const String firebaseAppId =
      String.fromEnvironment('FIREBASE_APP_ID', defaultValue: '');
  static const String firebaseProjectId =
      String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: '');
  static const String firebaseMessagingSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID', defaultValue: '');
  static const String firebaseAuthDomain =
      String.fromEnvironment('FIREBASE_AUTH_DOMAIN', defaultValue: '');
  static const String firebaseStorageBucket =
      String.fromEnvironment('FIREBASE_STORAGE_BUCKET', defaultValue: '');

  static bool get firebaseConfigured =>
      firebaseApiKey.isNotEmpty &&
      firebaseAppId.isNotEmpty &&
      firebaseProjectId.isNotEmpty;
}
