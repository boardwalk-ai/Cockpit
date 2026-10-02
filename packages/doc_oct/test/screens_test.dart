import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:doc_oct/doc_oct.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget page, Brightness b) => ProviderScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: BorderlessTheme.build(b),
        home: page,
      ),
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await WizardSession.init();
  });

  Future<void> desktop(WidgetTester t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1280, 720);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
  }

  for (final b in [Brightness.dark, Brightness.light]) {
    testWidgets('loading screen renders ($b)', (t) async {
      await desktop(t);
      await t.pumpWidget(_wrap(const DocOctLoadingPage(progress: 0.78), b));
      await t.pump(const Duration(milliseconds: 30));
      expect(find.text('78%'), findsOneWidget);
      expect(find.textContaining('ACADEMIC FORMATTER ENGINE'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('wizard welcome renders without overflow ($b)', (t) async {
      await desktop(t);
      await t.pumpWidget(_wrap(const WizardWelcomePage(), b));
      await t.pumpAndSettle();
      expect(find.text('Specify my topic'), findsOneWidget);
      expect(find.text('Start writing'), findsOneWidget);
      expect(find.text('Topic'), findsOneWidget); // step label
      expect(find.byType(ThemeSwitcher), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('wizard setup renders without overflow ($b)', (t) async {
      await desktop(t);
      await t.pumpWidget(_wrap(const WizardSetupPage(), b));
      await t.pumpAndSettle();
      expect(find.text('CITATION FORMAT'), findsOneWidget);
      expect(find.text('Setup'), findsOneWidget); // step label
      expect(find.text('Open Editor'), findsOneWidget); // empty-topic CTA
      // All five citation styles present as pills.
      for (final s in FormatStyle.values) {
        expect(find.text(s.short), findsWidgets);
      }
      expect(find.byType(ThemeSwitcher), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('wizard analysis renders without overflow ($b)', (t) async {
      await desktop(t);
      await t.pumpWidget(_wrap(
        const WizardAnalysisPage(
          topic: 'The impact of social media on mental health',
          style: FormatStyle.apa,
          initialAnalysis: HeinAnalysis(
            analysis: 'Take a position and defend it with evidence.',
            essayTopic: 'The impact of social media on mental health',
            essayType: 'Argumentative essay',
            scope: 'Focused — one core claim',
            structure: 'Intro · body · conclusion',
          ),
        ),
        b,
      ));
      await t.pumpAndSettle();
      expect(find.text('Continue to Editor'), findsOneWidget);
      expect(find.text('Build My Way'), findsOneWidget);
      expect(find.text('Auto Outline'), findsOneWidget);
      expect(find.text('One Paragraph'), findsOneWidget);
      expect(find.text('Analysis'), findsOneWidget); // step label
      expect(find.byType(ThemeSwitcher), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('workspace renders without overflow ($b)', (t) async {
      await desktop(t);
      await t.pumpWidget(_wrap(const WorkspacePage(), b));
      await t.pumpAndSettle();
      expect(find.textContaining('workspace'), findsOneWidget);
      expect(find.text('Blank'), findsOneWidget);
      expect(find.text('MLA Paper'), findsOneWidget);
      expect(find.text('Harvard Paper'), findsOneWidget);
      expect(find.byType(ThemeSwitcher), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('editor renders + lossless restyle APA→MLA ($b)', (t) async {
      await desktop(t);
      await t.pumpWidget(_wrap(const EditorPage(), b));
      await t.pumpAndSettle();
      // Chrome present.
      expect(find.text('STYLE'), findsOneWidget);
      expect(find.text('Finish'), findsOneWidget);
      expect(find.text('Format'), findsOneWidget);
      // APA title page shows the centred title block placeholders (the title
      // also repeats on the body page, so it can appear more than once).
      expect(find.text('Untitled Paper'), findsWidgets);
      expect(find.text('Institution Name'), findsOneWidget);
      // References page renders formatted entries from the sources.
      expect(find.text('References'), findsOneWidget);
      // Type into the student-name field, then restyle to MLA.
      await t.enterText(find.widgetWithText(TextField, 'Student Name'), 'Ada Lovelace');
      await t.pumpAndSettle();
      // Style-row pill is first in the tree (the Tools tab repeats the labels).
      await t.ensureVisible(find.text('MLA').first);
      await t.tap(find.text('MLA').first);
      await t.pumpAndSettle();
      // Content survives the restyle (no loss); MLA drops the abstract slot
      // and re-headers the bibliography as "Works Cited".
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('Works Cited'), findsOneWidget);
      expect(find.text('References'), findsNothing);

      // Every style projects its own bibliography heading, content intact.
      for (final (pill, heading) in const [
        ('Chicago', 'Bibliography'),
        ('IEEE', 'References'),
        ('Harvard', 'Reference List'),
      ]) {
        await t.ensureVisible(find.text(pill).first);
        await t.tap(find.text(pill).first);
        await t.pumpAndSettle();
        expect(find.text(heading), findsOneWidget);
        expect(find.text('Ada Lovelace'), findsOneWidget);
      }
      expect(find.byType(ThemeSwitcher), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
