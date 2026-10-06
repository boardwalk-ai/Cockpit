import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/application/providers.dart';
import 'package:study_studio/src/data/mock/mock_data.dart';
import 'package:study_studio/src/domain/entities/quiz_question.dart';
import 'package:study_studio/src/domain/entities/studio.dart';
import 'package:study_studio/src/domain/entities/topic.dart';
import 'package:study_studio/src/presentation/lightning_recall/lightning_recall_page.dart';
import 'package:study_studio/src/presentation/mastery_report/mastery_report_page.dart';

void main() {
  // A rich studio (topics with varied mastery + a quiz bank) to drive the two
  // screens. Taken from the stashed mock so the test stays independent of the
  // offline repository, which dev empties for backend testing.
  final Studio bio = buildMockStudiosStashed().firstWhere((s) => s.id == 'bio');

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

  // Override studioProvider('bio') so both screens receive [bio] directly,
  // regardless of whether the offline repo or the API backend is configured.
  Widget app(Widget home) {
    return ProviderScope(
      overrides: [studioProvider('bio').overrideWith((ref) => bio)],
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

  group('Screen 8 — AI Mastery Report', () {
    testWidgets('renders live studio data at a phone viewport', (tester) async {
      await setPhoneViewport(tester);
      await tester.pumpWidget(app(const MasteryReportPage(studioId: 'bio')));
      await tester.pumpAndSettle();

      // A phone gets its own report: the ring and the path to 80%.
      expect(find.text('Mastery'), findsOneWidget);
      expect(find.text('YOUR PATH TO 80%'), findsOneWidget);
      // A path step is a real weak topic (DNA Replication, mastery 0.35)
      // from the studio, proving the report reads live data, not a mock.
      expect(find.text('DNA Replication'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lays out without overflow at a desktop viewport', (
      tester,
    ) async {
      await setDesktopViewport(tester);
      await tester.pumpWidget(app(const MasteryReportPage(studioId: 'bio')));
      await tester.pumpAndSettle();

      expect(find.text('AI Mastery Report'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Screen 9 — Lightning Recall', () {
    // The countdown uses a periodic Timer, so avoid pumpAndSettle and dispose
    // the tree at the end to cancel it (otherwise the test fails on a pending
    // timer).
    Future<void> pumpRecall(WidgetTester tester) async {
      await tester.pumpWidget(app(const LightningRecallPage(studioId: 'bio')));
      await tester.pump(); // resolve the overridden studioProvider
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('renders the recall session at a phone viewport', (
      tester,
    ) async {
      await setPhoneViewport(tester);
      await pumpRecall(tester);

      // The phone's session: the first question and its clock.
      expect(find.text('Lightning recall'), findsOneWidget);
      expect(find.textContaining('Question 1 of'), findsOneWidget);
      expect(find.text('Type the answer'), findsOneWidget); // no voice here
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox()); // dispose → cancel timer
    });

    testWidgets('lays out without overflow at a desktop viewport', (
      tester,
    ) async {
      await setDesktopViewport(tester);
      await pumpRecall(tester);

      expect(find.text('QUESTION'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox()); // dispose → cancel timer
    });

    testWidgets(
      'long weak-topic names do not overflow the session summary panel',
      (tester) async {
        // A weak topic with a very long name — the dense 3-column desktop
        // session-summary panel must ellipsize its chip, not overflow.
        const longTopic = Topic(
          id: 'isa',
          studioId: 'bio',
          title: 'Instruction Set Architecture and Execution Cycle Fundamentals',
          subject: 'Computer Science',
          definition: '',
          simpleExplanation: '',
          detailedExplanation: '',
          whyItMatters: '',
          mastery: 0.2, // weak
          quizQuestions: [
            QuizQuestion(
              id: 'isa_q',
              topicId: 'isa',
              type: QuizType.shortAnswer,
              question: 'What is the fetch-decode-execute cycle?',
              answer: 'the instruction cycle',
              explanation: 'It is the basic CPU operation cycle.',
            ),
          ],
        );
        final studio = bio.copyWith(topics: [...bio.topics, longTopic]);

        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1281, 720);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [studioProvider('bio').overrideWith((ref) => studio)],
            child: MaterialApp(
              theme: CockpitTheme.build(
                colors: CockpitColors.brand,
                fonts: CockpitFonts.brand,
                brightness: Brightness.light,
              ),
              home: const LightningRecallPage(studioId: 'bio'),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          find.textContaining('Instruction Set Architecture'),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox()); // dispose → cancel timer
      },
    );
  });
}
