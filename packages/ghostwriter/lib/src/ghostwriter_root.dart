import 'dart:async';

import 'package:flutter/material.dart';

import 'data/gw_api.dart';
import 'ghostwriter_page.dart';
import 'gw_auth.dart';
import 'gw_push.dart';
import 'mobile/mobile_app.dart';
import 'mobile/mobile_sign_in.dart';
import 'mobile/mobile_theme.dart';
import 'platform.dart';
import 'session/gw_push_link.dart';
import 'session/gw_session.dart';

/// GhostWriter with its own look, whatever theme the host app uses: the
/// phone UI on Android and iOS, the desktop UI elsewhere. With a real
/// [auth] the phone UI asks the user to sign in first.
class GhostWriterRoot extends StatefulWidget {
  const GhostWriterRoot({super.key, this.auth, this.push, this.session});

  /// The host app's sign-in. Null (or not [GwAuth.enabled]) means local dev:
  /// no sign-in screen, and the API is called as the dev user.
  final GwAuth? auth;

  /// The host app's push notifications. Null means none: nothing is asked
  /// of the user and runs are followed even in the background.
  final GwPush? push;

  /// A ready-made session, for tests.
  final GwSession? session;

  @override
  State<GhostWriterRoot> createState() => _GhostWriterRootState();
}

class _GhostWriterRootState extends State<GhostWriterRoot>
    with WidgetsBindingObserver {
  late final GwSession _session =
      widget.session ?? GwSession(GwApi(idToken: widget.auth?.idToken));
  StreamSubscription<bool>? _authChanges;
  late bool _signedIn;
  GwPushLink? _pushLink;

  GwAuth? get _auth {
    final auth = widget.auth;
    return auth != null && auth.enabled ? auth : null;
  }

  @override
  void initState() {
    super.initState();
    final auth = _auth;
    _signedIn = auth == null || auth.isSignedIn;
    _authChanges = auth?.authStateChanges().listen((signedIn) {
      if (signedIn == _signedIn || !mounted) return;
      if (!signedIn) _session.signedOut();
      setState(() => _signedIn = signedIn);
      if (signedIn) _pushLink?.start();
    });

    final push = widget.push;
    if (push != null && isMobilePlatform) {
      final link = _pushLink = GwPushLink(push, _session);
      // Ask to notify when there is something to be notified about.
      _session.onRunStarted = () => unawaited(link.sync(ask: true));
      WidgetsBinding.instance.addObserver(this);
      if (_signedIn) link.start();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // In the background the run is not followed, so the server notifies
    // instead. Coming back, the app reconnects and catches up.
    if (state == AppLifecycleState.paused) _session.suspend();
  }

  /// Signs out, first telling the server to stop notifying this phone.
  Future<void> _signOut() async {
    await _pushLink?.unregister();
    await _auth?.signOut();
  }

  @override
  void dispose() {
    _authChanges?.cancel();
    if (_pushLink != null) {
      WidgetsBinding.instance.removeObserver(this);
      _pushLink!.dispose();
      _session.onRunStarted = null;
    }
    if (widget.session == null) _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = _auth;
    final Widget child;
    if (!isMobilePlatform) {
      child = const GhostWriterPage();
    } else if (!_signedIn && auth != null) {
      child = GhostWriterSignIn(
        key: const ValueKey('sign-in'),
        onSignIn: auth.signIn,
      );
    } else {
      child = GhostWriterMobileApp(
        key: const ValueKey('app'),
        session: _session,
        onSignOut: auth == null ? null : _signOut,
      );
    }

    return Theme(
      data: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: GwFonts.primary,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 420),
        child: child,
      ),
    );
  }
}
