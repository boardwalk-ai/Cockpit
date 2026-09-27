import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/data/ai/ai_service.dart';
import 'package:study_studio/src/data/mock/mock_data.dart';
import 'package:study_studio/src/domain/entities/topic.dart';
import 'package:study_studio/src/presentation/teach_me/teach_me_page.dart';

import '../helpers/test_app.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('Outfit')
      ..addFont(
        File('../../apps/cockpit/assets/fonts/Outfit-VariableFont_wght.ttf')
            .readAsBytes()
            .then((bytes) => ByteData.sublistView(bytes)),
      );
    await loader.load();
  });
  for (final width in [320.0, 390.0]) {
    testWidgets('mobile lesson and AI flow at $width', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      final studio = buildMockStudiosStashed().first;
      final topic = studio.topics.first;
      final ai = _TestAi();
      await pumpTestApp(
        tester,
        child: TeachMePage(studioId: studio.id, topicId: topic.id),
        studios: [studio],
        aiService: ai,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('teach-mobile')), findsOneWidget);
      await tester.tap(find.text('Start Lesson'));
      await tester.pumpAndSettle();
      expect(find.text(topic.definition), findsOneWidget);
      for (final example in topic.examples) {
        expect(find.text(example), findsOneWidget);
      }
      if (topic.sources.isNotEmpty) {
        expect(
          find.textContaining(topic.sources.first.snippet),
          findsOneWidget,
        );
      }
      await tester.ensureVisible(find.text('Ask Anything'));
      await tester.tap(find.text('Ask Anything'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Explain this lesson');
      await tester.ensureVisible(find.text('Send'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Send')).bottom, lessThan(544));
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(ai.message, 'Explain this lesson');
      expect(ai.topicId, topic.id);
      expect(find.text('Test lesson reply'), findsOneWidget);
      await tester.ensureVisible(find.text('Give another example'));
      await tester.tap(find.text('Give another example'));
      await tester.pumpAndSettle();
      expect(ai.message, 'Give another example');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('shows loading indicator', (tester) async {
    await pumpTestApp(
      tester,
      child: const TeachMePage(studioId: 'bio', topicId: 'cell'),
      delay: Duration.zero,
    );

    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows error state', (tester) async {
    await pumpTestApp(
      tester,
      child: const TeachMePage(studioId: 'bio', topicId: 'cell'),
      error: Exception('Test error'),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('Error:'), findsOneWidget);
  });

  testWidgets('shows topic not found', (tester) async {
    final studio = buildMockStudiosStashed().first;

    await pumpTestApp(
      tester,
      child: TeachMePage(studioId: studio.id, topicId: 'does-not-exist'),
      studios: [studio],
    );

    await tester.pumpAndSettle();

    expect(find.text('Topic not found'), findsOneWidget);
  });

  testWidgets('shows lesson data', (tester) async {
    final studio = buildMockStudiosStashed().first;
    final topic = studio.topics.first;

    await pumpTestApp(
      tester,
      child: TeachMePage(studioId: studio.id, topicId: topic.id),
      studios: [studio],
    );

    await tester.pumpAndSettle();

    expect(find.text(topic.title), findsWidgets);
    expect(find.text('Teach Me'), findsWidgets);
    expect(find.text('Current Topic'), findsOneWidget);
    expect(find.text('Start Lesson'), findsOneWidget);
    expect(find.text('Ask Anything'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}

class _TestAi implements AiService {
  String? message;
  String? topicId;
  @override
  Future<String> teach({required Topic topic, required String message}) async {
    this.message = message;
    topicId = topic.id;
    return 'Test lesson reply';
  }
}
