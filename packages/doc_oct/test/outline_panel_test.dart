import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:doc_oct/doc_oct.dart';
import 'package:doc_oct/src/presentation/editor/outline_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await WizardSession.init();
  });

  Widget wrap(Widget child) => MaterialApp(
    theme: BorderlessTheme.build(Brightness.dark),
    home: Scaffold(body: SizedBox(width: 340, child: child)),
  );

  testWidgets('left panel shows Hein analysis above outline cards', (t) async {
    await WizardSession.saveAnalysis(
      const HeinAnalysis(
        analysis: 'Examine how Norse seafarers reshaped medieval Europe.',
        essayTopic: 'The Vikings',
        essayType: 'Analytical',
        scope: '8th–11th century North Atlantic',
        structure: 'Intro · body · conclusion',
      ),
    );
    await WizardSession.saveOutlines(const [
      OutlineData(
        type: 'Introduction',
        title: 'Beyond the myth of raiders',
        description: '',
        bullets: ['Definition of the Viking Age'],
      ),
    ]);

    await t.pumpWidget(wrap(const OutlinePanel()));
    await t.pumpAndSettle();

    expect(find.text('ANALYSIS'), findsOneWidget);
    expect(
      find.text('Examine how Norse seafarers reshaped medieval Europe.'),
      findsOneWidget,
    );
    expect(find.text('The Vikings'), findsOneWidget);
    expect(find.text('Analytical'), findsOneWidget);
    expect(find.text('Beyond the myth of raiders'), findsOneWidget);
    expect(find.text('Definition of the Viking Age'), findsOneWidget);
    expect(find.textContaining('Your outline'), findsOneWidget);
  });

  group('no topic yet ("Start writing" skipped the wizard)', () {
    testWidgets('asks for the topic, analyzes, then generates', (t) async {
      final hein = _FakeHein();
      final lily = _FakeLily();
      String? topicSet;
      await t.pumpWidget(
        wrap(
          OutlinePanel(
            topic: 'Untitled document',
            hein: hein,
            lily: lily,
            onTopicSet: (v) => topicSet = v,
          ),
        ),
      );
      await t.pumpAndSettle();

      await t.tap(find.text('Auto Outline'));
      await t.pumpAndSettle();
      expect(find.text('What is your essay about?'), findsOneWidget);
      expect(lily.lastMode, isNull, reason: 'nothing runs before a topic');

      await t.enterText(
        find.byType(TextField).last,
        'The importance of AI safety',
      );
      await t.pump();
      await t.tap(find.text('Analyze & Generate'));
      await t.pumpAndSettle();

      expect(hein.lastInstructions, 'The importance of AI safety');
      expect(lily.lastMode, LilyMode.auto);
      expect(lily.lastAnalysis?.essayTopic, 'AI Safety');
      expect(topicSet, 'AI Safety');
      expect(WizardSession.analysis?.essayTopic, 'AI Safety');
      expect(find.text('Generated section'), findsOneWidget);
      expect(find.text('ANALYSIS'), findsOneWidget);
    });

    testWidgets('cancelling the topic prompt generates nothing', (t) async {
      final hein = _FakeHein();
      final lily = _FakeLily();
      await t.pumpWidget(wrap(OutlinePanel(hein: hein, lily: lily)));
      await t.pumpAndSettle();

      await t.tap(find.text('One Paragraph'));
      await t.pumpAndSettle();
      await t.tap(find.text('Conclusion'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();

      expect(hein.lastInstructions, isNull);
      expect(lily.lastMode, isNull);
      expect(WizardSession.outlines, isEmpty);
    });

    test('WizardSession.clear forgets a previous topic', () async {
      await WizardSession.savePrompt('Old topic');
      await WizardSession.saveAnalysis(
        const HeinAnalysis(
          analysis: 'a',
          essayTopic: 'Old',
          essayType: '',
          scope: '',
          structure: '',
        ),
      );
      await WizardSession.clear();
      expect(WizardSession.analysis, isNull);
      expect(WizardSession.searchTopic, isEmpty);
      expect(WizardSession.outlines, isEmpty);
    });
  });

  group('outline modes (same as the wizard)', () {
    const analysis = HeinAnalysis(
      analysis: 'Argue a claim.',
      essayTopic: 'AI safety',
      essayType: 'Argumentative',
      scope: '',
      structure: '',
    );

    setUp(() => WizardSession.saveAnalysis(analysis));

    testWidgets('shows all three mode pills', (t) async {
      await t.pumpWidget(wrap(OutlinePanel(lily: _FakeLily())));
      await t.pumpAndSettle();
      expect(find.text('Build My Way'), findsOneWidget);
      expect(find.text('Auto Outline'), findsOneWidget);
      expect(find.text('One Paragraph'), findsOneWidget);
    });

    testWidgets('Auto Outline generates the outline', (t) async {
      final lily = _FakeLily();
      await t.pumpWidget(wrap(OutlinePanel(lily: lily)));
      await t.pumpAndSettle();
      await t.tap(find.text('Auto Outline'));
      await t.pumpAndSettle();
      expect(lily.lastMode, LilyMode.auto);
      expect(find.text('Generated section'), findsOneWidget);
      expect(WizardSession.outlines, hasLength(1));
    });

    testWidgets('One Paragraph asks Lily for the chosen type', (t) async {
      final lily = _FakeLily();
      await t.pumpWidget(wrap(OutlinePanel(lily: lily)));
      await t.pumpAndSettle();
      await t.tap(find.text('One Paragraph'));
      await t.pumpAndSettle();
      await t.tap(find.text('Conclusion'));
      await t.pumpAndSettle();
      expect(lily.lastMode, LilyMode.single);
      expect(lily.lastType, 'Conclusion');
      expect(find.text('Generated section'), findsOneWidget);
    });

    testWidgets('Build My Way sends the prompt and type, appending', (t) async {
      await WizardSession.saveOutlines(const [
        OutlineData(
          type: 'Introduction',
          title: 'Existing',
          description: '',
          bullets: [],
        ),
      ]);
      final lily = _FakeLily();
      await t.pumpWidget(wrap(OutlinePanel(lily: lily)));
      await t.pumpAndSettle();
      await t.tap(find.text('Build My Way'));
      await t.pumpAndSettle();
      await t.tap(find.text('Body Paragraph'));
      await t.enterText(find.byType(TextField), 'alignment research');
      await t.tap(find.text('Build paragraph'));
      await t.pumpAndSettle();
      expect(lily.lastMode, LilyMode.build);
      expect(lily.lastType, 'Body Paragraph');
      expect(lily.lastTitle, 'alignment research');
      expect(find.text('Existing'), findsOneWidget);
      expect(find.text('alignment research'), findsOneWidget);
      expect(WizardSession.outlines, hasLength(2));
    });
  });
}

class _FakeHein implements HeinService {
  String? lastInstructions;

  @override
  Future<HeinAnalysis> analyze({
    required String instructions,
    String essayType = '',
  }) async {
    lastInstructions = instructions;
    return const HeinAnalysis(
      analysis: 'Explain why AI safety matters.',
      essayTopic: 'AI Safety',
      essayType: 'Expository',
      scope: '',
      structure: '',
    );
  }
}

class _FakeLily implements LilyService {
  HeinAnalysis? lastAnalysis;
  LilyMode? lastMode;
  String? lastType;
  String? lastTitle;

  @override
  Future<List<OutlineData>> generate({
    required LilyMode mode,
    HeinAnalysis? analysis,
    String essayTopic = '',
    String? requestedType,
    String? customTitle,
    int? count,
    bool bullets = true,
  }) async {
    lastMode = mode;
    lastAnalysis = analysis;
    lastType = requestedType;
    lastTitle = customTitle;
    return [
      OutlineData(
        type: requestedType ?? 'Introduction',
        title: customTitle ?? 'Generated section',
        description: '',
        bullets: const ['point one'],
      ),
    ];
  }
}
