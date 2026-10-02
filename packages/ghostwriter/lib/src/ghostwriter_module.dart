import 'package:cockpit_module/cockpit_module.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'ghostwriter_root.dart';
import 'gw_auth.dart';
import 'gw_push.dart';
import 'mobile/mobile_theme.dart';

/// GhostWriter as a pluggable Cockpit module. [auth] is the host app's
/// sign-in; without it GhostWriter runs as the dev user.
class GhostWriterModule extends CockpitModule {
  const GhostWriterModule({this.auth, this.push});

  final GwAuth? auth;

  /// The host app's push notifications, if it has them.
  final GwPush? push;

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
    GoRoute(
      path: '/ghostwriter',
      builder: (_, _) => GhostWriterRoot(auth: auth, push: push),
    ),
  ];
}
