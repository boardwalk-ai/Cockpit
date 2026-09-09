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

  @override
  Widget build(BuildContext context) {
    final headStyle = TextStyle(
      fontFamily: 'Times New Roman',
      fontFamilyFallback: const ['Georgia', 'serif'],
      fontSize: 13,
      color: const Color(0xFF6B7280),
    );

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
                              child: pages[i].runningHead ??
                                  const SizedBox.shrink()),
                          Text(pageLabel(i + 1), style: headStyle),
                        ],
                      ),
                      const SizedBox(height: 24),
                      pages[i].content,
                    ],
                  ),
                ),
          ),
        ],
      ],
    );
  }
}
