import 'package:flutter/foundation.dart';

const bool _forceMobile = bool.fromEnvironment('FORCE_MOBILE');

/// True on Android and iOS (including mobile browsers), where GhostWriter
/// shows its phone UI instead of the desktop layout.
///
/// Pass `--dart-define=FORCE_MOBILE=true` to preview the phone UI on
/// desktop or in a desktop browser.
bool get isMobilePlatform =>
    _forceMobile ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;
