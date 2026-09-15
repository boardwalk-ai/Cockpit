import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';

import 'format_spec.dart';

/// Renders the laid-out [DocPage]s as US-Letter sheets on the charcoal ground —
/// white paper, 1" margins, a running-head line (left furniture + right page
/// number), stacked with a gap between pages (the page break). Borderless: the
/// white-on-charcoal contrast separates the sheet; no outline, no shadow.
///
/// Intrinsic-size only (no internal scroll) so the caller can uniformly scale
/// it to any zoom via a [FittedBox] and scroll it as one column.
class PagedDocument extends StatelessWidget {
  const PagedDocument({
    super.key,
    required this.pages,
    required this.pageLabel,
  });

  final List<DocPage> pages;

  /// The right-side running-head text for page [n] (1-based) — e.g. "1" (APA)
  /// or "Lastname 1" (MLA).
  final String Function(int n) pageLabel;

  /// US Letter @96dpi.
  static const double pageWidth = 816;
  static const double _h = 1056;
  static const double _margin = 96;

  // Where page breaks fall in the (continuous) body content: the first break
  // near the first page's bottom margin, then one per full page thereafter.
  static const double _firstBreak = 916;
  static const double _pageStep = 960;

  final _headStyle = const TextStyle(
    fontFamily: 'packages/doc_oct/Tinos',
    fontFamilyFallback: ['Georgia', 'serif'],
    fontSize: 13,
    color: Color(0xFF6B7280),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < pages.length; i++) ...[
          if (i > 0) const SizedBox(height: CockpitSpacing.xl), // page break
          SizedBox(
            width: pageWidth,
            child: Container(
              constraints: const BoxConstraints(minHeight: _h),
              color: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: _margin,
                vertical: 48,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Running head: left furniture + right page number.
                  Row(
                    children: [
                      Expanded(
                          child:
                              pages[i].runningHead ?? const SizedBox.shrink()),
                      Text(pageLabel(i + 1), style: _headStyle),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Page-break separators overlay the content where it spills
                  // past a page — one editor underneath, so the caret and word
                  // count stay correct; the markers are purely visual.
                  CustomPaint(
                    foregroundPainter: _PageBreakPainter(
                      firstBreak: _firstBreak,
                      step: _pageStep,
                    ),
                    child: pages[i].content,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Draws a dashed rule + "PAGE BREAK" label wherever the continuous content
/// crosses a page boundary — the visual "page break" over a single editor. A
/// thin white band masks the content at the seam so the marker reads cleanly
/// instead of slicing through a line of text.
class _PageBreakPainter extends CustomPainter {
  _PageBreakPainter({required this.firstBreak, required this.step});

  final double firstBreak;
  final double step;

  static const _bandH = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    final dash = Paint()
      ..color = const Color(0xFFC9CED6)
      ..strokeWidth = 1;
    final white = Paint()..color = Colors.white;

    for (var y = firstBreak; y < size.height; y += step) {
      // Mask the seam so text doesn't collide with the marker.
      canvas.drawRect(
          Rect.fromLTWH(0, y - _bandH / 2, size.width, _bandH), white);

      // Dashed rule across the width.
      const dashW = 6.0, gapW = 5.0;
      for (var x = 0.0; x < size.width; x += dashW + gapW) {
        canvas.drawLine(
            Offset(x, y), Offset((x + dashW).clamp(0, size.width), y), dash);
      }

      // Centered "PAGE BREAK" label on a clear patch.
      final tp = TextPainter(
        text: const TextSpan(
          text: 'PAGE BREAK',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
            color: Color(0xFF9AA0AA),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final lx = (size.width - tp.width) / 2;
      canvas.drawRect(
          Rect.fromLTWH(lx - 10, y - _bandH / 2, tp.width + 20, _bandH), white);
      tp.paint(canvas, Offset(lx, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_PageBreakPainter old) =>
      old.firstBreak != firstBreak || old.step != step;
}
