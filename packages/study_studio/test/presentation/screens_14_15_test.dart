import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/presentation/ask_ai/ask_ai_page.dart';
import 'package:study_studio/src/presentation/manage/manage_study_studio_page.dart';

/// Screens 14 (Ask AI) and 15 (Manage Study Studio) are desktop-first surfaces.
/// These guard the desktop viewport (1281x720): the studio title comes from the
/// real studio (not a hardcoded exam name) and nothing overflows the viewport.
void main() {
  Future<void> setDesktopViewport(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1281, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }

  Widget app(Widget home) {
    return ProviderScope(
      child: MaterialApp(
        theme: CockpitTheme.build(
          colors: CockpitColors.brand,
          fonts: CockpitFonts.brand,
          brightness: Brightness.light,
        ),
        home: home,
      ),
    );
  }

  testWidgets(
    'Screen 14 (Ask AI) fits the desktop viewport with a live title',
    (tester) async {
      await setDesktopViewport(tester);
      await tester.pumpWidget(app(const AskAiPage(studioId: 'bio')));
      await tester.pumpAndSettle();

      // Title is driven by the studio, not a hardcoded exam name.
      expect(find.text('Computer Networks Final Exam'), findsNothing);
      expect(find.text('Ask AI'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Screen 15 (Manage) fits the desktop viewport with a live title',
    (tester) async {
      await setDesktopViewport(tester);
      await tester.pumpWidget(
        app(const ManageStudyStudioPage(studioId: 'bio')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Computer Networks Final Exam'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
