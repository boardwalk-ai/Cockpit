import 'package:flutter/foundation.dart';

enum AppFlavor { dev, staging, prod }

/// Global, build-time configuration. Provide the active config near app start
/// and read it via [appConfigProvider].
@immutable
class AppConfig {
  const AppConfig({
    required this.flavor,
    required this.apiBaseUrl,
    this.appName = 'Octopilot Cockpit',
  });

  final AppFlavor flavor;
  final String apiBaseUrl;
  final String appName;

  static const AppConfig dev = AppConfig(
    flavor: AppFlavor.dev,
    apiBaseUrl: 'https://api.dev.octopilotai.com',
  );

  bool get isProd => flavor == AppFlavor.prod;
}
