import 'dart:convert';

import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:octo_notes/src/application/account_providers.dart';
import 'package:octo_notes/src/data/account/account_repository.dart';
import 'package:octo_notes/src/data/api/notes_api_client.dart';
import 'package:octo_notes/src/domain/account.dart';
import 'package:octo_notes/src/presentation/home/header_glow.dart';
import 'package:octo_notes/src/presentation/home/octo_notes_home_page.dart';

const _meJson = {
  'uid': 'dev-user',
  'email': 'dev@octonotes.local',
  'registered': true,
  'userId': 'cd454c20-232b-4f86-9630-c503c91491eb',
  'name': 'Dev Student',
  'photoUrl': null,
  'plan': 'Pro Monthly',
  'octoCredits': 5000,
  'isAdmin': false,
};

void main() {
  group('NotesAccount', () {
    test('parses the /v1/me contract', () {
      final a = NotesAccount.fromJson(_meJson);
      expect(a.registered, isTrue);
      expect(a.octoCredits, 5000);
      expect(a.displayName, 'Dev Student');
      expect(a.initial, 'D');
    });

    test('unregistered account has no balance and falls back to the email', () {
      final a = NotesAccount.fromJson(const {
        'uid': 'x',
        'email': 'hein@example.com',
        'registered': false,
        'octoCredits': null,
      });
      expect(a.octoCredits, isNull);
      expect(a.displayName, 'hein');
    });
  });

  group('ApiAccountRepository', () {
    test('sends the bearer token and decodes the account', () async {
      late http.Request seen;
      final client = NotesApiClient(
        baseUrl: 'http://api.test/',
        tokenProvider: () async => 'tok123',
        httpClient: MockClient((req) async {
          seen = req;
          return http.Response(jsonEncode(_meJson), 200);
        }),
      );
      final me = await ApiAccountRepository(client).me();
      expect(seen.url.toString(), 'http://api.test/v1/me');
      expect(seen.headers['authorization'], 'Bearer tok123');
      expect(me.octoCredits, 5000);
    });

    test('omits the header when signed out and surfaces API errors', () async {
      late http.Request seen;
      final client = NotesApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () async => null,
        httpClient: MockClient((req) async {
          seen = req;
          return http.Response('{"error":"missing bearer token"}', 401);
        }),
      );
      await expectLater(
        ApiAccountRepository(client).me(),
        throwsA(isA<NotesApiException>()
            .having((e) => e.statusCode, 'status', 401)
            .having((e) => e.message, 'message', 'missing bearer token')),
      );
      expect(seen.headers.containsKey('authorization'), isFalse);
    });
  });

  testWidgets('Home header shows the OctoCredits balance', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        accountRepositoryProvider.overrideWithValue(
          InMemoryAccountRepository(NotesAccount.fromJson(_meJson)),
        ),
      ],
      child: const MaterialApp(home: OctoNotesHomePage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('5,000'), findsOneWidget);
    expect(find.text('D'), findsOneWidget);
  });

  testWidgets('Phone home: OctoCredits pill and the header glow, desktop without', (tester) async {
    Future<void> show(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(ProviderScope(
        key: ValueKey(size),
        overrides: [
          accountRepositoryProvider.overrideWithValue(
            InMemoryAccountRepository(NotesAccount.fromJson(_meJson)),
          ),
        ],
        child: const MaterialApp(home: OctoNotesHomePage()),
      ));
      // The glow never settles (it drifts), so pump past the count-up.
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
    }

    addTearDown(tester.view.reset);
    // The real face, so widths are what a phone draws (not the test font).
    await tester.runAsync(() async {
      final font = FontLoader('packages/cockpit_ui/PlusJakartaSans');
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        font.addFont(rootBundle.load('packages/cockpit_ui/assets/fonts/PlusJakartaSans-$w.ttf'));
      }
      await font.load();
    });
    await show(const Size(390, 844));
    expect(find.byType(OctoCreditsPill), findsOneWidget);
    expect(find.text('5,000'), findsOneWidget);
    expect(find.byType(HeaderGlow), findsOneWidget);
    // A finger on the header moves the glow without breaking anything.
    await tester.tapAt(const Offset(80, 60));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    await show(const Size(1440, 900));
    expect(find.byType(HeaderGlow), findsNothing);
    expect(find.byType(OctoCreditsPill), findsNothing);
  });
}
