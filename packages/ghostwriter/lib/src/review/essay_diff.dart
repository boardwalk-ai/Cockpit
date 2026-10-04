/// What changed between two versions of an essay, for review: paragraphs
/// are lined up first (unchanged ones match whole), then a changed pair is
/// compared word by word.
library;

enum DiffOp { same, added, removed }

class DiffSpan {
  const DiffSpan(this.op, this.text);

  final DiffOp op;

  /// Words with the spaces between them.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is DiffSpan && other.op == op && other.text == text;

  @override
  int get hashCode => Object.hash(op, text);

  @override
  String toString() => '${op.name}(${text.replaceAll('\n', r'\n')})';
}

class DiffParagraph {
  const DiffParagraph(this.spans);

  final List<DiffSpan> spans;

  bool get changed => spans.any((s) => s.op != DiffOp.same);
}

class EssayDiff {
  const EssayDiff(this.paragraphs);

  final List<DiffParagraph> paragraphs;

  int get wordsAdded => _count(DiffOp.added);
  int get wordsRemoved => _count(DiffOp.removed);
  int get changedParagraphs => paragraphs.where((p) => p.changed).length;
  bool get changed => paragraphs.any((p) => p.changed);

  int _count(DiffOp op) => paragraphs
      .expand((p) => p.spans)
      .where((s) => s.op == op)
      .fold(0, (n, s) => n + _words(s.text));
}

int _words(String text) =>
    text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;

List<String> _paragraphs(String text) => text
    .replaceAll('\r\n', '\n')
    .split(RegExp(r'\n\s*\n'))
    .map((p) => p.trim())
    .where((p) => p.isNotEmpty)
    .toList();

/// The longest common subsequence of [a] and [b], as pairs of indexes.
List<(int, int)> _lcs<T>(List<T> a, List<T> b) {
  final n = a.length, m = b.length;
  // lengths[i][j]: the LCS of a[i..] and b[j..].
  final lengths = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lengths[i][j] = a[i] == b[j]
          ? lengths[i + 1][j + 1] + 1
          : (lengths[i + 1][j] >= lengths[i][j + 1]
                ? lengths[i + 1][j]
                : lengths[i][j + 1]);
    }
  }
  final pairs = <(int, int)>[];
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      pairs.add((i, j));
      i++;
      j++;
    } else if (lengths[i + 1][j] >= lengths[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return pairs;
}

/// Words and the whitespace after each, so joining gives the text back.
List<String> _tokens(String text) =>
    RegExp(r'\S+\s*').allMatches(text).map((m) => m.group(0)!).toList();

/// One paragraph against another, word by word.
DiffParagraph diffWords(String before, String after) {
  final a = _tokens(before), b = _tokens(after);
  // Compare words without their trailing space, so a moved line end is not
  // a change.
  final pairs = _lcs(
    [for (final t in a) t.trimRight()],
    [for (final t in b) t.trimRight()],
  );
  final spans = <DiffSpan>[];
  void add(DiffOp op, String text) {
    if (text.isEmpty) return;
    if (spans.isNotEmpty && spans.last.op == op) {
      spans[spans.length - 1] = DiffSpan(op, spans.last.text + text);
    } else {
      spans.add(DiffSpan(op, text));
    }
  }

  var i = 0, j = 0;
  for (final (pi, pj) in [...pairs, (a.length, b.length)]) {
    while (i < pi) {
      add(DiffOp.removed, _spaced(a[i++]));
    }
    while (j < pj) {
      add(DiffOp.added, _spaced(b[j++]));
    }
    if (pi < a.length) {
      add(DiffOp.same, _spaced(b[pj]));
      i++;
      j++;
    }
  }
  // No trailing space at the paragraph's end.
  if (spans.isNotEmpty) {
    final last = spans.last;
    spans[spans.length - 1] = DiffSpan(last.op, last.text.trimRight());
  }
  return DiffParagraph(spans);
}

String _spaced(String token) => '${token.trimRight()} ';

/// [before] against [after], paragraph by paragraph.
EssayDiff diffEssay(String before, String after) {
  final a = _paragraphs(before), b = _paragraphs(after);
  final out = <DiffParagraph>[];
  var i = 0, j = 0;
  for (final (pi, pj) in [..._lcs(a, b), (a.length, b.length)]) {
    // Between two matches: pair the changed paragraphs up in order and
    // compare their words; any left over were removed or added whole.
    final removed = a.sublist(i, pi), added = b.sublist(j, pj);
    final paired = removed.length < added.length
        ? removed.length
        : added.length;
    for (var k = 0; k < paired; k++) {
      out.add(diffWords(removed[k], added[k]));
    }
    for (final p in removed.skip(paired)) {
      out.add(DiffParagraph([DiffSpan(DiffOp.removed, p)]));
    }
    for (final p in added.skip(paired)) {
      out.add(DiffParagraph([DiffSpan(DiffOp.added, p)]));
    }
    if (pi < a.length) out.add(DiffParagraph([DiffSpan(DiffOp.same, a[pi])]));
    i = pi + 1;
    j = pj + 1;
  }
  return EssayDiff(out);
}
