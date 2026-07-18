import 'package:cockpit_module/cockpit_module.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'presentation/analytics/study_analytics_page.dart';
import 'presentation/building/building_page.dart';
import 'presentation/dashboard/dashboard_page.dart';
import 'presentation/flashcards/flashcards_page.dart';
import 'presentation/home/study_home_page.dart';
import 'presentation/progress/progress_page.dart';
import 'presentation/quiz_me/quiz_me_page.dart';
import 'presentation/ready/ready_page.dart';
import 'presentation/teach_me/teach_me_page.dart';
import 'presentation/topic_detail/topic_detail_page.dart';
import 'presentation/topic_library/topic_library_page.dart';
import 'presentation/upload/upload_page.dart';
import 'presentation/welcome/welcome_back_page.dart';

/// Study Studio as a pluggable Cockpit module. The shell mounts this only when
/// `study_studio_enabled` is on.
class StudyStudioModule extends CockpitModule {
  const StudyStudioModule();

  @override
  String get id => 'study_studio';

  @override
  String get title => 'Study Studio';

  @override
  String get description => 'Turn any material into an AI study environment.';

  @override
  IconData get icon => Icons.school_rounded;

  @override
  Color? get accentColor => const Color(0xFF4F46E5);

  @override
  String get rootPath => '/study';

  @override
  bool get enabledByDefault => true;

  @override
  List<RouteBase> routes() => [
    GoRoute(
      path: '/study',
      builder: (_, _) => const StudyHomePage(),
      routes: [
        // Static siblings declared before the `:studioId` param route.
        GoRoute(path: 'upload', builder: (_, _) => const UploadPage()),
        GoRoute(
          path: 'build/:jobId',
          builder: (_, state) =>
              BuildingPage(jobId: state.pathParameters['jobId']!),
        ),
        GoRoute(path: 'welcome', builder: (_, _) => const WelcomeBackPage()),
        GoRoute(
          path: ':studioId',
          builder: (_, state) =>
              DashboardPage(studioId: state.pathParameters['studioId']!),
          routes: [
            GoRoute(
              path: 'ready',
              builder: (_, state) =>
                  ReadyPage(studioId: state.pathParameters['studioId']!),
            ),
            GoRoute(
              path: 'topics',
              builder: (_, state) =>
                  TopicLibraryPage(studioId: state.pathParameters['studioId']!),
            ),
            GoRoute(
              path: 'topics/:topicId',
              builder: (_, state) => TopicDetailPage(
                studioId: state.pathParameters['studioId']!,
                topicId: state.pathParameters['topicId']!,
              ),
            ),
            GoRoute(
              path: 'teach/:topicId',
              builder: (_, state) => TeachMePage(
                studioId: state.pathParameters['studioId']!,
                topicId: state.pathParameters['topicId']!,
              ),
            ),
            GoRoute(
              path: 'quiz',
              builder: (_, state) => QuizMePage(
                studioId: state.pathParameters['studioId']!,
                topicId: state.uri.queryParameters['topicId'],
              ),
            ),
            GoRoute(
              path: 'flashcards',
              builder: (_, state) => FlashcardsPage(
                studioId: state.pathParameters['studioId']!,
                topicId: state.uri.queryParameters['topicId'],
              ),
            ),
            GoRoute(
              path: 'progress',
              builder: (_, state) =>
                  ProgressPage(studioId: state.pathParameters['studioId']!),
            ),
            GoRoute(
              path: 'analytics',
              builder: (_, state) => StudyAnalyticsPage(
                studioId: state.pathParameters['studioId']!,
              ),
            ),
          ],
        ),
      ],
    ),
  ];
}
