import 'assist_service.dart';
import 'essays_service.dart';
import 'http_tools_service.dart';
import 'tools_service.dart';

/// The backend base URL, injected at build time:
///
///   flutter run --dart-define=DOC_OCT_API=http://localhost:8787
///
/// When empty (the default), the app uses [MockToolsService] so it still runs
/// fully offline with clearly-marked sample data.
const String kDocOctApiBase =
    String.fromEnvironment('DOC_OCT_API', defaultValue: '');

/// Whether a real backend is configured.
bool get hasBackend => kDocOctApiBase.isNotEmpty;

/// Supplies the Firebase ID token for authed requests (set by the auth layer).
/// Null while signed out or in offline mode.
Future<String?> Function()? _authTokenSource;
void setAuthTokenSource(Future<String?> Function()? f) => _authTokenSource = f;
Future<String?> Function()? get authTokenSource => _authTokenSource;

/// The active Tools data source — real HTTP backend when configured, else mock.
ToolsService createToolsService() => hasBackend
    ? HttpToolsService(kDocOctApiBase, token: authTokenSource)
    : const MockToolsService();

/// The active assistant (OctoBot chat + outline) — backend when configured.
AssistService createAssistService() => hasBackend
    ? HttpAssistService(kDocOctApiBase, token: authTokenSource)
    : const MockAssistService();

/// Saved-document service (essays). Requires a backend + sign-in; null offline.
EssaysService? createEssaysService() =>
    hasBackend ? EssaysService(kDocOctApiBase, token: authTokenSource) : null;
