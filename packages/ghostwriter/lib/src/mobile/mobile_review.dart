import 'package:flutter/material.dart';

import '../data/gw_api.dart';
import '../review/essay_diff.dart';
import '../session/gw_session.dart';
import '../session/timeline.dart';
import 'mobile_motion.dart';
import 'mobile_theme.dart';

const _addedBg = Color(0x333DDC84);
const _addedFg = Color(0xFFB8F5CF);
const _removedBg = Color(0x33FF4A4F);
const _removedFg = Color(0xFFFF9A9E);

/// Opens the review of a revision: the essay as it was against the document
/// now. Returns what the user did, or null if they just looked.
Future<RevisionReview?> openGwReview(
  BuildContext context, {
  required GwApi api,
  required String projectId,
  required String versionId,
}) {
  return Navigator.of(context).push<RevisionReview>(
    MaterialPageRoute(
      builder: (_) =>
          _ReviewPage(api: api, projectId: projectId, versionId: versionId),
    ),
  );
}

/// In the chat, after a revision: what changed, and Review.
class GwRevisionCard extends StatelessWidget {
  const GwRevisionCard({
    super.key,
    required this.revision,
    required this.review,
    required this.onReview,
  });

  final RevisionItem revision;
  final RevisionReview? review;

  /// Null while the run is still going.
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (review) {
      RevisionReview.kept => ('Changes kept', const Color(0xFF3DDC84)),
      RevisionReview.undone => ('Changes undone', GwColors.muted),
      null => ('Review the changes', Colors.white),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1C1F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: GwColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.difference_outlined, size: 20, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Essay revised',
                  style: kGwBody.copyWith(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${revision.wordsBefore} → ${revision.wordsAfter} words',
                  style: kGwBody.copyWith(color: GwColors.muted, fontSize: 10),
                ),
              ],
            ),
          ),
          GwPressable(
            tooltip: 'Review changes',
            onTap: onReview,
            haptic: GwHaptic.selection,
            child: AnimatedOpacity(
              opacity: onReview == null ? 0.4 : 1,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A1416),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFF7A2D31)),
                ),
                child: Text(
                  label,
                  style: kGwBody.copyWith(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewPage extends StatefulWidget {
  const _ReviewPage({
    required this.api,
    required this.projectId,
    required this.versionId,
  });

  final GwApi api;
  final String projectId;
  final String versionId;

  @override
  State<_ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<_ReviewPage> {
  late final Future<EssayDiff> _diff = _load();
  bool _onlyChanges = true;
  bool _busy = false;
  String? _error;

  Future<EssayDiff> _load() async {
    final results = await Future.wait([
      widget.api.version(widget.projectId, widget.versionId),
      widget.api.document(widget.projectId),
    ]);
    return diffEssay(
      results[0]['body']?.toString() ?? '',
      results[1]['body']?.toString() ?? '',
    );
  }

  Future<void> _undo() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GwColors.panel,
        title: const Text('Undo the changes?'),
        content: const Text(
          'Your essay goes back to how it was before this revision. Edits '
          'you made since then are undone too.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Undo'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.restoreVersion(widget.projectId, widget.versionId);
      if (mounted) Navigator.of(context).pop(RevisionReview.undone);
    } on GwApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't undo. Try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GwColors.background,
      appBar: AppBar(
        backgroundColor: GwColors.background,
        foregroundColor: Colors.white,
        title: Text(
          'Changes',
          style: kGwBody.copyWith(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => setState(() => _onlyChanges = !_onlyChanges),
            child: Text(
              _onlyChanges ? 'Show all' : 'Only changes',
              style: kGwBody.copyWith(color: GwColors.muted, fontSize: 12),
            ),
          ),
        ],
      ),
      body: FutureBuilder<EssayDiff>(
        future: _diff,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                "Couldn't load the changes.",
                style: kGwBody.copyWith(color: GwColors.muted),
              ),
            );
          }
          final diff = snapshot.data;
          if (diff == null) {
            return const Center(
              child: CircularProgressIndicator(color: GwColors.accent),
            );
          }
          return Column(
            children: [
              _Summary(diff: diff),
              Expanded(
                child: _Paragraphs(diff: diff, only: _onlyChanges),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Text(
                    _error!,
                    style: kGwBody.copyWith(color: _removedFg, fontSize: 12),
                  ),
                ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy || !diff.changed ? null : _undo,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: GwColors.border),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: const StadiumBorder(),
                          ),
                          child: const Text('Undo changes'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(
                                  context,
                                ).pop(RevisionReview.kept),
                          style: FilledButton.styleFrom(
                            backgroundColor: GwColors.accent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: const StadiumBorder(),
                          ),
                          child: const Text('Keep changes'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.diff});

  final EssayDiff diff;

  @override
  Widget build(BuildContext context) {
    Widget chip(String text, Color bg, Color fg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: kGwBody.copyWith(color: fg, fontSize: 11)),
    );
    final paragraphs = diff.changedParagraphs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          chip('+${diff.wordsAdded} words', _addedBg, _addedFg),
          const SizedBox(width: 8),
          chip('−${diff.wordsRemoved} words', _removedBg, _removedFg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              diff.changed
                  ? '$paragraphs paragraph${paragraphs == 1 ? '' : 's'} changed'
                  : 'Nothing changed',
              textAlign: TextAlign.right,
              style: kGwBody.copyWith(color: GwColors.muted, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _Paragraphs extends StatelessWidget {
  const _Paragraphs({required this.diff, required this.only});

  final EssayDiff diff;
  final bool only;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final (i, p) in diff.paragraphs.indexed)
        if (!only || p.changed) (i, p),
    ];
    final base = kGwBody.copyWith(
      color: Colors.white,
      fontSize: 14,
      height: 1.6,
    );
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: shown.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, k) {
        final (index, paragraph) = shown[k];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF17181A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: paragraph.changed ? GwColors.border : Colors.transparent,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '¶ ${index + 1}',
                style: kGwBody.copyWith(color: GwColors.muted, fontSize: 10),
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  children: [
                    for (final span in paragraph.spans)
                      TextSpan(
                        text: span.text,
                        style: switch (span.op) {
                          DiffOp.same => base.copyWith(
                            color: paragraph.changed
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.55),
                          ),
                          DiffOp.added => base.copyWith(
                            color: _addedFg,
                            backgroundColor: _addedBg,
                          ),
                          DiffOp.removed => base.copyWith(
                            color: _removedFg,
                            backgroundColor: _removedBg,
                            decoration: TextDecoration.lineThrough,
                            decorationColor: _removedFg,
                          ),
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
