import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Pocket TTS's text preparation (its `prepare_text_prompt`): one line,
/// a capital first letter, sentence-final punctuation, and leading spaces
/// for very short text (the model does badly with few tokens). Returns the
/// text and how many frames to keep after the end-of-speech signal.
(String, int) preparePocketText(String input) {
  var text = input.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return ('', 1);
  final afterEos = text.split(' ').length <= 4 ? 3 : 1;
  text = text[0].toUpperCase() + text.substring(1);

  const closers = '"\'”’)]»';
  var core = text;
  while (core.isNotEmpty && '$closers '.contains(core[core.length - 1])) {
    core = core.substring(0, core.length - 1);
  }
  if (core.isNotEmpty && !'.!?…'.contains(core[core.length - 1])) {
    const weak = ',;:-–—';
    if (weak.contains(core[core.length - 1])) {
      var trimmed = core;
      while (trimmed.isNotEmpty &&
          '$weak '.contains(trimmed[trimmed.length - 1])) {
        trimmed = trimmed.substring(0, trimmed.length - 1);
      }
      text = '$trimmed.${text.substring(core.length).trim()}';
    } else {
      text = '$text.';
    }
  }
  if (text.split(' ').length < 5) text = '${' ' * 8}$text';
  return (text, afterEos);
}

/// SentencePiece unigram tokenizer over the bundle's `vocab.json` and
/// `token_scores.json`: the best-scoring split into known pieces, with byte
/// pieces (`<0x41>`) for anything else.
class PocketTokenizer {
  PocketTokenizer(Map<String, dynamic> vocab, Map<String, dynamic> scores) {
    for (final entry in vocab.entries) {
      final bytes = utf8.encode(entry.key);
      final score = (scores[entry.key] as num).toDouble();
      _pieces[_key(bytes)] = (entry.value as int, score);
      _longest = math.max(_longest, bytes.length);
      final byte = RegExp(r'^<0x([0-9A-F]{2})>$').firstMatch(entry.key);
      if (byte != null) {
        _bytes[int.parse(byte[1]!, radix: 16)] = (entry.value as int, score);
      }
    }
  }

  factory PocketTokenizer.fromJson(String vocabJson, String scoresJson) =>
      PocketTokenizer(
        jsonDecode(vocabJson) as Map<String, dynamic>,
        jsonDecode(scoresJson) as Map<String, dynamic>,
      );

  final _pieces = <String, (int, double)>{};
  final _bytes = <int, (int, double)>{};
  var _longest = 1;

  /// Bytes as a map key (latin1 keeps one char per byte).
  static String _key(List<int> bytes) => latin1.decode(bytes);

  Int64List encode(String text) {
    // SentencePiece marks every word start, the first one included.
    final data = utf8.encode('▁${text.replaceAll(' ', '▁')}');
    final n = data.length;
    final best = List<double>.filled(n + 1, -1e30);
    final back = List<int>.filled(n + 1, -1);
    final ids = List<int>.filled(n + 1, -1);
    best[n] = 0;
    for (var start = n - 1; start >= 0; start--) {
      final last = math.min(n, start + _longest);
      for (var end = start + 1; end <= last; end++) {
        final hit = _pieces[_key(data.sublist(start, end))];
        if (hit != null && hit.$2 + best[end] > best[start]) {
          best[start] = hit.$2 + best[end];
          back[start] = end;
          ids[start] = hit.$1;
        }
      }
      if (back[start] < 0) {
        final byte = _bytes[data[start]];
        if (byte != null) {
          best[start] = byte.$2 + best[start + 1];
          ids[start] = byte.$1;
        }
        back[start] = start + 1;
      }
    }
    final out = <int>[];
    for (var at = 0; at < n; at = back[at]) {
      if (ids[at] >= 0) out.add(ids[at]);
    }
    return Int64List.fromList(out);
  }
}
