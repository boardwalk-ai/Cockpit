import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:doc_oct/doc_oct.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> setDesktop(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 840);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }

  testWidgets('saved projects renders (borderless) without overflow',
      (tester) async {
    await setDesktop(tester);
    await tester.pumpWidget(const ProviderScope(child: DocOctApp()));
    await tester.pumpAndSettle();

    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('New document'), findsOneWidget);
    expect(
      find.text('The Vikings: Seafaring, Trade, and Settlement'),
      findsOneWidget,
    );
    expect(find.byType(ThemeSwitcher), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme switcher drives the shared controller', (tester) async {
    await setDesktop(tester);
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(builder: (context, r, _) {
          ref = r;
          return const DocOctApp();
        }),
      ),
    );
    await tester.pumpAndSettle();

    ref.read(themeControllerProvider.notifier).setMode(ThemeMode.light);
    await tester.pumpAndSettle();
    expect(ref.read(themeControllerProvider).mode, ThemeMode.light);
    expect(tester.takeException(), isNull);
  });
}
