import 'package:doc_oct/src/application/wizard_session.dart';
import 'package:doc_oct/src/domain/hein_analysis.dart';
import 'package:doc_oct/src/domain/outline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await WizardSession.init();
  });

  test('saves prompt and reuses it as search topic', () async {
    await WizardSession.savePrompt('  Social media and anxiety  ');
    expect(WizardSession.prompt, 'Social media and anxiety');
    expect(WizardSession.searchTopic, 'Social media and anxiety');
  });

  test('new prompt replaces the previous topic and clears old analysis',
      () async {
    await WizardSession.savePrompt('old assignment');
    await WizardSession.saveAnalysis(const HeinAnalysis(
      analysis: 'old',
      essayTopic: 'Old topic',
      essayType: 'Narrative',
      scope: 'x',
      structure: 'y',
    ));
    await WizardSession.saveOutlines(const [
      OutlineData(
        type: 'Introduction',
        title: 'Old intro',
        description: '',
        bullets: ['x'],
      ),
    ]);
    await WizardSession.savePrompt('new assignment');
    expect(WizardSession.searchTopic, 'new assignment');
    expect(WizardSession.analysis, isNull);
    expect(WizardSession.outlines, isEmpty);
  });

  test('saves Lily outlines for the editor', () async {
    await WizardSession.saveOutlines(const [
      OutlineData(
        type: 'Introduction',
        title: 'Hook',
        description: '',
        bullets: ['context'],
      ),
    ]);
    expect(WizardSession.outlines, hasLength(1));
    expect(WizardSession.outlines.first.title, 'Hook');
  });

  test('Hein essayTopic becomes the search topic', () async {
    await WizardSession.savePrompt('long assignment sheet text');
    await WizardSession.saveAnalysis(const HeinAnalysis(
      analysis: 'summary',
      essayTopic: 'Social media',
      essayType: 'Argumentative',
      scope: 'teens',
      structure: '5-paragraph',
    ));
    expect(WizardSession.searchTopic, 'Social media');
    expect(WizardSession.analysis?.essayType, 'Argumentative');
  });
}
