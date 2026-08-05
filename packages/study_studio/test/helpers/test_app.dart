import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/application/providers.dart';
import 'package:study_studio/src/domain/entities/studio.dart';

import 'fake_studio_repository.dart';

Future<void> pumpTestApp(
  WidgetTester tester, {
  required Widget child,
  List<Studio> studios = const [],
  Object? error,
  Duration delay = Duration.zero,
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
        authStateProvider.overrideWith(
          (ref) => Stream<bool>.value(false),
        ),
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