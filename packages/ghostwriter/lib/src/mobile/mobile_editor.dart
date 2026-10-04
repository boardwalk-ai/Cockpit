import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../data/gw_api.dart';
import '../export/gw_pdf.dart';
import '../session/doc_session.dart';
import 'mobile_motion.dart';
import 'mobile_theme.dart';

/// Opens the essay's editor over the chat.
Future<void> openGwEditor(
  BuildContext context, {
  required GwApi api,
  required String projectId,
}) {
  gwHaptic(GwHaptic.medium);
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, _, _) =>
          GwEditorPage(api: api, projectId: projectId),
      transitionsBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

/// The editor is a white page, like paper, after the dark chat.
abstract final class _Paper {
  static const background = Colors.white;
  static const ink = Color(0xFF1C1D1F);
  static const muted = Color(0xFF6B6E73);
  static const faint = Color(0xFFB4B8BE);
  static const rule = Color(0xFFE8E8EA);
  static const wash = Color(0xFFF4F4F5);
  static const green = Color(0xFF1E9E5A);

  /// Doc Oct's metric-compatible Times New Roman.
  static const serif = 'packages/doc_oct/Tinos';
}

/// The essay on a phone: title, title-page details, the body and the
/// references, top to bottom (no pages). Read-only while GhostWriter writes,
/// with its text arriving live; editable after, saving on its own.
class GwEditorPage extends StatefulWidget {
  const GwEditorPage({
    super.key,
    required this.api,
    required this.projectId,
    this.session,
  });

  final GwApi api;
  final String projectId;

  /// A ready-made session, for tests.
  final GwDocumentSession? session;

  @override
  State<GwEditorPage> createState() => _GwEditorPageState();
}

class _GwEditorPageState extends State<GwEditorPage>
    with WidgetsBindingObserver {
  late final GwDocumentSession _doc =
      widget.session ?? GwDocumentSession(widget.api, widget.projectId);
  final ScrollController _scroll = ScrollController();
  final FocusNode _bodyFocus = FocusNode();

  /// Quill wants one; the page's own scroll view does the scrolling.
  final ScrollController _bodyScroll = ScrollController();
  bool _showDetails = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _doc.addListener(_onDoc);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving the app: save now rather than after the autosave delay.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _doc.save();
    }
  }

  void _onDoc() {
    final nearBottom =
        _scroll.hasClients &&
        _scroll.position.maxScrollExtent - _scroll.position.pixels < 200;
    setState(() {});
    // Follow the text as GhostWriter writes it, unless the reader scrolled up.
    if (_doc.locked && nearBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _doc.removeListener(_onDoc);
    if (widget.session == null) _doc.dispose();
    _scroll.dispose();
    _bodyScroll.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  /// The essay as it stands in the editor, as a formatted PDF.
  Future<void> _download() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await GwPdf.share(
        style: _doc.style,
        title: _doc.title.text,
        fields: {for (final e in _doc.fields.entries) e.key: e.value.text},
        body: _doc.body.document.toPlainText(),
        bibliography: _doc.bibliography.text,
      );
    } on Object {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't make the PDF. Try again.")),
      );
    }
  }

  Future<void> _openHistory() async {
    gwHaptic(GwHaptic.light);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _Paper.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _HistorySheet(doc: _doc),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editable = _doc.editable;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Theme(
        data: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          fontFamily: GwFonts.primary,
          colorScheme: ColorScheme.fromSeed(
            seedColor: GwColors.accent,
            surface: _Paper.background,
          ),
          textSelectionTheme: TextSelectionThemeData(
            cursorColor: GwColors.accent,
            selectionColor: GwColors.accent.withValues(alpha: 0.18),
            selectionHandleColor: GwColors.accent,
          ),
        ),
        // flutter_quill needs its localizations in the tree.
        child: Localizations.override(
          context: context,
          delegates: const [FlutterQuillLocalizations.delegate],
          child: Scaffold(
            backgroundColor: _Paper.background,
            body: SafeArea(
              child: Column(
                children: [
                  _Bar(
                    doc: _doc,
                    onHistory: editable ? _openHistory : null,
                    onDownload: editable ? _download : null,
                  ),
                  _Notices(doc: _doc),
                  Expanded(
                    child: !_doc.loaded
                        ? const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _Paper.muted,
                            ),
                          )
                        : _page(editable),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    child: editable
                        ? _Toolbar(controller: _doc.body)
                        : _LockedFooter(locked: _doc.locked),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _page(bool editable) {
    const bodySize = 15.0;
    final paper = TextStyle(
      fontFamily: _Paper.serif,
      fontSize: bodySize,
      height: 1.6,
      color: _Paper.ink,
    );
    final hasDetails = kDocFields.any(
      (f) => _doc.fields[f.$1]!.text.trim().isNotEmpty,
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PlainField(
                controller: _doc.title,
                enabled: editable,
                hint: 'Title',
                maxLines: null,
                style: const TextStyle(
                  fontFamily: _Paper.serif,
                  color: _Paper.ink,
                  fontSize: 23,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              _DetailsToggle(
                open: _showDetails,
                filled: hasDetails,
                onTap: () => setState(() => _showDetails = !_showDetails),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _showDetails
                    ? _Details(doc: _doc, enabled: editable)
                    : const SizedBox(width: double.infinity),
              ),
              const SizedBox(height: 14),
              QuillEditor(
                controller: _doc.body,
                focusNode: _bodyFocus,
                scrollController: _bodyScroll,
                config: QuillEditorConfig(
                  scrollable: false,
                  expands: false,
                  autoFocus: false,
                  showCursor: editable,
                  padding: EdgeInsets.zero,
                  placeholder: _doc.locked
                      ? 'GhostWriter is about to start writing…'
                      : 'Start writing…',
                  customStyles: DefaultStyles(
                    paragraph: _block(paper, after: 14),
                    placeHolder: _block(paper.copyWith(color: _Paper.faint)),
                    h1: _block(
                      paper.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
                      before: 8,
                      after: 10,
                    ),
                    h2: _block(
                      paper.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
                      before: 6,
                      after: 8,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 26),
              const Text(
                'REFERENCES',
                style: TextStyle(
                  color: _Paper.muted,
                  fontSize: 10,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              _PlainField(
                controller: _doc.bibliography,
                enabled: editable,
                hint: 'No references yet.',
                maxLines: null,
                style: paper.copyWith(fontSize: 12.5, height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static DefaultTextBlockStyle _block(
    TextStyle style, {
    double before = 0,
    double after = 0,
  }) => DefaultTextBlockStyle(
    style,
    HorizontalSpacing.zero,
    VerticalSpacing(before, after),
    VerticalSpacing.zero,
    null,
  );
}

/// A text field with no box at all: only the ink and the caret.
class _PlainField extends StatelessWidget {
  const _PlainField({
    required this.controller,
    required this.enabled,
    required this.hint,
    required this.style,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final bool enabled;
  final String hint;
  final TextStyle style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: !enabled,
      maxLines: maxLines,
      style: style,
      cursorColor: GwColors.accent,
      decoration: InputDecoration.collapsed(
        hintText: hint,
        hintStyle: style.copyWith(color: _Paper.faint),
      ),
    );
  }
}

class _DetailsToggle extends StatelessWidget {
  const _DetailsToggle({
    required this.open,
    required this.filled,
    required this.onTap,
  });

  final bool open;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: GwPressable(
        haptic: GwHaptic.selection,
        pressedScale: 0.96,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                filled ? Icons.badge_outlined : Icons.add_rounded,
                size: 16,
                color: _Paper.muted,
              ),
              const SizedBox(width: 6),
              Text(
                filled ? 'Title page details' : 'Add title page details',
                style: const TextStyle(
                  color: _Paper.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: const Duration(milliseconds: 220),
                child: const Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: _Paper.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.doc, required this.enabled});

  final GwDocumentSession doc;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Column(
        children: [
          for (final (key, label) in kDocFields)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: _Paper.rule)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: _Paper.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _PlainField(
                      controller: doc.fields[key]!,
                      enabled: enabled,
                      hint: '—',
                      style: const TextStyle(
                        color: _Paper.ink,
                        fontSize: 13,
                        fontFamily: GwFonts.secondary,
                        fontFamilyFallback: GwFonts.secondaryFallback,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.doc,
    required this.onHistory,
    required this.onDownload,
  });

  final GwDocumentSession doc;
  final VoidCallback? onHistory;

  /// Null while the agent writes.
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final words = doc.wordCount;
    final (color, label) = doc.offline
        ? (_Paper.muted, 'Reconnecting…')
        : doc.locked
        ? (GwColors.accent, 'Writing · $words words')
        : switch (doc.saveState) {
            SaveState.saved => (_Paper.green, 'Saved · $words words'),
            SaveState.dirty => (_Paper.muted, 'Edited · $words words'),
            SaveState.saving => (_Paper.muted, 'Saving…'),
            SaveState.failed => (GwColors.accent, 'Not saved · retrying'),
            SaveState.conflict => (GwColors.accent, 'Changed elsewhere'),
          };

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Row(
        children: [
          GwPressable(
            tooltip: 'Back to chat',
            onTap: () => Navigator.of(context).maybePop(),
            child: const SizedBox(
              width: kGwButton,
              height: kGwButton,
              child: Icon(
                Icons.arrow_back_rounded,
                color: _Paper.ink,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Text(
              'Editor',
              style: TextStyle(
                color: _Paper.ink,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (onDownload != null)
            GwPressable(
              tooltip: 'Download PDF',
              onTap: onDownload,
              child: const SizedBox(
                width: kGwButton,
                height: kGwButton,
                child: Icon(
                  Icons.download_rounded,
                  color: _Paper.ink,
                  size: 22,
                ),
              ),
            ),
          if (onHistory != null)
            GwPressable(
              tooltip: 'History',
              onTap: onHistory,
              child: const SizedBox(
                width: kGwButton,
                height: kGwButton,
                child: Icon(Icons.history_rounded, color: _Paper.ink, size: 22),
              ),
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// A plain line under the bar for a conflict or a one-off notice.
class _Notices extends StatelessWidget {
  const _Notices({required this.doc});

  final GwDocumentSession doc;

  @override
  Widget build(BuildContext context) {
    final String? text;
    final String action;
    final VoidCallback onAction;
    if (doc.saveState == SaveState.conflict) {
      text =
          'This essay was changed somewhere else. Load that version to keep '
          'editing (your newest edits here will be replaced).';
      action = 'Load';
      onAction = doc.reload;
    } else if (doc.notice != null) {
      text = doc.notice;
      action = 'OK';
      onAction = doc.clearNotice;
    } else {
      text = null;
      action = '';
      onAction = () {};
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      child: text == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 10, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(
                        color: GwColors.accent,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onAction,
                    child: Text(
                      action,
                      style: const TextStyle(
                        color: _Paper.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _LockedFooter extends StatelessWidget {
  const _LockedFooter({required this.locked});

  final bool locked;

  @override
  Widget build(BuildContext context) {
    if (!locked) return const SizedBox(width: double.infinity);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _Paper.rule)),
      ),
      child: const Row(
        children: [
          Icon(Icons.lock_clock_rounded, size: 16, color: _Paper.muted),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Read-only while GhostWriter writes.',
              style: TextStyle(color: _Paper.muted, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Formatting for the body: undo / redo, bold / italic / underline, a
/// heading, and lists. Sits above the keyboard.
class _Toolbar extends StatefulWidget {
  const _Toolbar({required this.controller});

  final QuillController controller;

  @override
  State<_Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends State<_Toolbar> {
  QuillController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_refresh);
  }

  @override
  void didUpdateWidget(_Toolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      _c.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  bool _on(Attribute attribute) =>
      _c.getSelectionStyle().attributes[attribute.key]?.value ==
      attribute.value;

  void _toggle(Attribute attribute) {
    _c.formatSelection(
      _on(attribute) ? Attribute.clone(attribute, null) : attribute,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget format(IconData icon, String tip, Attribute attribute) => _Tool(
      icon: icon,
      tooltip: tip,
      active: _on(attribute),
      onTap: () => _toggle(attribute),
    );

    return Container(
      height: 52,
      decoration: const BoxDecoration(
        color: _Paper.background,
        border: Border(top: BorderSide(color: _Paper.rule)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          _Tool(
            icon: Icons.undo_rounded,
            tooltip: 'Undo',
            onTap: _c.hasUndo ? _c.undo : null,
          ),
          _Tool(
            icon: Icons.redo_rounded,
            tooltip: 'Redo',
            onTap: _c.hasRedo ? _c.redo : null,
          ),
          const _Divider(),
          format(Icons.format_bold_rounded, 'Bold', Attribute.bold),
          format(Icons.format_italic_rounded, 'Italic', Attribute.italic),
          format(
            Icons.format_underlined_rounded,
            'Underline',
            Attribute.underline,
          ),
          const _Divider(),
          format(Icons.title_rounded, 'Heading', Attribute.h2),
          format(Icons.format_list_bulleted_rounded, 'Bullets', Attribute.ul),
          format(Icons.format_list_numbered_rounded, 'Numbers', Attribute.ol),
          format(Icons.format_quote_rounded, 'Quote', Attribute.blockQuote),
        ],
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GwPressable(
      tooltip: tooltip,
      haptic: GwHaptic.selection,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 42,
        margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 6),
        decoration: BoxDecoration(
          color: active ? _Paper.wash : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 21,
          color: onTap == null
              ? _Paper.faint
              : active
              ? GwColors.accent
              : _Paper.ink,
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
    color: _Paper.rule,
  );
}

// ── History ──────────────────────────────────────────────────────────────

class _HistorySheet extends StatefulWidget {
  const _HistorySheet({required this.doc});

  final GwDocumentSession doc;

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  late final Future<List<Map<String, dynamic>>> _versions = widget.doc
      .versions();
  String? _restoring;

  static String reasonLabel(String reason) => switch (reason) {
    'agent_write' => 'Before GhostWriter wrote',
    'agent_revise' => 'Before GhostWriter revised',
    'humanize' => 'Before humanizing',
    'user_save' => 'Before your edits',
    'restore' => 'Before a restore',
    _ => reason,
  };

  static String ago(String? iso) {
    final at = DateTime.tryParse(iso ?? '')?.toLocal();
    if (at == null) return '';
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${at.year}-${at.month.toString().padLeft(2, '0')}-'
        '${at.day.toString().padLeft(2, '0')}';
  }

  Future<void> _restore(Map<String, dynamic> version) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _Paper.background,
        title: const Text('Restore this version?'),
        content: const Text(
          'The essay goes back to how it was then. What it replaces is kept '
          'in History, so you can undo this too.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _restoring = version['id'].toString());
    try {
      await widget.doc.restore(version['id'].toString());
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _restoring = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (context, scroll) => FutureBuilder(
        future: _versions,
        builder: (context, snapshot) {
          final versions = snapshot.data ?? const [];
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 30),
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _Paper.rule,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'History',
                style: TextStyle(
                  color: _Paper.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Earlier versions of this essay. Tap one to go back to it.',
                style: TextStyle(color: _Paper.muted, fontSize: 11),
              ),
              const SizedBox(height: 12),
              if (snapshot.connectionState != ConnectionState.done)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _Paper.muted,
                    ),
                  ),
                )
              else if (snapshot.hasError)
                const Text(
                  'Could not load the history.',
                  style: TextStyle(color: GwColors.accent),
                )
              else if (versions.isEmpty)
                const Text(
                  'No earlier versions yet.',
                  style: TextStyle(color: _Paper.muted),
                ),
              for (final v in versions)
                GwPressable(
                  pressedScale: 0.98,
                  haptic: GwHaptic.selection,
                  onTap: _restoring == null ? () => _restore(v) : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: _Paper.rule)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                reasonLabel(v['reason']?.toString() ?? ''),
                                style: const TextStyle(
                                  color: _Paper.ink,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${ago(v['createdAt']?.toString())} · '
                                '${v['wordCount'] ?? 0} words',
                                style: const TextStyle(
                                  color: _Paper.muted,
                                  fontSize: 11.5,
                                ),
                              ),
                              if ((v['preview']?.toString() ?? '').isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    v['preview'].toString(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _Paper.muted,
                                      fontFamily: _Paper.serif,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (_restoring == v['id'].toString())
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          const Icon(
                            Icons.restore_rounded,
                            color: _Paper.muted,
                            size: 20,
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
