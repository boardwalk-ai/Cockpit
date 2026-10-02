import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mobile_motion.dart';
import 'mobile_theme.dart';

/// Bottom sheet with the essay's details and its sources: the phone version
/// of the desktop right-hand panel.
Future<void> showGwDetailsSheet(
  BuildContext context, {
  required String title,
  required bool finished,
  required String citationStyle,
  required int wordCount,
  required List<Map<String, dynamic>> sources,
  required String bibliography,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (context, scrollController) => _DetailsSheet(
        scrollController: scrollController,
        title: title,
        finished: finished,
        citationStyle: citationStyle,
        wordCount: wordCount,
        sources: sources,
        bibliography: bibliography,
      ),
    ),
  );
}

class _DetailsSheet extends StatelessWidget {
  const _DetailsSheet({
    required this.scrollController,
    required this.title,
    required this.finished,
    required this.citationStyle,
    required this.wordCount,
    required this.sources,
    required this.bibliography,
  });

  final ScrollController scrollController;
  final String title;
  final bool finished;
  final String citationStyle;
  final int wordCount;
  final List<Map<String, dynamic>> sources;
  final String bibliography;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.vertical(top: Radius.circular(28));

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xF01B1C1C),
            borderRadius: radius,
            border: Border(top: BorderSide(color: Color(0x1FFFFFFF))),
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(
              16,
              10,
              16,
              24 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0x40FFFFFF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const _Heading('Essay details'),
              _Tile(label: 'Topic', value: title),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _Tile(
                      label: 'Status',
                      value: finished ? 'Finished' : 'Writing',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Tile(label: 'Citation', value: citationStyle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Tile(
                      label: 'Words',
                      value: wordCount > 0 ? '$wordCount' : 'Pending',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _Heading(
                'Sources',
                trailing: sources.isEmpty ? null : '${sources.length}',
              ),
              if (sources.isEmpty)
                _Note(
                  finished
                      ? 'No sources were returned by the backend.'
                      : 'Sources appear here once the draft is finished.',
                )
              else
                for (final source in sources) _SourceCard(source: source),
              if (bibliography.isNotEmpty) ...[
                const SizedBox(height: 16),
                const _Heading('Reference list'),
                SelectableText(
                  bibliography,
                  style: const TextStyle(
                    color: Color(0xFFC9CACC),
                    fontFamily: GwFonts.secondary,
                    fontFamilyFallback: GwFonts.secondaryFallback,
                    fontSize: 13,
                    height: 1.55,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final trailing = this.trailing;

    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 10),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF2A1416),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                trailing,
                style: const TextStyle(
                  color: GwColors.accentSoft,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        color: const Color(0x0FFFFFFF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: GwColors.hint,
              fontSize: 10.5,
              letterSpacing: 1.3,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14.5,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x0FFFFFFF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: GwColors.muted,
          fontFamily: GwFonts.secondary,
          fontFamilyFallback: GwFonts.secondaryFallback,
          fontSize: 13,
          height: 1.4,
        ),
      ),
    );
  }
}

/// One source. Tapping it copies the link, since the app has no browser.
class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.source});

  final Map<String, dynamic> source;

  String _field(String key) => (source[key] ?? '').toString().trim();

  @override
  Widget build(BuildContext context) {
    final title = _field('title');
    final byline = [
      _field('author'),
      _field('publisher'),
    ].where((part) => part.isNotEmpty).join(' · ');
    final url = _field('url');

    const secondary = TextStyle(
      color: GwColors.muted,
      fontFamily: GwFonts.secondary,
      fontFamilyFallback: GwFonts.secondaryFallback,
      fontSize: 12.5,
      height: 1.35,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GwPressable(
        pressedScale: 0.98,
        haptic: GwHaptic.selection,
        onTap: url.isEmpty
            ? null
            : () {
                Clipboard.setData(ClipboardData(text: url));
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    const SnackBar(
                      content: Text('Link copied'),
                      duration: Duration(milliseconds: 1400),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
              },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
          decoration: BoxDecoration(
            color: const Color(0x0FFFFFFF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.isEmpty ? 'Untitled source' : title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (byline.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(byline, style: secondary),
              ],
              if (url.isNotEmpty) ...[
                const SizedBox(height: 7),
                Row(
                  children: [
                    const Icon(
                      Icons.link_rounded,
                      size: 15,
                      color: GwColors.accentSoft,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: secondary.copyWith(color: GwColors.accentSoft),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
