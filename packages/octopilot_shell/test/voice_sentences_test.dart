import 'package:flutter_test/flutter_test.dart';
import 'package:octopilot_shell/src/voice/voice_loop.dart';

void main() {
  test('a reply is spoken a sentence at a time', () {
    expect(
      VoiceLoop.sentences(
        'Yes, chatting is free, but there is a daily limit. '
        'Writing in GhostWriter uses OctoCredits! Want to try?',
      ),
      [
        'Yes, chatting is free, but there is a daily limit.',
        'Writing in GhostWriter uses OctoCredits! Want to try?',
      ],
    );
  });

  test('short sentences go with the next one', () {
    expect(VoiceLoop.sentences('Sure. Open Create, then tap GhostWriter.'), [
      'Sure. Open Create, then tap GhostWriter.',
    ]);
    expect(VoiceLoop.sentences('Hi!'), ['Hi!']);
    expect(VoiceLoop.sentences('   '), isEmpty);
  });
}
