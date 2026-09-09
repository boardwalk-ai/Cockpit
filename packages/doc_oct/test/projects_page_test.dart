import 'package:doc_oct/doc_oct.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Forces the light theme for the light-mode case.
class _LightController extends DocThemeController {
  @override
  ThemeMode build() => ThemeMode.light;
}

void main() {
  Future<void> setDesktop(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 840);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }

  testWidgets('saved projects renders in dark without overflow', (tester) async {
    await setDesktop(tester);
    await tester.pumpWidget(const ProviderScope(child: DocOctApp()));
    await tester.pumpAndSettle();

    expect(find.text('Your documents'), findsOneWidget);
    expect(find.text('New document'), findsWidgets);
    expect(
      find.text('The Vikings: Seafaring, Trade, and Settlement'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved projects renders in light + theme switcher present',
      (tester) async {
    await setDesktop(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          docThemeControllerProvider.overrideWith(_LightController.new),
        ],
        child: const DocOctApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your documents'), findsOneWidget);
    expect(find.byType(DocThemeSwitcher), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme switcher toggles mode', (tester) async {
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

    expect(ref.read(docThemeControllerProvider), ThemeMode.dark);
    await tester.tap(find.byType(DocThemeSwitcher));
    await tester.pumpAndSettle();
    expect(ref.read(docThemeControllerProvider), ThemeMode.light);
  });
}
