import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwriter/src/ghostwriter_page.dart';

import 'support.dart';

void main() {
  testWidgets('app boots into GhostWriter', (tester) async {
    await tester.pumpWidget(const GhostWriterApp());
    expect(find.byType(GhostWriterPage), findsOneWidget);
  });
}
