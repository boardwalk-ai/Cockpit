import 'package:cockpit_module/cockpit_module.dart';
import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'presentation/editor/editor_page.dart';
import 'presentation/outline/outline_page.dart';

class GuidedGenerationModule extends CockpitModule {
  const GuidedGenerationModule();

  @override
  String get id => 'guided_generation';

  @override
  String get title => 'Guided Generation';

  @override
  String get description => 'Build and review an outline before writing.';

  @override
  IconData get icon => Icons.auto_awesome_rounded;

  @override
  Color? get accentColor => CockpitColors.brand.primary;

  @override
  String get rootPath => '/guided-generation';

  @override
  bool get enabledByDefault => true;

  @override
  List<RouteBase> routes() => [
    GoRoute(
      path: rootPath,
      builder: (_, _) => const GuidedOutlinePage(),
      routes: [
        GoRoute(
          path: 'configuration',
          builder: (_, _) => const GuidedNextPage(),
        ),
        GoRoute(
          path: 'editor',
          builder: (_, state) => GuidedEditorPage(
            threadId: state.uri.queryParameters['threadId'],
          ),
        ),
      ],
    ),
  ];
}
