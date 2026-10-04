import 'dart:async';

import 'package:flutter/foundation.dart';

/// One conversation in the main chat's history.
@immutable
class ChatThread {
  const ChatThread({
    required this.id,
    required this.title,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final DateTime updatedAt;

  ChatThread copyWith({String? title, DateTime? updatedAt}) => ChatThread(
    id: id,
    title: title ?? this.title,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

enum ChatRole { user, assistant }

@immutable
class ChatMessage {
  const ChatMessage(this.role, this.text);

  final ChatRole role;
  final String text;
}

/// What a reply streams.
sealed class ChatEvent {
  const ChatEvent();
}

/// A new conversation was started by this message.
class ChatThreadStarted extends ChatEvent {
  const ChatThreadStarted(this.thread);
  final ChatThread thread;
}

/// More of the reply.
class ChatDelta extends ChatEvent {
  const ChatDelta(this.text);
  final String text;
}

/// The reply could not be given. [code] is the server's (`daily_limit`,
/// `rate_limited`, …) when there is one.
class ChatFailed extends ChatEvent {
  const ChatFailed(this.message, {this.code});
  final String message;
  final String? code;
}

/// The main chat: the conversations on the Home screen. Separate from every
/// module's own chats.
abstract class MainChat {
  /// The history, newest first.
  ValueListenable<List<ChatThread>> get threads;

  /// Reloads the history.
  Future<void> refresh();

  Future<List<ChatMessage>> messages(String threadId);

  /// Sends [text] in [threadId] (null starts a new conversation) and streams
  /// the reply. Cancelling the subscription stops the reply.
  Stream<ChatEvent> send({String? threadId, required String text});

  Future<void> rename(String threadId, String title);

  Future<void> delete(String threadId);
}

/// Answers [text], given the conversation before it (oldest first).
typedef ChatAnswerer =
    Future<String> Function(String text, List<ChatMessage> history);

/// A main chat whose history lives on the device. Each answer comes whole
/// from [answer] and is shown word by word.
class LocalMainChat implements MainChat {
  LocalMainChat({
    required this.answer,
    this.wordDelay = const Duration(milliseconds: 28),
  });

  final ChatAnswerer answer;

  /// Between shown words.
  final Duration wordDelay;

  final _threads = ValueNotifier<List<ChatThread>>(const []);
  final _messages = <String, List<ChatMessage>>{};
  var _next = 0;

  @override
  ValueListenable<List<ChatThread>> get threads => _threads;

  @override
  Future<void> refresh() async {}

  @override
  Future<List<ChatMessage>> messages(String threadId) async =>
      List.of(_messages[threadId] ?? const []);

  @override
  Stream<ChatEvent> send({String? threadId, required String text}) async* {
    var id = threadId;
    if (id == null) {
      id = 'chat-${_next++}';
      final thread = ChatThread(
        id: id,
        title: _title(text),
        updatedAt: DateTime.now(),
      );
      _messages[id] = [];
      _threads.value = [thread, ..._threads.value];
      yield ChatThreadStarted(thread);
    }
    final log = _messages[id]!;
    final history = List.of(log);
    log.add(ChatMessage(ChatRole.user, text));
    _touch(id);

    final String answer;
    try {
      answer = await this.answer(text, history);
    } on Object catch (error) {
      yield ChatFailed(_failure(error));
      return;
    }
    final said = StringBuffer();
    try {
      for (final word in answer.split(' ')) {
        await Future<void>.delayed(wordDelay);
        final piece = said.isEmpty ? word : ' $word';
        said.write(piece);
        yield ChatDelta(piece);
      }
    } finally {
      // Stopped or finished, what was said stays.
      log.add(ChatMessage(ChatRole.assistant, said.toString()));
    }
  }

  @override
  Future<void> rename(String threadId, String title) async {
    _threads.value = [
      for (final t in _threads.value)
        t.id == threadId ? t.copyWith(title: title) : t,
    ];
  }

  @override
  Future<void> delete(String threadId) async {
    _messages.remove(threadId);
    _threads.value = [
      for (final t in _threads.value)
        if (t.id != threadId) t,
    ];
  }

  void _touch(String id) {
    final list = List.of(_threads.value);
    final at = list.indexWhere((t) => t.id == id);
    if (at < 0) return;
    final thread = list.removeAt(at).copyWith(updatedAt: DateTime.now());
    _threads.value = [thread, ...list];
  }

  static String _title(String text) {
    final line = text.trim().split('\n').first;
    return line.length <= 40 ? line : '${line.substring(0, 40).trimRight()}…';
  }

  /// What to tell the user when an answer fails: a message the answerer
  /// gave as a [ChatAnswerError], else a general one.
  static String _failure(Object error) => error is ChatAnswerError
      ? error.message
      : "Couldn't reach Octopilot. Try again.";
}

/// A failure with words fit for the user (a limit reached, and so on).
class ChatAnswerError implements Exception {
  const ChatAnswerError(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// A main chat with canned answers, for tests and offline demos.
class DemoMainChat extends LocalMainChat {
  DemoMainChat({super.wordDelay})
    : super(answer: (text, _) async => _canned(text));

  static String _canned(String text) {
    final q = text.toLowerCase();
    if (q.contains('essay') || q.contains('write')) {
      return 'For essays, open Create and pick GhostWriter. Tell it your '
          'topic and it asks a few questions, finds sources and writes the '
          'draft for you.';
    }
    if (q.contains('study') || q.contains('learn') || q.contains('exam')) {
      return 'Study Studio is coming to Learn soon. It will turn your notes '
          'into flashcards and practice questions.';
    }
    if (q.contains('note')) {
      return 'OctoNotes is coming to Organize soon, for your notes and plans.';
    }
    if (q.contains('credit')) {
      return 'OctoCredits pay for the work modules do, like writing an essay. '
          'Chatting here is free. Your balance is in Settings.';
    }
    return "I'm Octopilot's assistant. I can help you find your way around "
        'the app: Create for writing, Learn for studying and Organize for '
        'notes. What would you like to do?';
  }
}
