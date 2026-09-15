/// Dictionary / thesaurus lookup results — mirror the web `DictResult` /
/// `ThesResult`. Populated by our backend later (frontend never calls the
/// dictionary/thesaurus APIs directly); mock data drives them for now.
class DictDefinition {
  const DictDefinition(this.definition, {this.example});
  final String definition;
  final String? example;
}

class DictMeaning {
  const DictMeaning(this.partOfSpeech, this.definitions);
  final String partOfSpeech;
  final List<DictDefinition> definitions;
}

class DictResult {
  const DictResult({
    required this.word,
    this.phonetic,
    this.meanings = const [],
    this.synonyms = const [],
    this.antonyms = const [],
  });
  final String word;
  final String? phonetic;
  final List<DictMeaning> meanings;
  final List<String> synonyms;
  final List<String> antonyms;
}

class ThesWord {
  const ThesWord(this.word, this.score);
  final String word;
  final int score;
}

class ThesResult {
  const ThesResult({
    required this.word,
    this.synonyms = const [],
    this.antonyms = const [],
  });
  final String word;
  final List<ThesWord> synonyms;
  final List<ThesWord> antonyms;
}
