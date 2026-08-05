import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/data/mock/mock_data.dart';
import 'package:study_studio/src/presentation/progress/progress_page.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('progress page golden', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);

    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final studio = buildMockStudiosStashed().first;

    await pumpTestApp(
      tester,
      child: ProgressPage(studioId: studio.id),
      studios: [studio],
    );

    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/progress_page.png'),
    );
  });
}