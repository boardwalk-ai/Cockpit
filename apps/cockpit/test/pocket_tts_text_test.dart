import 'dart:io';

import 'package:cockpit/voice/pocket_tts_text.dart';
import 'package:flutter_test/flutter_test.dart';

/// Token IDs from the bundle's own SentencePiece model (tokenizer.model).
const cases = [
  (
    "Hi, I'm Octopilot.",
    "        Hi, I'm Octopilot.",
    3,
    [
      260,
      260,
      260,
      260,
      260,
      260,
      260,
      260,
      1445,
      262,
      268,
      264,
      283,
      705,
      440,
      274,
      561,
      457,
      1025,
      263,
    ],
  ),
  (
    'sure',
    '        Sure.',
    3,
    [260, 260, 260, 260, 260, 260, 260, 260, 2756, 263],
  ),
  (
    'Open Create, then tap GhostWriter!',
    'Open Create, then tap GhostWriter!',
    1,
    [
      3732,
      439,
      444,
      280,
      492,
      262,
      351,
      3362,
      618,
      771,
      261,
      274,
      1563,
      582,
      641,
      682,
    ],
  ),
  (
    "It's 12.5 dollars, isn't it?",
    "It's 12.5 dollars, isn't it?",
    1,
    [
      333,
      264,
      261,
      260,
      341,
      365,
      263,
      437,
      260,
      1481,
      261,
      262,
      1112,
      264,
      274,
      275,
      292,
    ],
  ),
  (
    'Café naïve — résumé',
    '        Café naïve — résumé.',
    3,
    [
      260,
      260,
      260,
      260,
      260,
      260,
      260,
      260,
      1130,
      601,
      745,
      913,
      199,
      179,
      314,
      260,
      3133,
      670,
      745,
      261,
      766,
      745,
      263,
    ],
  ),
  (
    'Writing in GhostWriter uses OctoCredits; chatting is free',
    'Writing in GhostWriter uses OctoCredits; chatting is free.',
    1,
    [
      940,
      582,
      442,
      276,
      618,
      771,
      261,
      274,
      1563,
      582,
      641,
      567,
      261,
      705,
      440,
      612,
      732,
      1060,
      562,
      261,
      1230,
      596,
      274,
      442,
      277,
      804,
      263,
    ],
  ),
];

void main() {
  test('text is prepared like Pocket TTS does', () {
    for (final (text, prepared, afterEos, _) in cases) {
      expect(preparePocketText(text), (prepared, afterEos), reason: text);
    }
  });

  final vocab = File('assets/tts/vocab.json');
  test(
    'the tokenizer matches SentencePiece',
    () {
      final tokenizer = PocketTokenizer.fromJson(
        vocab.readAsStringSync(),
        File('assets/tts/token_scores.json').readAsStringSync(),
      );
      for (final (text, prepared, _, ids) in cases) {
        expect(tokenizer.encode(prepared), ids, reason: text);
      }
    },
    skip: vocab.existsSync() ? false : 'run tools/voice/fetch_onnx_bundle.py',
  );
}
