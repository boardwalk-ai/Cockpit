import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Static text with a real **first-line** or **hanging** indent — something
/// Flutter's `Text` (and flutter_quill) can't do natively. Lays the text out
/// once, then paints each line at its own x-offset. Used for bibliography
/// entries (hanging indent) and any static indented paragraph.
class IndentedText extends StatelessWidget {
  const IndentedText(
    this.text, {
    super.key,
    required this.style,
    this.firstLineIndent = 0,
    this.restIndent = 0,
    this.textAlign = TextAlign.left,
  });

  final String text;
  final TextStyle style;

  /// Indent (px) applied to the first line only (e.g. body paragraphs).
  final double firstLineIndent;

  /// Indent (px) applied to every line except the first (e.g. hanging refs).
  final double restIndent;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxIndent = math.max(firstLineIndent, restIndent);
        final tp = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
          textAlign: textAlign,
        )..layout(maxWidth: constraints.maxWidth - maxIndent);
        return CustomPaint(
          size: Size(constraints.maxWidth, tp.height),
          painter: _IndentPainter(tp, firstLineIndent, restIndent),
        );
      },
    );
  }
}

class _IndentPainter extends CustomPainter {
  _IndentPainter(this.tp, this.firstIndent, this.restIndent);

  final TextPainter tp;
  final double firstIndent;
  final double restIndent;

  @override
  void paint(Canvas canvas, Size size) {
    var top = 0.0;
    for (final m in tp.computeLineMetrics()) {
      final x = m.lineNumber == 0 ? firstIndent : restIndent;
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, top, size.width, m.height));
      tp.paint(canvas, Offset(x, 0));
      canvas.restore();
      top += m.height;
    }
  }

  @override
  bool shouldRepaint(_IndentPainter old) =>
      old.tp != tp ||
      old.firstIndent != firstIndent ||
      old.restIndent != restIndent;
}
