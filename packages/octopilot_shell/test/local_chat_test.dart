import 'package:flutter_test/flutter_test.dart';
import 'package:octopilot_shell/octopilot_shell.dart';

void main() {
  test('each answer gets the conversation before it', () async {
    final seen = <List<String>>[];
    final chat = LocalMainChat(
      wordDelay: Duration.zero,
      answer: (text, history) async {
        seen.add([for (final m in history) '${m.role.name}: ${m.text}']);
        return 'reply to $text';
      },
    );
    final first = await chat.send(text: 'hello').toList();
    final id = (first.first as ChatThreadStarted).thread.id;
    await chat.send(threadId: id, text: 'and then?').toList();

    expect(seen, [
      <String>[],
      ['user: hello', 'assistant: reply to hello'],
    ]);
    expect((await chat.messages(id)).length, 4);
  });

  test('a failed answer says why, in words for the user', () async {
    final chat = LocalMainChat(
      answer: (_, _) async =>
          throw const ChatAnswerError("You've reached today's free chats."),
    );
    final events = await chat.send(text: 'hi').toList();
    expect(events.last, isA<ChatFailed>());
    expect(
      (events.last as ChatFailed).message,
      "You've reached today's free chats.",
    );

    final offline = LocalMainChat(
      answer: (_, _) async => throw StateError('x'),
    );
    final failed = (await offline.send(text: 'hi').toList()).last as ChatFailed;
    expect(failed.message, "Couldn't reach Octopilot. Try again.");
  });
}
