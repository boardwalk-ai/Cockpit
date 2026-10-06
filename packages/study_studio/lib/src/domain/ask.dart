/// An earlier Ask AI turn, sent back so follow-ups make sense.
class AskTurn {
  const AskTurn(this.question, this.answer);

  final String question;
  final String answer;

  Map<String, String> toJson() => {'q': question, 'a': answer};
}

/// Where part of an answer came from: a passage of one of the user's files.
class AskSource {
  const AskSource({required this.number, this.fileName, this.snippet = ''});

  /// The [n] the answer cites it by.
  final int number;
  final String? fileName;
  final String snippet;

  String get label =>
      fileName?.trim().isNotEmpty == true ? fileName!.trim() : 'Your notes';
}

/// What an Ask AI answer streams: its sources, then its text in pieces.
sealed class AskEvent {
  const AskEvent();
}

class AskSources extends AskEvent {
  const AskSources(this.sources);

  final List<AskSource> sources;
}

class AskText extends AskEvent {
  const AskText(this.text);

  final String text;
}
