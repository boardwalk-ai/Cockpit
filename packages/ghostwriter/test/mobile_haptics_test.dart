import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('every landing button fires a haptic', (tester) async {
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );

    await tester.pumpWidget(const GhostWriterApp());
    await tester.pump(const Duration(seconds: 2));

    Future<void> expectHaptic(Finder finder, String type) async {
      haptics.clear();
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 600));
      expect(haptics, [type]);
    }

    const light = 'HapticFeedbackType.lightImpact';
    const medium = 'HapticFeedbackType.mediumImpact';
    const selection = 'HapticFeedbackType.selectionClick';

    await expectHaptic(find.byTooltip('Attach'), light);
    await expectHaptic(find.byTooltip('Source'), light);
    await expectHaptic(find.byTooltip('Voice'), light);
    await expectHaptic(find.byTooltip('OctoCredits'), selection);

    // Start only buzzes once there is a brief to send.
    haptics.clear();
    await tester.tap(find.byTooltip('Start'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(haptics, isEmpty);

    await expectHaptic(find.text('Draft an essay'), selection);
    await expectHaptic(find.byTooltip('Start'), medium);
  });

  testWidgets('menu button fires a haptic', (tester) async {
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );

    await tester.pumpWidget(const GhostWriterApp());
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.byTooltip('Essays'));
    await tester.pump(const Duration(milliseconds: 600));

    expect(haptics, ['HapticFeedbackType.lightImpact']);
  });
}
