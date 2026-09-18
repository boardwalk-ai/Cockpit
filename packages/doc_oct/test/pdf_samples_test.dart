// Generates a full sample essay as a PDF in all five citation styles, so the
// export layout can be verified visually. Run with:
//
//   flutter test test/pdf_samples_test.dart
//
// PDFs are written to build/pdf_samples/<style>.pdf.
import 'dart:io';
import 'dart:typed_data';

import 'package:doc_oct/src/application/pdf_export.dart';
import 'package:doc_oct/src/domain/citation_templates.dart';
import 'package:doc_oct/src/domain/source.dart';
import 'package:doc_oct/src/theme/doc_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

// ── The shared sample essay ──────────────────────────────────────────────────
const _title = 'Artificial Intelligence in Modern Education';
const _student = 'Ada Lovelace';
const _institution = 'University of Cambridge';
const _course = 'EDU 401: Educational Technology';
const _instructor = 'Dr. Alan Turing';
const _date = 'September 18, 2026';
const _dateDMY = '18 September 2026';

const _abstract =
    'This paper examines the growing role of artificial intelligence (AI) in '
    'contemporary education. It reviews how adaptive learning platforms, '
    'automated assessment, and intelligent tutoring systems reshape the way '
    'students learn and teachers teach. Drawing on recent studies, the paper '
    'argues that AI can personalise instruction and widen access, yet it also '
    'raises concerns about data privacy, equity, and the erosion of critical '
    'thinking. The analysis concludes that AI is best treated as an assistant '
    'to human educators rather than a replacement, and that thoughtful policy '
    'and teacher training are essential to realising its benefits responsibly.';

const _keywords =
    'artificial intelligence, education, adaptive learning, assessment, equity';

const _body = <String>[
  'Artificial intelligence has moved from research laboratories into everyday '
      'classrooms with remarkable speed. Where educational technology once meant '
      'little more than a projector or a shared document, schools and '
      'universities now deploy systems that adapt to each learner in real time. '
      'This shift raises an urgent question for educators: how can these tools be '
      'used to genuinely improve learning without sacrificing the human '
      'relationships at the heart of good teaching?',
  'The clearest benefit of AI in education is personalisation. Adaptive learning '
      'platforms track how a student answers each question and adjust the '
      'difficulty and sequence of material accordingly. A learner who masters a '
      'concept quickly is moved ahead, while one who struggles receives '
      'additional practice and worked examples. For large classes in which a '
      'single teacher cannot attend to every individual, this kind of tailored '
      'pacing offers a practical form of one-to-one support that was previously '
      'impossible to provide at scale.',
  'Automated assessment is a second area of rapid growth. Machine-learning models '
      'can now grade short answers, give feedback on essay structure, and flag '
      'misconceptions for the teacher to review. When used well, this frees '
      'educators from routine marking and lets them spend more time on '
      'discussion, mentoring, and designing richer tasks. The technology is far '
      'from perfect, however, and over-reliance on automated scoring can reward '
      'formulaic writing and penalise original thinking that a model has not '
      'been trained to recognise.',
  'Alongside these opportunities sit real risks. Adaptive systems depend on '
      'collecting detailed records of student behaviour, which raises serious '
      'questions about privacy and consent, especially for minors. There is also '
      'a danger of widening inequality: well-funded schools can afford the best '
      'platforms and the training to use them, while under-resourced schools may '
      'be left further behind. Finally, if students come to depend on AI to '
      'summarise, draft, and solve, they may lose the very skills — patience, '
      'judgement, and critical reasoning — that education exists to cultivate.',
  'The most sensible path forward treats AI as an assistant rather than an '
      'authority. Teachers remain best placed to know their students, to judge '
      'context, and to model the curiosity that machines cannot feel. Policy '
      'makers should insist on transparency about how these systems work and how '
      'student data is used, and teacher-training programmes should prepare '
      'educators to question as well as to operate them. Used in this spirit, AI '
      'becomes a powerful support for human judgement instead of a substitute '
      'for it.',
  'In conclusion, artificial intelligence offers education both a genuine '
      'opportunity and a genuine test. Its capacity to personalise learning and '
      'lighten routine work is real, but so are the threats it poses to privacy, '
      'equity, and independent thought. The task for educators is not to accept '
      'or reject the technology wholesale, but to shape its use so that it '
      'amplifies rather than replaces the human work of teaching.',
];

const _sources = <Source>[
  Source(
    url: 'https://www.oecd.org/education/ai-and-the-future-of-skills.htm',
    title: 'Artificial Intelligence and the Future of Skills',
    author: 'OECD',
    publishedYear: '2021',
    publisher: 'OECD Publishing',
    fullContent: '',
  ),
  Source(
    url: 'https://link.springer.com/article/10.1007/s40593-021-00239-1',
    title: 'Intelligent Tutoring Systems and Learning Outcomes',
    author: 'Kulik, James A.; Fletcher, J. D.',
    publishedYear: '2016',
    publisher: 'International Journal of Artificial Intelligence in Education',
    fullContent: '',
  ),
  Source(
    url: 'https://unesdoc.unesco.org/ark:/48223/pf0000376709',
    title: 'AI and Education: Guidance for Policy-Makers',
    author: 'Miao, Fengchun; Holmes, Wayne',
    publishedYear: '2021',
    publisher: 'UNESCO',
    fullContent: '',
  ),
  Source(
    url: 'https://www.brookings.edu/articles/how-artificial-intelligence-is-transforming-the-classroom',
    title: 'How Artificial Intelligence Is Transforming the Classroom',
    author: 'Bryant, Jake',
    publishedYear: '2020',
    publisher: 'Brookings Institution',
    fullContent: '',
  ),
  Source(
    url: 'https://dl.acm.org/doi/10.1145/3313831.3376789',
    title: 'Equity and Data Privacy in Adaptive Learning',
    author: 'Zhang, Wei; Nguyen, Linh',
    publishedYear: '2019',
    publisher: 'ACM Conference on Human Factors in Computing Systems',
    fullContent: '',
  ),
];

ByteData _load(String name) {
  final bytes = File('fonts/$name').readAsBytesSync();
  return ByteData.sublistView(Uint8List.fromList(bytes));
}

FormatStyle _flutterStyle(PdfStyle s) => switch (s) {
      PdfStyle.apa => FormatStyle.apa,
      PdfStyle.mla => FormatStyle.mla,
      PdfStyle.chicago => FormatStyle.chicago,
      PdfStyle.ieee => FormatStyle.ieee,
      PdfStyle.harvard => FormatStyle.harvard,
    };

EssayInput _inputFor(PdfStyle style) {
  final fs = _flutterStyle(style);
  final refs = [
    for (var i = 0; i < _sources.length; i++)
      CitationTemplates.reference(fs, _sources[i], i + 1),
  ];
  return EssayInput(
    title: _title,
    studentName: _student,
    institution: _institution,
    course: _course,
    instructor: _instructor,
    date: _date,
    dateDayMonthYear: _dateDMY,
    abstractText: _abstract,
    keywords: _keywords,
    body: _body,
    references: refs,
  );
}

void main() {
  test('generates sample PDFs for all five styles', () async {
    final fonts = DocFonts.fromBytes(
      regular: _load('Tinos-Regular.ttf'),
      bold: _load('Tinos-Bold.ttf'),
      italic: _load('Tinos-Italic.ttf'),
      boldItalic: _load('Tinos-BoldItalic.ttf'),
    );

    final outDir = Directory('build/pdf_samples')..createSync(recursive: true);
    for (final style in PdfStyle.values) {
      final bytes = await buildEssayPdf(
          input: _inputFor(style), style: style, fonts: fonts);
      final file = File('${outDir.path}/${style.name}.pdf')
        ..writeAsBytesSync(bytes);
      expect(file.existsSync(), isTrue);
      expect(bytes.length, greaterThan(1000));
      // ignore: avoid_print
      print('wrote ${file.path} (${bytes.length} bytes)');
    }
  });
}
