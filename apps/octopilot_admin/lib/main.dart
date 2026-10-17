import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'api.dart';
import 'screens.dart';
import 'theme.dart';

/// Octopilot Admin: the test environment's list of testers, their
/// OctoCredits, the feature flags and the prices. Only the admin emails set
/// on the server (ADMIN_EMAILS) get past sign-in.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Octopilot Admin',
    debugShowCheckedModeBanner: false,
    theme: adminTheme(),
    home: const _Gate(),
  );
}

Future<void>? _googleReady;

Future<void> signIn() async {
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
  if (idToken == null) throw StateError('Google returned no ID token');
  await FirebaseAuth.instance.signInWithCredential(
    GoogleAuthProvider.credential(idToken: idToken),
  );
}

Future<void> signOut() async {
  await (_googleReady ??= GoogleSignIn.instance.initialize());
  await GoogleSignIn.instance.signOut();
  await FirebaseAuth.instance.signOut();
}

/// Signed out → sign in; signed in but not an admin → sign out; else the app.
class _Gate extends StatefulWidget {
  const _Gate();

  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  final _api = AdminApi();
  Future<String>? _me;
  User? _user;

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.authStateChanges().listen((u) {
      setState(() {
        _user = u;
        _me = u == null ? null : _api.me();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) return const _SignInPage();
    return FutureBuilder(
      future: _me,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          final e = snap.error;
          return _Message(
            title: e is ApiError && e.code == 'not_admin'
                ? 'Admins only'
                : 'Can\'t reach the server',
            body: e is ApiError && e.code == 'not_admin'
                ? '${_user!.email} isn\'t an admin of the test environment.'
                : '$e',
            action: e is ApiError && e.code == 'not_admin'
                ? ('Use another account', signOut)
                : ('Try again', () async => setState(() => _me = _api.me())),
          );
        }
        return HomePage(api: _api, email: snap.data!);
      },
    );
  }
}

class _SignInPage extends StatefulWidget {
  const _SignInPage();

  @override
  State<_SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<_SignInPage> {
  bool _busy = false;
  String? _error;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await signIn();
    } on Object catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          children: [
            const Spacer(flex: 3),
            const OctoMark(size: 76),
            const SizedBox(height: 28),
            Text(
              'Octopilot Admin',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              'Testers, credits and switches for the test app.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AdminColors.muted, height: 1.4),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AdminColors.accent),
              ),
            ],
            const Spacer(flex: 4),
            SizedBox(
              width: double.infinity,
              child: GradientButton(
                label: _busy ? 'Signing in…' : 'Sign in with Google',
                icon: Icons.login_rounded,
                onPressed: _busy ? null : _go,
              ),
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.title,
    required this.body,
    required this.action,
  });
  final String title;
  final String body;
  final (String, Future<void> Function()) action;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const OctoMark(size: 60),
            const SizedBox(height: 24),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: AdminColors.muted),
            ),
            const SizedBox(height: 24),
            OutlinedButton(onPressed: action.$2, child: Text(action.$1)),
          ],
        ),
      ),
    ),
  );
}
