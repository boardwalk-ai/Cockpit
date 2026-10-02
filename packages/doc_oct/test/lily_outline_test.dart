import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:doc_oct/doc_oct.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeLily implements LilyService {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await WizardSession.init();
  });

  Widget wrap(Widget page) => ProviderScope(
        child: MaterialApp(
          theme: BorderlessTheme.build(Brightness.dark),
          home: page,
        ),
      );

  const analysis = HeinAnalysis(
    analysis: 'Argue a claim.',
    essayTopic: 'Social media',
    essayType: 'Argumentative',
    scope: 'teens',
    structure: '5-paragraph',
  );

  Future<void> desktop(WidgetTester t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1280, 900);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
  }

  testWidgets('Auto Outline calls Lily and shows the section', (t) async {
    await desktop(t);
    final lily = _FakeLily();
    await t.pumpWidget(wrap(WizardAnalysisPage(
      topic: 'Social media',
      style: FormatStyle.mla,
      initialAnalysis: analysis,
      lily: lily,
    )));
    await t.pumpAndSettle();
    await t.tap(find.text('Auto Outline'));
    await t.pumpAndSettle();
    expect(lily.lastMode, LilyMode.auto);
    expect(find.text('Generated section'), findsOneWidget);
    expect(find.text('point one'), findsOneWidget);
    expect(WizardSession.outlines, hasLength(1));
  });

  testWidgets('One Paragraph asks Lily for the chosen type', (t) async {
    await desktop(t);
    final lily = _FakeLily();
    await t.pumpWidget(wrap(WizardAnalysisPage(
      topic: 'Social media',
      style: FormatStyle.mla,
      initialAnalysis: analysis,
      lily: lily,
    )));
    await t.pumpAndSettle();
    await t.tap(find.text('One Paragraph'));
    await t.pumpAndSettle();
    expect(find.text('Introduction'), findsWidgets);
    await t.tap(find.text('Conclusion'));
    await t.pumpAndSettle();
    expect(lily.lastMode, LilyMode.single);
    expect(lily.lastType, 'Conclusion');
    expect(find.text('Generated section'), findsOneWidget);
  });

  testWidgets('Build My Way sends the prompt and type', (t) async {
    await desktop(t);
    final lily = _FakeLily();
    await t.pumpWidget(wrap(WizardAnalysisPage(
      topic: 'Social media',
      style: FormatStyle.mla,
      initialAnalysis: analysis,
      lily: lily,
    )));
    await t.pumpAndSettle();
    await t.tap(find.text('Build My Way'));
    await t.pumpAndSettle();
    await t.enterText(
      find.byType(TextField).last,
      'algorithmic feeds',
    );
    await t.tap(find.text('Build paragraph'));
    await t.pumpAndSettle();
    expect(lily.lastMode, LilyMode.build);
    expect(lily.lastType, 'Introduction');
    expect(lily.lastTitle, 'algorithmic feeds');
    expect(find.text('algorithmic feeds'), findsOneWidget);
  });
}
