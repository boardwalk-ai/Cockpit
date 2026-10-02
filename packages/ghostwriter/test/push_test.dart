import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwriter/ghostwriter.dart';
import 'package:ghostwriter/src/session/gw_session.dart';

import 'fake_server.dart';
import 'sign_in_test.dart' show FakeAuth;

class FakePush implements GwPush {
  FakePush({this.allowed = false});

  /// Whether the user has allowed notifications.
  bool allowed;
  int asks = 0;
  final refreshes = StreamController<String>.broadcast();
  final taps = StreamController<Map<String, String>>.broadcast();

  @override
  String get platform => 'android';

  @override
  Future<String> deviceId() async => 'device-1';

  @override
  Future<String?> token({required bool ask}) async {
    if (ask && !allowed) {
      asks++;
      allowed = true; // the user says yes
    }
    return allowed ? 'token-1' : null;
  }

  @override
  Stream<String> get tokenRefreshes => refreshes.stream;

  @override
  Stream<Map<String, String>> get opened => taps.stream;
}

const _away = [
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
];

/// The app goes to the background, through every state on the way.
void toBackground(WidgetTester tester) =>
    _away.forEach(tester.binding.handleAppLifecycleStateChanged);

void toForeground(WidgetTester tester) => [
  AppLifecycleState.hidden,
  AppLifecycleState.inactive,
  AppLifecycleState.resumed,
].forEach(tester.binding.handleAppLifecycleStateChanged);

void main() {
  late FakeServer server;
  late GwSession session;

  setUp(() {
    server = FakeServer();
    session = server.session();
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
  }

  Future<void> show(WidgetTester tester, GwPush push, {GwAuth? auth}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GhostWriterRoot(auth: auth, push: push, session: session),
      ),
    );
    await settle(tester);
  }

  Iterable<String> deviceCalls() =>
      server.calls.where((call) => call.contains('/v1/devices/'));

  testWidgets('a phone that already allows notifications registers at once', (
    tester,
  ) async {
    final push = FakePush(allowed: true);
    await show(tester, push);

    expect(deviceCalls(), ['PUT /v1/devices/device-1']);
    expect(server.bodies.last, {'token': 'token-1', 'platform': 'android'});
    expect(push.asks, 0);

    // A new token replaces the old one; the same one is not sent twice.
    push.refreshes.add('token-1');
    push.refreshes.add('token-2');
    await settle(tester);
    expect(deviceCalls(), hasLength(2));
    expect(server.bodies.last, {'token': 'token-2', 'platform': 'android'});
  });

  testWidgets('permission is asked when the first run starts, not before', (
    tester,
  ) async {
    final push = FakePush();
    await show(tester, push);
    expect(push.asks, 0);
    expect(deviceCalls(), isEmpty);

    final started = session.start('An essay on tides');
    await tester.pump();
    await started;
    await settle(tester);

    expect(push.asks, 1);
    expect(deviceCalls(), ['PUT /v1/devices/device-1']);
  });

  testWidgets('tapping a notification opens its essay', (tester) async {
    final push = FakePush(allowed: true);
    await show(tester, push);

    push.taps.add({'type': 'question', 'projectId': 'p9', 'runId': 'r9'});
    await settle(tester);

    expect(server.calls, contains('GET /v1/projects/p9'));
    expect(session.projectId, 'p9');
  });

  testWidgets(
    'in the background the run is not followed; back, it catches up',
    (tester) async {
      await show(tester, FakePush(allowed: true));
      final started = session.start('An essay on tides');
      await tester.pump();
      await started;
      await tester.pump();
      await settle(tester);
      server.send(ev(1, 'user_message', {'text': 'An essay on tides'}));
      await settle(tester);
      expect(server.listening, isTrue);

      toBackground(tester);
      await settle(tester);
      expect(server.cancelled, 1);
      expect(session.reconnecting, isFalse);
      // It stays away: no retry while in the background.
      await tester.pump(const Duration(seconds: 10));
      expect(server.connections, 1);

      toForeground(tester);
      await settle(tester);
      expect(server.connections, 2);
      expect(server.lastSince, 1);
    },
  );

  testWidgets('signing out stops notifications to this phone first', (
    tester,
  ) async {
    final auth = FakeAuth(isSignedIn: true);
    await show(tester, FakePush(allowed: true), auth: auth);

    await tester.tap(find.byTooltip('Essays'));
    await settle(tester);
    await tester.tap(find.byTooltip('Sign out'));
    await settle(tester);

    expect(deviceCalls().last, 'DELETE /v1/devices/device-1');
    expect(auth.signOuts, 1);
  });

  testWidgets('without push nothing is registered and the run stays followed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: GhostWriterRoot(session: session)),
    );
    await settle(tester);
    final started = session.start('An essay on tides');
    await tester.pump();
    await started;
    await tester.pump();
    await settle(tester);

    toBackground(tester);
    await settle(tester);

    expect(deviceCalls(), isEmpty);
    expect(server.cancelled, 0);
    toForeground(tester);
  });
}
