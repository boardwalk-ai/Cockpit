import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The host app's microphone and speaker, for answering out loud and
/// hearing questions read (Lightning recall). Octopilot hands in its own
/// voice engine; without one (the web, tests) the pages fall back to typing.
abstract interface class StudyVoice {
  /// Listens while the user holds the button; returns what they said, or
  /// null for nothing. [finishListening] ends it.
  Future<String?> listen({required ValueChanged<String> onPartial});

  /// Takes what has been heard so far as the answer.
  void finishListening();

  /// Reads [text] aloud; completes when it is done (or [stop]ped).
  Future<void> say(String text);

  /// Starts making [text]'s speech ahead of [say] (the next question).
  void warm(String text);

  /// Stops listening or speaking at once.
  void stop();
}

/// None unless the host app overrides it.
final studyVoiceProvider = Provider<StudyVoice?>(
  (ref) => null,
  dependencies: const [],
);
