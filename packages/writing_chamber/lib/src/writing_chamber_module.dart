import 'package:cockpit_module/cockpit_module.dart';
import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'presentation/writing_chamber_page.dart';

class WritingChamberModule extends CockpitModule {
  const WritingChamberModule();

  @override
  String get id => 'writing_chamber';

  @override
  String get title => 'Writing Chamber';

  @override
  String get description => 'Research, generate, and refine a sourced essay.';

  @override
  IconData get icon => Icons.edit_note_rounded;

  @override
  Color? get accentColor => CockpitColors.brand.primary;

  @override
  String get rootPath => '/writing-chamber';

  @override
  bool get enabledByDefault => true;

  @override
  List<RouteBase> routes() => [
    GoRoute(
      path: rootPath,
      builder: (_, state) =>
          WritingChamberPage(threadId: state.uri.queryParameters['threadId']),
    ),
  ];
}
