import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwriter/src/mobile/mobile_app.dart';

import 'support.dart';

void main() {
  testWidgets('app boots into GhostWriter', (tester) async {
    await tester.pumpWidget(const GhostWriterApp());
    expect(find.byType(GhostWriterMobileApp), findsOneWidget);
  });
}
