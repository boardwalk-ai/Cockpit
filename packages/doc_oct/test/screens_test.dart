import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:doc_oct/doc_oct.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget page, Brightness b) => ProviderScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: BorderlessTheme.build(b),
        home: page,
      ),
    );

void main() {
  Future<void> desktop(WidgetTester t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1280, 720);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
  }

  for (final b in [Brightness.dark, Brightness.light]) {
    testWidgets('loading screen renders ($b)', (t) async {
      await desktop(t);
      await t.pumpWidget(_wrap(const DocOctLoadingPage(progress: 0.78), b));
      await t.pump(const Duration(milliseconds: 30));
      expect(find.text('78%'), findsOneWidget);
      expect(find.textContaining('ACADEMIC FORMATTER ENGINE'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('wizard welcome renders without overflow ($b)', (t) async {
      await desktop(t);
      await t.pumpWidget(_wrap(const WizardWelcomePage(), b));
      await t.pumpAndSettle();
      expect(find.text('Specify my topic'), findsOneWidget);
      expect(find.text('Start writing'), findsOneWidget);
      expect(find.text('Topic'), findsOneWidget); // step label
      expect(find.byType(ThemeSwitcher), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
