import 'package:doc_oct/doc_oct.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const smith = Source(
    url: 'https://example.com/x',
    title: 'A Study of Things',
    author: 'Smith, John',
    publishedYear: '2020',
    publisher: 'Academic Press',
  );
  const noYear = Source(
    url: '',
    title: 'Untitled',
    author: 'Doe, Jane',
  );

  test('in-text marks per style', () {
    expect(CitationTemplates.inText(FormatStyle.mla, smith, 1), '(Smith)');
    expect(CitationTemplates.inText(FormatStyle.apa, smith, 1), '(Smith, 2020)');
    expect(CitationTemplates.inText(FormatStyle.chicago, smith, 1), '(Smith 2020)');
    expect(CitationTemplates.inText(FormatStyle.harvard, smith, 1), '(Smith, 2020)');
    expect(CitationTemplates.inText(FormatStyle.ieee, smith, 3), '[3]');
  });

  test('missing year → n.d.', () {
    expect(CitationTemplates.inText(FormatStyle.apa, noYear, 1), '(Doe, n.d.)');
  });

  test('reference entries carry style-specific shape', () {
    expect(CitationTemplates.reference(FormatStyle.apa, smith, 1),
        contains('Smith. (2020). A Study of Things. Academic Press.'));
    expect(CitationTemplates.reference(FormatStyle.mla, smith, 1),
        startsWith('Smith, John. "A Study of Things." Academic Press, 2020.'));
    expect(CitationTemplates.reference(FormatStyle.ieee, smith, 2),
        startsWith('[2] Smith, John, "A Study of Things," Academic Press, 2020.'));
  });

  test('date conventions', () {
    expect(DocDates.monthDayYear('12 June 2026'), 'June 12, 2026');
    expect(DocDates.dayMonthYear('June 12, 2026'), '12 June 2026');
    expect(DocDates.monthDayYear('not a date'), 'not a date');
  });
}
