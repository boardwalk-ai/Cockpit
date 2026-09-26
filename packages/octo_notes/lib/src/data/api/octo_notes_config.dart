/// Build-time switch between the real OctoNotes API and the in-memory data.
///
/// `flutter run --dart-define=OCTONOTES_API_BASE_URL=http://127.0.0.1:8790`
/// points OctoNotes at `octonotes-api`; without it every repository uses its
/// in-memory implementation (offline default, and what tests use).
abstract final class OctoNotesConfig {
  static const String apiBaseUrl = String.fromEnvironment('OCTONOTES_API_BASE_URL');

  static bool get hasApiBackend => apiBaseUrl.isNotEmpty;
}
