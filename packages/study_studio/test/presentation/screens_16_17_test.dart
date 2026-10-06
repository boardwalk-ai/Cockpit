import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/presentation/analytics/study_analytics_page.dart';
import 'package:study_studio/src/presentation/mastery_report/mastery_report_phone.dart';
import 'package:study_studio/src/presentation/welcome/welcome_back_page.dart';

void main() {
  Future<void> setPhoneViewport(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }

  Future<void> setDesktopViewport(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1281, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }

  Widget app(Widget home) {
    return ProviderScope(
      child: MaterialApp(
        theme: CockpitTheme.build(
          colors: CockpitColors.brand,
          fonts: CockpitFonts.brand,
          brightness: Brightness.light,
        ),
        home: home,
      ),
    );
  }

  testWidgets('Screen 16 on a phone is the mastery report', (tester) async {
    await setPhoneViewport(tester);
    await tester.pumpWidget(app(const StudyAnalyticsPage(studioId: 'bio')));
    // The week and what's fading moved into the report.
    expect(find.byType(MasteryReportPhone), findsOneWidget);
    expect(find.text('Study Analytics'), findsNothing);
  });

  testWidgets('Screen 16 lays out as two columns on desktop without overflow', (
    tester,
  ) async {
    await setDesktopViewport(tester);
    await tester.pumpWidget(app(const StudyAnalyticsPage(studioId: 'bio')));
    await tester.pumpAndSettle();

    expect(find.text('Study Analytics'), findsOneWidget);
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

  testWidgets('Screen 17 renders every card on desktop', (tester) async {
    await setDesktopViewport(tester);
    await tester.pumpWidget(app(const WelcomeBackPage()));
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text("Today's Briefing"), findsOneWidget);
    expect(find.text("Here's today's plan"), findsOneWidget);
    expect(find.text('Your Study Studio at a Glance'), findsOneWidget);
    expect(find.text('Learning Milestones'), findsOneWidget);
    expect(find.text('AI has noticed...'), findsOneWidget);
    expect(find.text('Knowledge Evolution'), findsOneWidget);
    expect(find.text("What's New"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
