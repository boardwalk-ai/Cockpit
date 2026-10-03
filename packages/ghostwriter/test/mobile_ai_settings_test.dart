import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_server.dart';
import 'support.dart';

/// The background never stops animating, so `pumpAndSettle` cannot be used.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

const catalog = {
  'pro': false,
  'models': [
    {
      'id': 'octo-v1',
      'name': 'Octo v1',
      'tagline': 'Everyday',
      'pro': false,
      'locked': false,
      'default': true,
    },
    {
      'id': 'octo-v2-pro',
      'name': 'Octo v2 Pro',
      'tagline': 'Our best writer',
      'pro': true,
      'locked': true,
      'default': false,
    },
  ],
  'personalities': [
    {'id': 'cool', 'name': 'Cool', 'description': 'Relaxed', 'default': true},
    {
      'id': 'professor',
      'name': 'Professor',
      'description': 'Precise',
      'default': false,
    },
  ],
};

Map<String, dynamic> prefs({
  Map<String, dynamic>? global,
  Map<String, dynamic>? ghostwriter,
}) => {
  'scopes': {
    'global': global,
    'ghostwriter': ghostwriter,
    'study_studio': null,
  },
  'effective': {
    'ghostwriter': {
      'model': ghostwriter?['model'] ?? global?['model'] ?? 'octo-v1',
      'personality':
          ghostwriter?['personality'] ?? global?['personality'] ?? 'cool',
    },
  },
};

void main() {
  Future<FakeServer> open(
    WidgetTester tester, {
    Map<String, Object?> responses = const {},
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final server = FakeServer(
      responses: {
        'GET /v1/ai/catalog': catalog,
        'GET /v1/ai/preferences': prefs(),
        ...responses,
      },
    );
    await tester.pumpWidget(GhostWriterApp(session: server.session()));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byTooltip('Essays'));
    await settle(tester);
    await tester.tap(find.byTooltip('AI settings'));
    await settle(tester);
    return server;
  }

  /// The tick on [name]'s card.
  Finder selected(String name) => find.descendant(
    of: find.ancestor(
      of: find.text(name),
      matching: find.byType(AnimatedContainer),
    ),
    matching: find.byIcon(Icons.check_circle_rounded),
  );

  testWidgets('shows the models and voices, and what is in use', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('AI settings'), findsOneWidget);
    expect(find.text('Octo v1'), findsOneWidget);
    expect(find.text('Octo v2 Pro'), findsOneWidget);
    expect(find.text('PRO'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(selected('Octo v1'), findsOneWidget);
    expect(find.text('Professor'), findsOneWidget);
    expect(
      find.textContaining('Your essay always stays academic'),
      findsOneWidget,
    );
  });

  testWidgets('a choice is saved for every app', (tester) async {
    final server = await open(
      tester,
      responses: {
        'PUT /v1/ai/preferences/global': (Object? body) =>
            prefs(global: {'model': null, 'personality': 'professor'}),
      },
    );

    await tester.tap(find.text('Professor'));
    await settle(tester);
    expect(server.calls, contains('PUT /v1/ai/preferences/global'));
    expect(server.bodies.last, {'personality': 'professor'});
  });

  testWidgets('a Pro model is locked off Pro, and the server agrees', (
    tester,
  ) async {
    final server = await open(
      tester,
      responses: {
        'PUT /v1/ai/preferences/global': const FakeReply(403, {
          'error': 'this model needs a Pro plan',
          'code': 'pro_required',
        }),
      },
    );

    await tester.tap(find.text('Octo v2 Pro'));
    await settle(tester);
    expect(find.text('That model needs a Pro plan.'), findsOneWidget);
    expect(server.calls, isNot(contains('PUT /v1/ai/preferences/global')));
  });

  testWidgets('GhostWriter can have its own choice, and give it back', (
    tester,
  ) async {
    final server = await open(
      tester,
      responses: {
        'PUT /v1/ai/preferences/ghostwriter': (Object? body) {
          final change = body as Map<String, dynamic>;
          return prefs(
            ghostwriter: change['model'] == null
                ? null
                : {'model': change['model'], 'personality': null},
          );
        },
      },
    );

    await tester.tap(find.text('GhostWriter only'));
    await settle(tester);
    expect(find.text('Same as all apps'), findsNWidgets(2));

    await tester.tap(find.text('Octo v1'));
    await settle(tester);
    expect(server.calls.last, 'PUT /v1/ai/preferences/ghostwriter');
    expect(server.bodies.last, {'model': 'octo-v1'});
    expect(find.text('Use all-apps setting'), findsOneWidget);

    await tester.tap(find.text('Use all-apps setting'));
    await settle(tester);
    expect(server.bodies.last, {'model': null});
    expect(find.text('Same as all apps'), findsNWidgets(2));
  });
}
