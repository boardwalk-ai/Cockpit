import 'package:doc_oct/src/presentation/widgets/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Counter extends StatefulWidget {
  const _Counter(this.label);
  final String label;
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int n = 0;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => n++),
    child: Text('${widget.label} $n'),
  );
}

void main() {
  Widget host(String page) => MaterialApp(
    home: Scaffold(
      body: BlinkSwitcher(pageKey: page, child: _Counter(page)),
    ),
  );

  testWidgets('blink: old page until the eye shuts, then the new page', (
    t,
  ) async {
    await t.pumpWidget(host('A'));
    expect(find.text('A 0'), findsOneWidget);

    await t.pumpWidget(host('B'));
    await t.pump(const Duration(milliseconds: 150)); // closing
    expect(find.text('A 0'), findsOneWidget);
    expect(find.text('B 0'), findsNothing);

    await t.pump(const Duration(milliseconds: 300)); // past the midpoint
    expect(find.text('B 0'), findsOneWidget);
    expect(find.text('A 0'), findsNothing);

    await t.pumpAndSettle();
    expect(find.text('B 0'), findsOneWidget);
  });

  testWidgets('the page keeps its state when the blink finishes', (t) async {
    await t.pumpWidget(host('A'));
    await t.pumpWidget(host('B'));
    await t.pump(const Duration(milliseconds: 500)); // new page mounted
    await t.pumpAndSettle();
    await t.tap(find.text('B 0'));
    await t.pump();
    expect(find.text('B 1'), findsOneWidget);
    // A rebuild at rest must not recreate the page (same tree shape).
    await t.pumpWidget(host('B'));
    await t.pump();
    expect(find.text('B 1'), findsOneWidget);
  });

  test('closure: open → shut → open', () {
    expect(blinkClosure(0), 0);
    expect(blinkClosure(0.46), 1);
    expect(blinkClosure(1), closeTo(0, 1e-9));
  });

  testWidgets('Pressable squishes while pressed and springs back', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Center(
          child: Pressable(
            child: TextButton(onPressed: () {}, child: const Text('Tap')),
          ),
        ),
      ),
    );
    double scale() => t.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
    expect(scale(), 1.0);
    final g = await t.startGesture(t.getCenter(find.text('Tap')));
    await t.pump();
    expect(scale(), lessThan(1.0));
    await g.up();
    await t.pump();
    expect(scale(), 1.0);
    await t.pumpAndSettle();
  });

  testWidgets('disabled Pressable stays still', (t) async {
    await t.pumpWidget(
      const MaterialApp(
        home: Center(child: Pressable(enabled: false, child: Text('Off'))),
      ),
    );
    final g = await t.startGesture(t.getCenter(find.text('Off')));
    await t.pump();
    expect(t.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1.0);
    await g.up();
  });
}
