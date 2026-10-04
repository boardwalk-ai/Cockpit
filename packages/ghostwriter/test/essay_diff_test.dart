import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwriter/src/review/essay_diff.dart';

void main() {
  test('unchanged text has no changes', () {
    final diff = diffEssay('One.\n\nTwo.', 'One.\n\nTwo.');
    expect(diff.changed, isFalse);
    expect(diff.paragraphs, hasLength(2));
  });

  test('a changed paragraph is compared word by word', () {
    final diff = diffEssay(
      'Seas are rising fast.\n\nCities must plan.',
      'Seas are rising quickly.\n\nCities must plan.',
    );
    expect(diff.paragraphs.first.spans, const [
      DiffSpan(DiffOp.same, 'Seas are rising '),
      DiffSpan(DiffOp.removed, 'fast. '),
      DiffSpan(DiffOp.added, 'quickly.'),
    ]);
    expect(diff.paragraphs.last.changed, isFalse);
    expect((diff.wordsAdded, diff.wordsRemoved), (1, 1));
    expect(diff.changedParagraphs, 1);
  });

  test('paragraphs added and removed whole', () {
    final diff = diffEssay(
      'Intro.\n\nOld middle.\n\nEnd.',
      'Intro.\n\nEnd.\n\nA new closing line.',
    );
    final ops = [
      for (final p in diff.paragraphs) [for (final s in p.spans) s.op],
    ];
    expect(ops, [
      [DiffOp.same],
      [DiffOp.removed],
      [DiffOp.same],
      [DiffOp.added],
    ]);
    expect(diff.wordsAdded, 4);
    expect(diff.wordsRemoved, 2);
  });

  test('a line break inside a paragraph is not a change', () {
    final diff = diffEssay('Seas are\nrising.', 'Seas are rising.');
    expect(diff.changed, isFalse);
  });
}
