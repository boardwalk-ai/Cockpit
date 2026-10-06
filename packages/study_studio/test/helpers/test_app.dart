import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/application/providers.dart';
import 'package:study_studio/src/application/study_voice.dart';
import 'package:study_studio/src/domain/entities/studio.dart';

import 'fake_studio_repository.dart';

Future<void> pumpTestApp(
  WidgetTester tester, {
  required Widget child,
  List<Studio> studios = const [],
  Object? error,
  Duration delay = Duration.zero,
  bool signedIn = true,
  StudyVoice? voice,
}) async {
  final repository = FakeStudioRepository(
    studios: studios,
    error: error,
    delay: delay,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        studioRepositoryProvider.overrideWithValue(repository),
        // Study Home gates on auth: signed out shows the Sign-in screen, so
        // sign in by default to exercise the studio-list states.
        authStateProvider.overrideWith((ref) => Stream<bool>.value(signedIn)),
        if (voice != null) studyVoiceProvider.overrideWithValue(voice),
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
