import 'dart:convert';

import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:doc_oct/doc_oct.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The editor is one session: every 10 s changes are written to the user's
/// document (title = essay title, else "Untitled document").
void main() {
  late List<Map<String, dynamic>> posts;
  late List<String?> keys; // Idempotency-Key per request
  late EssaysService essays;
  String? token;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await WizardSession.init();
    posts = [];
    keys = [];
    token = 'firebase-id-token';
    essays = EssaysService(
      'https://api.test',
      token: () async => token,
      client: MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        posts.add(body);
        keys.add(req.headers['Idempotency-Key']);
        return http.Response(
          jsonEncode({
            'id': body['id'] ?? 'doc-1',
            'title': body['title'],
            'content': body['content'],
          }),
          200,
        );
      }),
    );
  });

  Future<void> pumpEditor(WidgetTester t, {String? id, String? json}) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1280, 720);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: BorderlessTheme.build(Brightness.dark),
          home: EditorPage(
            essays: essays,
            initialDocId: id,
            initialDocJson: json,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  final studentName = find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == 'Student Name',
  );

  Future<void> tick(WidgetTester t) async {
    await t.pump(const Duration(seconds: 10));
    await t.pump();
  }

  testWidgets('blank editor writes nothing until there is content', (t) async {
    await pumpEditor(t);
    await tick(t);
    expect(posts, isEmpty);
  });

  testWidgets('changes autosave every 10 s, titled "Untitled document"', (
    t,
  ) async {
    await pumpEditor(t);
    // Fill in a paper field (student name) — content, but no essay title.
    await t.enterText(studentName, 'Jane Doe');
    await tick(t);

    expect(posts, hasLength(1));
    // A new doc brings its own UUID → the create is an idempotent upsert.
    final id = posts.single['id'] as String?;
    expect(
      id,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(posts.single['title'], 'Untitled document');
    expect(keys.single, isNotEmpty, reason: 'POST carries an Idempotency-Key');

    // No change → no write.
    await tick(t);
    expect(posts, hasLength(1));

    // Next change updates the same document, under a fresh key.
    await t.enterText(studentName, 'Jane Q. Doe');
    await tick(t);
    expect(posts, hasLength(2));
    expect(posts.last['id'], id);
    expect(keys.last, isNot(keys.first));
  });

  testWidgets(
    'the saved title is the essay title; later saves update in place',
    (t) async {
      await pumpEditor(t, id: 'doc-7', json: jsonEncode({'v': 2, 'body': 'x'}));
      await tick(t);
      expect(posts, isEmpty, reason: 'opened doc starts clean');

      // Renaming in the doc bar renames the essay.
      await t.enterText(find.byType(TextField).first, 'AI Safety');
      await tick(t);
      expect(posts, hasLength(1));
      expect(posts.single['id'], 'doc-7');
      expect(posts.single['title'], 'AI Safety');
      final state =
          jsonDecode(posts.single['content'] as String) as Map<String, dynamic>;
      expect(state['title'], 'AI Safety');
    },
  );

  testWidgets('signed out → autosave does not write', (t) async {
    token = null;
    await pumpEditor(t);
    await t.enterText(studentName, 'Jane Doe');
    await tick(t);
    expect(posts, isEmpty);
  });
}
