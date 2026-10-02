import 'package:cockpit_module/cockpit_module.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'ghostwriter_root.dart';
import 'mobile/mobile_theme.dart';

/// GhostWriter as a pluggable Cockpit module.
class GhostWriterModule extends CockpitModule {
  const GhostWriterModule();

  @override
  String get id => 'ghostwriter';

  @override
  String get title => 'GhostWriter';

  @override
  String get description => 'Draft fast. Revise cleanly.';

  @override
  IconData get icon => Icons.edit_note_rounded;

  @override
  Color? get accentColor => GwColors.accent;

  @override
  String get rootPath => '/ghostwriter';

  @override
  bool get enabledByDefault => true;

  @override
  List<RouteBase> routes() => [
    GoRoute(path: '/ghostwriter', builder: (_, _) => const GhostWriterRoot()),
  ];
}
