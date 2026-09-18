/// Dictionary / thesaurus lookup results — mirror the web `DictResult` /
/// `ThesResult`. Populated by our backend later (frontend never calls the
/// dictionary/thesaurus APIs directly); mock data drives them for now.
class DictDefinition {
  const DictDefinition(this.definition, {this.example});
  final String definition;
  final String? example;

  factory DictDefinition.fromJson(Map<String, dynamic> j) => DictDefinition(
        (j['definition'] ?? '') as String,
        example: j['example'] as String?,
      );
}

class DictMeaning {
  const DictMeaning(this.partOfSpeech, this.definitions);
  final String partOfSpeech;
  final List<DictDefinition> definitions;

  factory DictMeaning.fromJson(Map<String, dynamic> j) => DictMeaning(
        (j['partOfSpeech'] ?? '') as String,
        ((j['definitions'] as List?) ?? const [])
            .map((d) => DictDefinition.fromJson(d as Map<String, dynamic>))
            .toList(),
      );
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

  factory DictResult.fromJson(Map<String, dynamic> j) => DictResult(
        word: (j['word'] ?? '') as String,
        phonetic: j['phonetic'] as String?,
        meanings: ((j['meanings'] as List?) ?? const [])
            .map((m) => DictMeaning.fromJson(m as Map<String, dynamic>))
            .toList(),
        synonyms: ((j['synonyms'] as List?) ?? const [])
            .map((s) => s.toString())
            .toList(),
        antonyms: ((j['antonyms'] as List?) ?? const [])
            .map((s) => s.toString())
            .toList(),
      );
}

class ThesWord {
  const ThesWord(this.word, this.score);
  final String word;
  final int score;

  factory ThesWord.fromJson(Map<String, dynamic> j) => ThesWord(
        (j['word'] ?? '') as String,
        (j['score'] as num?)?.toInt() ?? 0,
      );
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

  factory ThesResult.fromJson(Map<String, dynamic> j) => ThesResult(
        word: (j['word'] ?? '') as String,
        synonyms: ((j['synonyms'] as List?) ?? const [])
            .map((s) => ThesWord.fromJson(s as Map<String, dynamic>))
            .toList(),
        antonyms: ((j['antonyms'] as List?) ?? const [])
            .map((s) => ThesWord.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}
