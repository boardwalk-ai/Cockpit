import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_studio/src/application/study_voice.dart';
import 'package:study_studio/src/presentation/mobile/lightning_mobile.dart';

import 'home_page_test.dart' show phone, viewport;

/// A voice the test drives: what is "said" is set before the hold ends.
class FakeVoice implements StudyVoice {
  final spoken = <String>[];
  final warmed = <String>[];
  String next = '';
  Completer<String?>? _heard;
  ValueChanged<String>? _partial;
  var stops = 0;

  @override
  Future<String?> listen({required ValueChanged<String> onPartial}) {
    _partial = onPartial;
    return (_heard = Completer<String?>()).future;
  }

  void speak(String words) => _partial?.call(words);

  @override
  void finishListening() {
    final h = _heard;
    if (h != null && !h.isCompleted) h.complete(next);
  }

  @override
  Future<void> say(String text) async => spoken.add(text);

  @override
  void warm(String text) => warmed.add(text);

  @override
  void stop() => stops++;
}

const items = [
  RecallItem(
    topicId: 'dns',
    question: 'What does DNS turn names into?',
    answer: 'IP addresses',
    hint: 'What a computer dials',
    explanation: 'DNS resolves names to addresses.',
  ),
  RecallItem(
    topicId: 'osi',
    question: 'Which layer do routers work at?',
    answer: 'Network layer',
    explanation: 'Layer 3.',
  ),
];

void main() {
  late List<(String, bool)> answers;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> show(WidgetTester tester, {StudyVoice? voice}) async {
    viewport(tester, phone);
    answers = [];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: LightningMobile(
          items: items,
          voice: voice,
          topicTitles: const {'dns': 'DNS', 'osi': 'OSI model'},
          onClose: () {},
          onReview: (_) {},
          onAnswer: (i, right) {
            debugPrint('GRADE ${i.topicId} $right\n${StackTrace.current}');
            answers.add((i.topicId, right));
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  test('lenient matching', () {
    const q = RecallItem(
      topicId: 't',
      question: '',
      answer: 'The network layer',
    );
    expect(q.matches('network layer'), isTrue);
    expect(q.matches('Network layer.'), isTrue);
    expect(q.matches('the transport layer'), isFalse);
    const n = RecallItem(topicId: 't', question: '', answer: '443');
    expect(n.matches('443'), isTrue);
    expect(n.matches('80'), isFalse);
  });

  testWidgets('reads the question, then a held answer moves on by itself', (
    tester,
  ) async {
    final voice = FakeVoice();
    await show(tester, voice: voice);
    expect(voice.spoken, ['What does DNS turn names into?']);
    expect(voice.warmed, ['Which layer do routers work at?']);
    expect(find.text('7'), findsOne);

    final mic = find.byIcon(Icons.mic_rounded);
    final gesture = await tester.startGesture(tester.getCenter(mic));
    await tester.pump();
    voice.speak('IP addresses');
    await tester.pump();
    expect(find.text('IP addresses'), findsOne);
    voice.next = 'IP addresses';
    await gesture.up();
    await tester.pump();
    await tester.pump();
    expect(answers, [('dns', true)]);
    // Right: the next question comes on its own.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Which layer do routers work at?'), findsOne);
    expect(find.text('Question 2 of 2'), findsOne);
  });

  testWidgets('time runs out: the answer and why, then done', (tester) async {
    await show(tester); // no voice: typing only, nothing read
    expect(find.text('Type the answer'), findsOne);
    expect(find.text('Speak'), findsNothing);
    await tester.pump(const Duration(seconds: 8));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Time’s up'), findsOne);
    expect(find.text('DNS resolves names to addresses.'), findsOne);
    expect(answers, [('dns', false)]);

    await tester.tap(find.text('Next question'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byType(TextField), 'network layer');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(answers.last, ('osi', true));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Session done'), findsOne);
    expect(find.text('50%'), findsOne);
    expect(find.text('DNS'), findsOne); // a weak topic to review
  });

  testWidgets('mute and typing are kept', (tester) async {
    final voice = FakeVoice();
    await show(tester, voice: voice);
    await tester.tap(find.bySemanticsLabel('Mute'));
    await tester.tap(find.text('Type'));
    await tester.pump();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(LightningMobile.mutedKey), isTrue);
    expect(prefs.getBool(LightningMobile.typingKey), isTrue);
    expect(find.text('Type the answer'), findsOne);
    expect(find.text('Speak'), findsOne);
  });
}
