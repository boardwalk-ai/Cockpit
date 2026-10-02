import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwriter/src/mobile/mobile_chat.dart';

void main() {
  late TextEditingController composer;
  late List<String> events;

  setUp(() {
    composer = TextEditingController();
    events = [];
  });

  Widget chat({
    bool finished = false,
    List<String> messages = const ['An essay on tides'],
    String assistantText = '',
    String essay = '',
    String bibliography = '',
    List<Map<String, dynamic>> sources = const [],
    String? pendingQuestion,
    String? errorMessage,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: GhostWriterMobileChat(
          finished: finished,
          title: 'An essay on tides',
          citationStyle: 'APA',
          wordCount: 500,
          messages: messages,
          assistantText: assistantText,
          essay: essay,
          bibliography: bibliography,
          sources: sources,
          pendingQuestion: pendingQuestion,
          errorMessage: errorMessage,
          onRetry: () => events.add('retry'),
          composerController: composer,
          onSend: () => events.add('send'),
        ),
      ),
    );
  }

  Future<void> show(WidgetTester tester, Widget widget) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(widget);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  }

  testWidgets('shows the typing indicator before the first words', (
    tester,
  ) async {
    await show(tester, chat());

    expect(find.text('An essay on tides'), findsNWidgets(2)); // strip + bubble
    expect(find.text('Writing'), findsOneWidget);
    expect(find.bySemanticsLabel('GhostWriter is writing'), findsOneWidget);
  });

  testWidgets('shows streamed text in place of the typing indicator', (
    tester,
  ) async {
    await show(tester, chat(assistantText: 'Tides rise and fall'));

    expect(find.textContaining('Tides rise and fall'), findsOneWidget);
    expect(find.bySemanticsLabel('GhostWriter is writing'), findsNothing);
  });

  testWidgets('shows a pending question and uses it as the hint', (
    tester,
  ) async {
    await show(tester, chat(pendingQuestion: 'Which citation style?'));

    expect(find.text('GhostWriter needs your input'), findsOneWidget);
    expect(find.text('Which citation style?'), findsNWidgets(2));
  });

  testWidgets('error card retries', (tester) async {
    await show(tester, chat(errorMessage: 'Stream disconnected'));

    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(milliseconds: 600));

    expect(events, ['retry']);
  });

  testWidgets('Send is disabled until something is typed', (tester) async {
    await show(tester, chat());

    await tester.tap(find.byTooltip('Send'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(events, isEmpty);

    await tester.enterText(find.byType(TextField), 'Make it shorter');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byTooltip('Send'));
    await tester.pump(const Duration(milliseconds: 600));

    expect(events, ['send']);
  });

  testWidgets('finished run shows the essay and references, and copies', (
    tester,
  ) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );

    await show(
      tester,
      chat(
        finished: true,
        essay: 'The tide is the sea breathing.',
        bibliography: 'Sweet, W. (2022). Sea level rise.',
      ),
    );

    expect(find.text('Finished'), findsOneWidget);
    expect(find.text('The tide is the sea breathing.'), findsOneWidget);
    expect(find.text('Sweet, W. (2022). Sea level rise.'), findsOneWidget);

    await tester.tap(find.byTooltip('Copy final essay'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(clipboard, 'The tide is the sea breathing.');
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    // The tick goes back to the copy icon on its own.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.check_rounded), findsNothing);
  });

  testWidgets('Details opens the sheet with sources', (tester) async {
    await show(
      tester,
      chat(
        finished: true,
        essay: 'Essay.',
        sources: const [
          {
            'title': 'Sea Level Rise Scenarios',
            'author': 'Sweet, W.',
            'publisher': 'NOAA',
            'url': 'https://example.org/slr',
          },
        ],
      ),
    );

    await tester.tap(find.byTooltip('Details'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Essay details'), findsOneWidget);
    expect(find.text('Sea Level Rise Scenarios'), findsOneWidget);
    expect(find.text('Sweet, W. · NOAA'), findsOneWidget);
    expect(find.text('https://example.org/slr'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
