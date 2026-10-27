import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwriter/ghostwriter.dart';
import 'package:ghostwriter/src/mobile/mobile_app.dart';
import 'package:ghostwriter/src/mobile/mobile_sign_in.dart';

import 'fake_server.dart';

class FakeAuth implements GwAuth {
  @override
  String? get photoUrl => null;

  FakeAuth({this.enabled = true, this.isSignedIn = false});

  @override
  final bool enabled;

  @override
  bool isSignedIn;

  final _changes = StreamController<bool>.broadcast();
  int signIns = 0;
  int signOuts = 0;

  @override
  Stream<bool> authStateChanges() => _changes.stream;

  @override
  Future<String?> idToken() async => isSignedIn ? 'token' : null;

  @override
  Future<void> signIn() async {
    signIns++;
    isSignedIn = true;
    _changes.add(true);
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    isSignedIn = false;
    _changes.add(false);
  }
}

void main() {
  Future<void> show(WidgetTester tester, GwAuth auth) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GhostWriterRoot(auth: auth, session: FakeServer().session()),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('signed out, the phone UI asks to sign in first', (tester) async {
    final auth = FakeAuth();
    await show(tester, auth);

    expect(find.byType(GhostWriterSignIn), findsOneWidget);
    expect(find.byType(GhostWriterMobileApp), findsNothing);

    await tester.tap(find.text('Continue with Google'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(auth.signIns, 1);
    expect(find.byType(GhostWriterMobileApp), findsOneWidget);
    expect(find.byType(GhostWriterSignIn), findsNothing);
  });

  testWidgets('sign-out from the drawer returns to the sign-in screen', (
    tester,
  ) async {
    final auth = FakeAuth(isSignedIn: true);
    await show(tester, auth);
    expect(find.byType(GhostWriterMobileApp), findsOneWidget);

    await tester.tap(find.byTooltip('Essays'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byTooltip('Sign out'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(auth.signOuts, 1);
    expect(find.byType(GhostWriterSignIn), findsOneWidget);
  });

  testWidgets('without a real sign-in (dev) there is no sign-in screen', (
    tester,
  ) async {
    await show(tester, FakeAuth(enabled: false));

    expect(find.byType(GhostWriterSignIn), findsNothing);
    expect(find.byType(GhostWriterMobileApp), findsOneWidget);
    // Nor a sign-out button.
    await tester.tap(find.byTooltip('Essays'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byTooltip('Sign out'), findsNothing);
  });
}
