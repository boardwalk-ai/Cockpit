import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwriter/src/mobile/mobile_landing.dart';
import 'package:ghostwriter/src/mobile/mobile_motion.dart';
import 'package:ghostwriter/src/mobile/mobile_top_bar.dart';

import 'support.dart';

void main() {
  testWidgets('mobile platforms get the phone landing and top bar', (
    tester,
  ) async {
    await tester.pumpWidget(const GhostWriterApp());

    expect(find.byType(GhostWriterMobileTopBar), findsOneWidget);
    expect(find.byType(GhostWriterMobileLanding), findsOneWidget);
  });

  testWidgets('menu button opens the essays drawer', (tester) async {
    await tester.pumpWidget(const GhostWriterApp());

    await tester.tap(find.byTooltip('Essays'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('New chat'), findsOneWidget);
  });

  testWidgets('Start is disabled until a brief is typed', (tester) async {
    await tester.pumpWidget(const GhostWriterApp());

    GwPressable startButton() =>
        tester.widget<GwPressable>(find.byKey(const ValueKey('gw-start')));

    expect(startButton().onTap, isNull);

    await tester.enterText(find.byType(TextField), 'An essay on tides');
    await tester.pump();

    expect(startButton().onTap, isNotNull);
  });

  testWidgets('desktop platforms keep the desktop layout', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const GhostWriterApp());

    expect(find.byType(GhostWriterMobileLanding), findsNothing);
    expect(find.text('Home'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });
}
