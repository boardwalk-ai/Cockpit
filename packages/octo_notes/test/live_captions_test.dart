import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:octo_notes/src/application/live_captioner.dart';
import 'package:octo_notes/src/application/live_session.dart';

void main() {
  test('phone captions fill in past the server transcript, then give way', () {
    final live = LiveSession(thisDeviceId: 'me');
    live.addCaption({'deviceId': 'pixel', 'segId': 'd0', 'text': 'Glycolysis happens', 'startMs': 0, 'endMs': 1800, 'final': false});
    expect(live.lines.single.text, 'Glycolysis happens');
    expect(live.lines.single.live, isTrue);

    // The partial grows into the final sentence (same segment).
    live.addCaption({'deviceId': 'pixel', 'segId': 'd0', 'text': 'Glycolysis happens in the cytoplasm', 'startMs': 0, 'endMs': 3200, 'final': true});
    live.addCaption({'deviceId': 'pixel', 'segId': 'd1', 'text': 'No oxygen needed', 'startMs': 3200, 'endMs': 5000, 'final': false});
    expect(live.lines.map((l) => l.text), ['Glycolysis happens in the cytoplasm', 'No oxygen needed']);

    // An echo of this device's own caption over the socket is ignored.
    live.debugEvent({'type': 'transcript.live', 'data': {'deviceId': 'me', 'segId': 'x', 'text': 'echo', 'startMs': 0, 'endMs': 1}});
    expect(live.lines.any((l) => l.text == 'echo'), isFalse);
    live.debugEvent({'type': 'transcript.live', 'data': {'deviceId': 'pixel', 'segId': 'd2', 'text': 'Pyruvate', 'startMs': 5000, 'endMs': 6000}});
    expect(live.lines.last.text, 'Pyruvate');
    live.dispose();
  });

  test('pcm16 becomes floats in [-1, 1)', () {
    final pcm = Uint8List.fromList([0x00, 0x00, 0xFF, 0x7F, 0x00, 0x80]);
    final f = pcm16ToFloat(pcm);
    expect(f.length, 3);
    expect(f[0], 0);
    expect(f[1], closeTo(1, 1e-4));
    expect(f[2], -1);
  });
}
