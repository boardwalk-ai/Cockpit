import 'dart:async';

import 'package:flutter/foundation.dart';

import 'main_chat.dart';

/// The conversation open on the Home screen.
class ChatController extends ChangeNotifier {
  ChatController(this.chat);

  final MainChat chat;

  /// Null = a new conversation (Home shows the mode cards).
  String? threadId;
  List<ChatMessage> messages = const [];

  /// The reply being streamed, if any.
  String? streaming;

  /// Why the last reply failed.
  ChatFailed? failure;

  bool loading = false;
  StreamSubscription<ChatEvent>? _reply;
  var _disposed = false;

  bool get replying => _reply != null;
  bool get isEmpty => messages.isEmpty && streaming == null;

  void newChat() {
    _cancel();
    threadId = null;
    messages = const [];
    failure = null;
    _notify();
  }

  Future<void> open(String id) async {
    _cancel();
    threadId = id;
    messages = const [];
    failure = null;
    loading = true;
    _notify();
    final loaded = await chat.messages(id);
    if (threadId != id) return;
    messages = loaded;
    loading = false;
    _notify();
  }

  void send(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || replying) return;
    failure = null;
    messages = [...messages, ChatMessage(ChatRole.user, trimmed)];
    streaming = '';
    final sentFrom = threadId;
    _reply = chat
        .send(threadId: sentFrom, text: trimmed)
        .listen(
          (event) {
            switch (event) {
              case ChatThreadStarted(:final thread):
                threadId = thread.id;
              case ChatDelta(:final text):
                streaming = '${streaming ?? ''}$text';
              case ChatFailed():
                failure = event;
            }
            _notify();
          },
          onError: (Object error) {
            failure = const ChatFailed("Couldn't reach Octopilot. Try again.");
            _finish();
          },
          onDone: _finish,
        );
    _notify();
  }

  /// Stops the reply; what was said so far stays.
  void stop() => _finish(cancel: true);

  void _finish({bool cancel = false}) {
    final reply = _reply;
    if (reply == null) return;
    _reply = null;
    if (cancel) reply.cancel();
    final said = streaming;
    streaming = null;
    if (said != null && said.isNotEmpty) {
      messages = [...messages, ChatMessage(ChatRole.assistant, said)];
    }
    _notify();
  }

  void _cancel() {
    _reply?.cancel();
    _reply = null;
    streaming = null;
    loading = false;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel();
    super.dispose();
  }
}
