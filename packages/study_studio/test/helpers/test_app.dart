import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/application/providers.dart';
import 'package:study_studio/src/data/ai/ai_service.dart';
import 'package:study_studio/src/domain/entities/studio.dart';

import 'fake_studio_repository.dart';

Future<void> pumpTestApp(
  WidgetTester tester, {
  required Widget child,
  List<Studio> studios = const [],
  Object? error,
  Duration delay = Duration.zero,
  bool signedIn = true,
  AiService? aiService,
}) async {
  final repository = FakeStudioRepository(
    studios: studios,
    error: error,
    delay: delay,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (aiService != null) aiServiceProvider.overrideWithValue(aiService),
        studioRepositoryProvider.overrideWithValue(repository),
        authStateProvider.overrideWith((ref) => Stream<bool>.value(signedIn)),
      ],
      child: MaterialApp(
        theme: CockpitTheme.build(
          colors: CockpitColors.brand,
          fonts: CockpitFonts.brand,
          brightness: Brightness.light,
        ),
        home: child,
      ),
    ),
  );
}
