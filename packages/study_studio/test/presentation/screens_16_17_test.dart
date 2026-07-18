import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/presentation/analytics/study_analytics_page.dart';
import 'package:study_studio/src/presentation/welcome/welcome_back_page.dart';

void main() {
  Future<void> setPhoneViewport(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }

  Widget app(Widget home) {
    return MaterialApp(
      theme: CockpitTheme.build(
        colors: CockpitColors.brand,
        fonts: CockpitFonts.brand,
        brightness: Brightness.light,
      ),
      home: home,
    );
  }

  testWidgets('Screen 16 renders analytics at a phone viewport', (
    tester,
  ) async {
    await setPhoneViewport(tester);
    await tester.pumpWidget(app(const StudyAnalyticsPage(studioId: 'bio')));

    final performanceChart = tester.getSize(
      find.byKey(const ValueKey('study-analytics-performance-chart')),
    );
    final retentionChart = tester.getSize(
      find.byKey(const ValueKey('study-analytics-retention-chart')),
    );
    const expectedChartWidth =
        (375 - CockpitSpacing.md * 2 - CockpitSpacing.sm) / 2 -
        CockpitSpacing.sm * 2 -
        2; // One-pixel card border on each side.

    expect(performanceChart.width, closeTo(expectedChartWidth, 0.1));
    expect(retentionChart.width, closeTo(expectedChartWidth, 0.1));
    expect(performanceChart.width, closeTo(retentionChart.width, 0.1));

    expect(find.text('Study Analytics'), findsOneWidget);
    expect(find.text('Overall Mastery'), findsOneWidget);
    expect(find.text('Predictive Exam Readiness'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Screen 17 renders welcome overview at a phone viewport', (
    tester,
  ) async {
    await setPhoneViewport(tester);
    await tester.pumpWidget(app(const WelcomeBackPage()));
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text("Today's Briefing"), findsOneWidget);
    expect(find.text('Your Study Studio at a Glance'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
