import 'package:doc_oct/doc_oct.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MLA dates are written day first', () {
    expect(DocPdf.dayMonthYear('March 4, 2026'), '4 March 2026');
    expect(DocPdf.dayMonthYear('Sept. 12 2025'), '12 Sept 2025');
    expect(DocPdf.dayMonthYear('4 March 2026'), '4 March 2026');
    expect(DocPdf.dayMonthYear(''), '');
  });

  test('given references are used as they are', () {
    final input = DocPdf.inputFrom(
      style: FormatStyle.apa,
      title: 'Tides',
      studentName: 'Ada',
      institution: '',
      course: '',
      instructor: '',
      date: 'March 4, 2026',
      abstractText: '',
      keywords: '',
      bodyText: 'One.\n\nTwo.',
      sources: const [],
      references: ['Smith, J. (2020). Tides. Ocean Press.'],
    );
    expect(input.body, ['One.', 'Two.']);
    expect(input.references, ['Smith, J. (2020). Tides. Ocean Press.']);
  });
}
