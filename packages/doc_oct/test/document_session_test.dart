import 'dart:convert';

import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:doc_oct/doc_oct.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Each saved document carries its own session (topic, Hein analysis, Lily
/// outlines, sources) in `documents.state`; opening it restores that session.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await WizardSession.init();
  });

  Future<void> openDoc(WidgetTester t, Map<String, dynamic> state) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1280, 720);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: BorderlessTheme.build(Brightness.dark),
          home: EditorPage(
            initialDocId: 'doc-1',
            initialDocJson: jsonEncode(state),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('opening a doc restores its analysis, outlines and sources', (
    t,
  ) async {
    await openDoc(t, {
      'v': 2,
      'style': 'apa',
      'docTitle': 'AI Safety',
      'title': 'AI Safety',
      'body': 'Hello world',
      'onboardingTopic': 'The importance of AI safety',
      'assignmentAnalysis': {
        'analysis': 'Explain why AI safety matters.',
        'essayTopic': 'AI Safety',
        'essayType': 'Expository',
        'scope': 'risks',
        'structure': '5 paragraphs',
      },
      'outlines': [
        {
          'type': 'Introduction',
          'title': 'Why alignment matters',
          'description': '',
          'bullets': ['Define AI safety'],
        },
      ],
      'sources': [
        {
          'url': 'https://example.org/a',
          'title': 'Concrete Problems in AI Safety',
          'author': 'Amodei, Dario',
          'publishedYear': '2016',
          'publisher': 'arXiv',
          'fullContent': '',
        },
      ],
    });

    expect(WizardSession.analysis?.essayTopic, 'AI Safety');
    expect(WizardSession.prompt, 'The importance of AI safety');
    expect(WizardSession.outlines.single.title, 'Why alignment matters');
    // The Outline panel shows this document's analysis + outline.
    expect(find.text('Explain why AI safety matters.'), findsOneWidget);
    expect(find.text('Why alignment matters'), findsOneWidget);
    // Sources restored → the references page is not in its empty state.
    expect(
      find.textContaining('No sources yet', skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets('a doc without a session clears the previous one', (t) async {
    await WizardSession.saveAnalysis(
      const HeinAnalysis(
        analysis: 'Stale analysis from another document.',
        essayTopic: 'The Vikings',
        essayType: '',
        scope: '',
        structure: '',
      ),
    );
    await WizardSession.saveOutlines(const [
      OutlineData(
        type: 'Introduction',
        title: 'Stale',
        description: '',
        bullets: [],
      ),
    ]);

    await openDoc(t, {
      'v': 1,
      'style': 'mla',
      'docTitle': 'Old doc',
      'body': 'x',
    });

    expect(WizardSession.analysis, isNull);
    expect(WizardSession.outlines, isEmpty);
    expect(find.text('Stale analysis from another document.'), findsNothing);
    expect(
      find.textContaining('No sources yet', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('web-app docs: sourceResults are read as sources', (t) async {
    await openDoc(t, {
      'formatStyle': 'mla',
      'analyzedTopic': 'Woman in the 20th century',
      'sourceResults': [
        {
          'url': 'https://localhistories.org/x',
          'title': 'A Timeline of Women in the 20th Century',
          'author': 'Tim Lambert',
          'publisher': 'Local Histories',
          'fullContent': '',
        },
      ],
    });
    expect(WizardSession.searchTopic, 'Woman in the 20th century');
    expect(
      find.textContaining('No sources yet', skipOffstage: false),
      findsNothing,
    );
  });
}
