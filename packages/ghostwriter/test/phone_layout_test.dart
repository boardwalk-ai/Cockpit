import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  for (final size in const [
    Size(360, 740),
    Size(390, 844),
    Size(430, 932),
    Size(740, 360), // landscape
    Size(420, 250), // split view
  ]) {
    testWidgets(
      'no layout overflow at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(const GhostWriterApp());
        await tester.pump();

        expect(tester.takeException(), isNull);
      },
    );
  }
}
