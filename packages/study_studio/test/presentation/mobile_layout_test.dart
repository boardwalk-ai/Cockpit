import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/data/mock/mock_data.dart';
import 'package:study_studio/src/presentation/analytics/study_analytics_page.dart';
import 'package:study_studio/src/presentation/ask_ai/ask_ai_page.dart';
import 'package:study_studio/src/presentation/building/building_page.dart';
import 'package:study_studio/src/presentation/dashboard/dashboard_page.dart';
import 'package:study_studio/src/presentation/flashcards/flashcards_page.dart';
import 'package:study_studio/src/presentation/home/study_home_page.dart';
import 'package:study_studio/src/presentation/knowledge_graph/knowledge_graph_page.dart';
import 'package:study_studio/src/presentation/lightning_recall/lightning_recall_page.dart';
import 'package:study_studio/src/presentation/manage/manage_study_studio_page.dart';
import 'package:study_studio/src/presentation/mastery_report/mastery_report_page.dart';
import 'package:study_studio/src/presentation/progress/progress_page.dart';
import 'package:study_studio/src/presentation/quiz_me/quiz_me_page.dart';
import 'package:study_studio/src/presentation/ready/ready_page.dart';
import 'package:study_studio/src/presentation/scenario_mode/scenario_mode_page.dart';
import 'package:study_studio/src/presentation/study_plan/study_plan_page.dart';
import 'package:study_studio/src/presentation/teach_me/teach_me_page.dart';
import 'package:study_studio/src/presentation/topic_detail/topic_detail_page.dart';
import 'package:study_studio/src/presentation/topic_library/topic_library_page.dart';
import 'package:study_studio/src/presentation/upload/upload_page.dart';
import 'package:study_studio/src/presentation/welcome/welcome_back_page.dart';
import 'package:study_studio/src/presentation/widgets/mobile_layout.dart';
import 'package:study_studio/src/presentation/widgets/studio_scaffold.dart';

import '../helpers/test_app.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('Outfit')
      ..addFont(
        File('../../apps/cockpit/assets/fonts/Outfit-VariableFont_wght.ttf')
            .readAsBytes()
            .then((bytes) => ByteData.sublistView(bytes)),
      );
    await loader.load();
  });
  final pages = <String, Widget>{
    'teach_me': const TeachMePage(studioId: 'bio', topicId: 'bio_dna'),
    'home': const StudyHomePage(),
    'upload': const UploadPage(),
    'building': const BuildingPage(jobId: 'test'),
    'ready': const ReadyPage(studioId: 'bio'),
    'dashboard': const DashboardPage(studioId: 'bio'),
    'topic_library': const TopicLibraryPage(studioId: 'bio'),
    'topic_detail': const TopicDetailPage(studioId: 'bio', topicId: 'bio_dna'),
    'quiz_me': const QuizMePage(studioId: 'bio'),
    'flashcards': const FlashcardsPage(studioId: 'bio'),
    'progress': const ProgressPage(studioId: 'bio'),
    'mastery_report': const MasteryReportPage(studioId: 'bio'),
    'study_plan': const StudyPlanPage(studioId: 'bio'),
    'knowledge_graph': const KnowledgeGraphPage(studioId: 'bio'),
    'lightning_recall': const LightningRecallPage(studioId: 'bio'),
    'scenario_mode': const ScenarioModePage(studioId: 'bio'),
    'analytics': const StudyAnalyticsPage(studioId: 'bio'),
    'ask_ai': const AskAiPage(studioId: 'bio'),
    'manage': const ManageStudyStudioPage(studioId: 'bio'),
    'welcome': const WelcomeBackPage(),
  };
  for (final width in [320.0, 390.0, 1280.0]) {
    for (final page in pages.entries) {
      testWidgets('${page.key} at $width has no layout exceptions', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final originalErrorHandler = FlutterError.onError!;
        FlutterError.onError = (details) {
          FlutterError.dumpErrorToConsole(details, forceReport: true);
          originalErrorHandler(details);
        };
        await pumpTestApp(
          tester,
          child: StudyMobileSurface(child: page.value),
          studios: buildMockStudiosStashed(),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
        final scrolls = find.byType(Scrollable);
        if (scrolls.evaluate().isNotEmpty) {
          for (var i = 0; i < 4; i++) {
            await tester.drag(scrolls.first, const Offset(0, -450));
            await tester.pump(const Duration(milliseconds: 100));
            expect(tester.takeException(), isNull);
          }
        }
        await tester.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
  testWidgets(
    'platform gate keeps wide Android mobile and wide Windows desktop',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.windows,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) =>
                  Text(isMobilePlatform(context) ? 'phone' : 'desktop'),
            ),
          ),
        );
        expect(
          find.text(platform == TargetPlatform.windows ? 'desktop' : 'phone'),
          findsOneWidget,
        );
      }
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
