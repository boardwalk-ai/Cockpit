import '../domain/lookup_result.dart';
import '../domain/source.dart';
import 'sources.dart';

/// The Tools panel's data source. **Seam:** every method here is backed by an
/// external API (dictionary, thesaurus, humanizer, scraper) that the frontend
/// reaches ONLY through our Rust backend. [MockToolsService] returns clearly
/// sample data until that backend exists; swap the provider for an HTTP client.
abstract interface class ToolsService {
  Future<DictResult> dictionary(String word);
  Future<ThesResult> thesaurus(String word);
  Future<String> paraphrase(String text);
  Future<List<Source>> searchSources(String query);

  /// True while results are placeholders (drives the "sample" banner).
  bool get isMock;
}

class MockToolsService implements ToolsService {
  const MockToolsService();

  @override
  bool get isMock => true;

  Future<T> _delay<T>(T value) =>
      Future.delayed(const Duration(milliseconds: 320), () => value);

  @override
  Future<DictResult> dictionary(String word) {
    final w = word.trim();
    return _delay(DictResult(
      word: w,
      phonetic: '/ˈsɑːmpəl/',
      meanings: [
        DictMeaning('noun', [
          DictDefinition('A representative example of "$w" used to illustrate '
              'the Tools panel.', example: 'The essay opened with a $w.'),
        ]),
        DictMeaning('verb', [
          const DictDefinition('To demonstrate or exemplify.'),
        ]),
      ],
      synonyms: const ['example', 'specimen', 'instance', 'illustration'],
      antonyms: const ['whole'],
    ));
  }

  @override
  Future<ThesResult> thesaurus(String word) {
    final w = word.trim();
    return _delay(ThesResult(
      word: w,
      synonyms: const [
        ThesWord('demonstrate', 92),
        ThesWord('illustrate', 88),
        ThesWord('exemplify', 81),
        ThesWord('represent', 74),
        ThesWord('typify', 69),
      ],
      antonyms: const [ThesWord('conceal', 40), ThesWord('hide', 36)],
    ));
  }

  @override
  Future<String> paraphrase(String text) =>
      _delay(text.trim().isEmpty ? '' : '$text\n\n(Sample rephrase — the '
          'humanizer runs on the backend.)');

  @override
  Future<List<Source>> searchSources(String query) => _delay(mockSources);
}
