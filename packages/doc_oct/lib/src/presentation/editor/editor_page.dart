import 'dart:async';
import 'dart:convert';

import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../application/backend_config.dart';
import '../../application/essays_service.dart';
import '../../application/idempotent_post.dart';
import '../../application/pdf_export_app.dart';
import '../../application/wizard_session.dart';
import '../../domain/hein_analysis.dart';
import '../../domain/outline.dart';
import '../../domain/source.dart';
import '../../theme/doc_tokens.dart';
import '../widgets/auth_chip.dart';
import '../widgets/doc_button.dart';
import '../widgets/doc_scaffold.dart';
import '../widgets/doc_widgets.dart';
import '../widgets/motion.dart';
import 'doc_model.dart';
import 'editor_panels.dart';
import 'editor_toolbar.dart';
import 'format_spec.dart';
import 'octobot_panel.dart';
import 'outline_panel.dart';
import 'paged_document.dart';
import 'tools_panel.dart';

/// The central editor — Doc Oct's web editor, restyled borderless. The paper is
/// the one light element (a real page); the chrome is flat charcoal. The style
/// pills re-project the *same* semantic fields, so switching APA↔MLA reflows
/// without touching content.
class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    this.initialStyle = FormatStyle.apa,
    this.onBack,
    this.initialDocId,
    this.initialDocJson,
    this.essays,
  });

  final FormatStyle initialStyle;
  final VoidCallback? onBack;

  /// When opening a saved document: its id (so Save updates in place) and its
  /// serialized state (restored into the editor on load).
  final String? initialDocId;
  final String? initialDocJson;

  /// Saved-documents store; defaults to the backend one (injectable in tests).
  final EssaysService? essays;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late FormatStyle _style = widget.initialStyle;

  /// null = auto fit-to-height; otherwise a manual zoom the user set with ±.
  double? _zoomOverride;

  // Side panels (Outline · Tools) — default widths, drag-resizable, collapsible.
  bool _leftOpen = true;
  bool _rightOpen = true;
  double _leftWidth = 340;
  double _rightWidth = 320;

  final _docTitle = TextEditingController(
    text: WizardSession.searchTopic.isEmpty
        ? 'Untitled document'
        : WizardSession.searchTopic,
  );
  final _title = TextEditingController(text: WizardSession.searchTopic);
  final _abstract = TextEditingController();
  final _keywords = TextEditingController();
  late final Map<DocFieldKind, TextEditingController> _fields = {
    for (final k in DocFieldKind.values) k: TextEditingController(),
  };

  late final List<TextEditingController> _all = [
    _title,
    _abstract,
    _keywords,
    ..._fields.values,
  ];

  // Researched sources feeding the references page. Starts EMPTY — a new document
  // has no citations until the user adds real sources (Tools → Source search /
  // Insert, or Manual → Generate Citation). Updated via onSourcesFound; the
  // in-text citation index follows this order.
  List<Source> _sources = const [];

  // The body prose — flutter_quill (EditableText underneath → works on web).
  final QuillController _body = QuillController.basic();
  final FocusNode _bodyFocus = FocusNode();
  final ScrollController _bodyScroll = ScrollController();

  // True while a PDF export is in flight (disables the Finish button).
  bool _exporting = false;

  // Saving: the backing essay id (null until first save) + in-flight flag.
  String? _savedId;

  /// This document's id. A new document picks its UUID up front, so its first
  /// save is an idempotent upsert — a retried or overlapping first save can't
  /// create a second copy in the Saving deck.
  late final String _docId = widget.initialDocId ?? newUuid();
  bool _saving = false;

  /// Autosave — the editor is one session: every 10 s any change (fields,
  /// body, sources, analysis, outlines) is written to the user's document.
  static const autosaveEvery = Duration(seconds: 10);
  Timer? _autosaveTimer;

  /// Title + state last written to the server; a tick only saves when it differs.
  String? _lastSaved;

  /// Small status beside the Save button ("Saving…", "Saved", …).
  String _saveStatus = '';

  /// Guards the essay-title ⇄ doc-bar mirror against feedback loops.
  bool _syncingTitle = false;

  @override
  void initState() {
    super.initState();
    _savedId = widget.initialDocId;
    if (widget.initialDocJson != null) _restore(widget.initialDocJson!);
    _titleToBar();
    // An opened document starts "clean"; a new one saves once it has content.
    if (_savedId != null) _lastSaved = _snapshot();
    for (final c in _all) {
      c.addListener(_onChanged);
    }
    _title.addListener(_titleToBar);
    _docTitle.addListener(_barToTitle);
    _body.addListener(_onChanged);
    _autosaveTimer = Timer.periodic(autosaveEvery, (_) => _save(silent: true));
  }

  void _onChanged() => setState(() {});

  /// The saved title is the essay title, or "Untitled document" until written.
  String get _saveTitle =>
      _title.text.trim().isEmpty ? 'Untitled document' : _title.text.trim();

  // The doc bar mirrors the essay title; renaming in the bar renames the essay.
  void _titleToBar() {
    if (_syncingTitle || _docTitle.text == _saveTitle) return;
    _syncingTitle = true;
    _docTitle.text = _saveTitle;
    _syncingTitle = false;
  }

  void _barToTitle() {
    if (_syncingTitle) return;
    final bar = _docTitle.text;
    final want = bar.trim() == 'Untitled document' ? '' : bar;
    if (_title.text == want) return;
    _syncingTitle = true;
    _title.text = want;
    _syncingTitle = false;
  }

  /// Nothing worth a document row yet (a blank "Start writing" editor).
  bool get _isBlank =>
      _bodyText.trim().isEmpty &&
      _all.every((c) => c.text.trim().isEmpty) &&
      _sources.isEmpty &&
      WizardSession.analysis == null &&
      WizardSession.outlines.isEmpty;

  String _snapshot() => '$_saveTitle\u0000${_docStateJson()}';

  /// Flush pending changes, then leave the editor.
  Future<void> _leave() async {
    _autosaveTimer?.cancel();
    await _save(silent: true);
    widget.onBack?.call();
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _title.removeListener(_titleToBar);
    _docTitle.removeListener(_barToTitle);
    for (final c in _all) {
      c.removeListener(_onChanged);
      c.dispose();
    }
    _docTitle.dispose();
    _body.removeListener(_onChanged);
    _body.dispose();
    _bodyFocus.dispose();
    _bodyScroll.dispose();
    super.dispose();
  }

  String get _bodyText => _body.document.toPlainText();

  int get _words => [..._all.map((c) => c.text), _bodyText]
      .expand((t) => t.trim().split(RegExp(r'\s+')))
      .where((w) => w.isNotEmpty)
      .length;

  int get _chars =>
      _all.fold(0, (n, c) => n + c.text.length) + _bodyText.trim().length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final spec = FormatSpec.of(_style);
    final profile = spec.profile;
    final paperStyle = TextStyle(
      fontFamily: 'packages/doc_oct/Tinos',
      fontFamilyFallback: const ['Georgia', 'serif'],
      fontSize: profile.fontSize,
      height: profile.lineHeight,
      color: const Color(0xFF1A1A1A),
    );
    final fields = EditorFields(
      title: _title,
      fields: _fields,
      abstractText: _abstract,
      keywords: _keywords,
      baseStyle: paperStyle,
      hintColor: const Color(0xFFB4B8BE),
      cursorColor: scheme.primary,
    );
    final pages = spec.buildPages(
      context,
      fields,
      body: _bodyEditor(paperStyle),
      sources: _sources,
      style: _style,
    );
    final lastName = fields.authorLastName;

    // Auto fit-to-height so a short viewport isn't stuck at a giant 1:1 page;
    // the user can override with the ± zoom control.
    final viewportH = MediaQuery.sizeOf(context).height;
    final fitZoom = ((viewportH - 210) / PagedDocument.pageWidth * 8.5 / 11)
        .clamp(0.5, 1.0);
    final zoom = _zoomOverride ?? fitZoom;
    final panelMax = (MediaQuery.sizeOf(context).width / 2 - 40).clamp(
      240,
      720,
    );

    final center = Column(
      children: [
        _docBar(theme, scheme),
        _styleRow(theme, scheme),
        _formatToolbar(scheme, zoom),
        Expanded(
          child: ColoredBox(
            color: scheme.surface,
            // flutter_quill needs its localization delegate in-tree.
            child: Localizations(
              locale: const Locale('en'),
              delegates: const [
                FlutterQuillLocalizations.delegate,
                DefaultMaterialLocalizations.delegate,
                DefaultWidgetsLocalizations.delegate,
              ],
              child: SingleChildScrollView(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: CockpitSpacing.md,
                    ),
                    child: SizedBox(
                      width: PagedDocument.pageWidth * zoom,
                      child: FittedBox(
                        fit: BoxFit.fitWidth,
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          width: PagedDocument.pageWidth,
                          child: PagedDocument(
                            pages: pages,
                            pageLabel: (n) => _style == FormatStyle.mla
                                ? '$lastName $n'
                                : '$n',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        _statusBar(theme, scheme),
      ],
    );

    return DocScaffold(
      child: SafeArea(
        child: Stack(
          children: [
            Row(
              children: [
                SidePanel(
                  side: PanelSide.left,
                  open: _leftOpen,
                  width: _leftWidth,
                  defaultWidth: 340,
                  maxWidth: panelMax.toDouble(),
                  title: 'Outline',
                  onToggle: () => setState(() => _leftOpen = !_leftOpen),
                  onResize: (w) => setState(() => _leftWidth = w),
                  child: OutlinePanel(
                    topic: _title.text.trim().isEmpty
                        ? _docTitle.text
                        : _title.text,
                    onInsertText: _insertIntoBody,
                    // Topic given in the editor ("Start writing" skipped the
                    // wizard) → fill in the still-empty titles.
                    onTopicSet: (topic) => setState(() {
                      if (_title.text.trim().isEmpty) _title.text = topic;
                      final doc = _docTitle.text.trim();
                      if (doc.isEmpty || doc == 'Untitled document') {
                        _docTitle.text = topic;
                      }
                    }),
                  ),
                ),
                Expanded(child: center),
                SidePanel(
                  side: PanelSide.right,
                  open: _rightOpen,
                  width: _rightWidth,
                  defaultWidth: 320,
                  maxWidth: panelMax.toDouble(),
                  title: 'Tools',
                  onToggle: () => setState(() => _rightOpen = !_rightOpen),
                  onResize: (w) => setState(() => _rightWidth = w),
                  // Leave a strip at the bottom for the floating theme
                  // switcher so it never sits on top of panel content.
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 52),
                    child: ToolsPanel(
                      currentStyle: _style,
                      sources: _sources,
                      onSourcesFound: (list) => setState(() => _sources = list),
                      onInsertText: _insertIntoBody,
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: 16,
              bottom: 16,
              child: OctoBotLauncher(essayContext: () => _bodyText),
            ),
          ],
        ),
      ),
    );
  }

  void _setZoom(double v) => setState(() => _zoomOverride = v.clamp(0.4, 2.0));

  /// The body prose editor — non-scrollable so it grows the page as you type
  /// (the page column scrolls). Uses the active style's paper metrics (font
  /// size + line spacing).
  Widget _bodyEditor(TextStyle paperStyle) {
    return QuillEditor(
      controller: _body,
      focusNode: _bodyFocus,
      scrollController: _bodyScroll,
      config: QuillEditorConfig(
        scrollable: false,
        expands: false,
        autoFocus: false,
        placeholder: 'Start writing your paper…',
        padding: EdgeInsets.zero,
        customStyles: DefaultStyles(
          paragraph: DefaultTextBlockStyle(
            paperStyle,
            const HorizontalSpacing(0, 0),
            const VerticalSpacing(0, 0),
            const VerticalSpacing(0, 0),
            null,
          ),
          placeHolder: DefaultTextBlockStyle(
            paperStyle.copyWith(color: const Color(0xFFB4B8BE)),
            const HorizontalSpacing(0, 0),
            const VerticalSpacing(0, 0),
            const VerticalSpacing(0, 0),
            null,
          ),
        ),
      ),
    );
  }

  // ── Saving: serialize the whole document to the essays store ──────────────
  int get _computedWordCount {
    final t = _bodyText.trim();
    if (t.isEmpty) return 0;
    return t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }

  /// The saved `documents.state` (JSONB). Besides the editor fields it carries
  /// the document's session — topic, Hein analysis, Lily outlines, sources —
  /// under the same keys the web app uses, so reopening restores all of it.
  String _docStateJson() => jsonEncode({
    'v': 2,
    'style': _style.name,
    'docTitle': _docTitle.text,
    'title': _title.text,
    'abstract': _abstract.text,
    'keywords': _keywords.text,
    'fields': {for (final e in _fields.entries) e.key.name: e.value.text},
    'body': _bodyText, // plain text — also feeds the server-side preview
    'delta': _body.document.toDelta().toJson(), // rich body (bold, lists…)
    'onboardingTopic': WizardSession.prompt,
    'analyzedTopic': WizardSession.searchTopic,
    'assignmentAnalysis': WizardSession.analysis?.toJson(),
    'outlines': WizardSession.outlines.map((o) => o.toJson()).toList(),
    'sources': _sources
        .map(
          (s) => {
            'url': s.url,
            'title': s.title,
            'author': s.author,
            'publishedYear': s.publishedYear,
            'publisher': s.publisher,
            'fullContent': s.fullContent,
          },
        )
        .toList(),
  });

  void _restore(String json) {
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      _style = FormatStyle.values.firstWhere(
        (s) => s.name == m['style'],
        orElse: () => _style,
      );
      _docTitle.text = (m['docTitle'] ?? _docTitle.text) as String;
      _title.text = (m['title'] ?? '') as String;
      // Older docs were named only in the doc bar — that name is the essay title.
      if (_title.text.trim().isEmpty &&
          _docTitle.text.trim() != 'Untitled document') {
        _title.text = _docTitle.text;
      }
      _abstract.text = (m['abstract'] ?? '') as String;
      _keywords.text = (m['keywords'] ?? '') as String;
      final f = m['fields'] as Map<String, dynamic>?;
      if (f != null) {
        for (final k in DocFieldKind.values) {
          final v = f[k.name];
          if (v is String) _fields[k]!.text = v;
        }
      }
      final delta = m['delta'] as List?;
      final body = (m['body'] ?? '') as String;
      if (delta != null && delta.isNotEmpty) {
        _body.document = Document.fromJson(delta);
      } else if (body.isNotEmpty) {
        _body.document.insert(0, body);
      }
      // `sourceResults` = sources of a document saved by the web app.
      final srcs = (m['sources'] ?? m['sourceResults']) as List?;
      if (srcs != null && srcs.isNotEmpty) {
        _sources = srcs
            .map((s) => Source.fromJson(s as Map<String, dynamic>))
            .toList();
      }
      _restoreSession(m);
    } catch (_) {
      // Corrupt/older payload — start from a blank doc rather than crashing.
      WizardSession.clear();
    }
  }

  /// This document's topic / analysis / outlines become the live session the
  /// Outline + Tools panels read. Docs saved before this existed have none, so
  /// the session clears instead of showing the previous document's analysis.
  void _restoreSession(Map<String, dynamic> m) {
    final a = m['assignmentAnalysis'];
    final outlines = m['outlines'] as List?;
    WizardSession.restore(
      prompt: (m['onboardingTopic'] ?? m['analyzedTopic'] ?? '') as String,
      analysis: a is Map<String, dynamic> ? HeinAnalysis.fromJson(a) : null,
      outlines: [
        for (final o in outlines ?? const [])
          if (o is Map<String, dynamic>) OutlineData.fromJson(o),
      ],
    );
  }

  /// Writes the document to the signed-in user's saved documents. Manual
  /// (Save button) always writes and toasts; [silent] (autosave / leaving)
  /// only writes when something changed and stays quiet.
  Future<void> _save({bool silent = false}) async {
    if (_saving) return;
    final svc = widget.essays ?? createEssaysService();
    if (svc == null) {
      if (!silent) _toast('Saving needs the backend.');
      return;
    }
    final snap = _snapshot();
    if (silent && (snap == _lastSaved || (_savedId == null && _isBlank))) {
      return;
    }
    // Signed out → nothing to save to (documents belong to a user).
    final token = await svc.token?.call();
    if (token == null || token.isEmpty) {
      if (!silent) _toast('Sign in to save your document.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _saving = true;
      _saveStatus = 'Saving…';
    });
    try {
      final saved = await svc.save(
        id: _docId,
        title: _saveTitle,
        content: _docStateJson(),
        wordCount: _computedWordCount,
        citationStyle: _style.name,
      );
      _savedId = saved.id;
      _lastSaved = snap;
      _saveStatus = 'Saved';
      if (!silent) _toast('Saved ✓');
    } catch (e) {
      _saveStatus = 'Not saved';
      if (!silent) {
        final s = e.toString();
        _toast(
          s.contains('no account') || s.contains(signInRequired)
              ? 'Sign in to save your document.'
              : 'Save failed: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(seconds: 2)),
    );
  }

  // ── Insert text (a quote and/or in-text citation) at the body cursor ──────
  void _insertIntoBody(String text) {
    final docLen = _body.document.length; // includes the trailing '\n'
    final sel = _body.selection;
    final base = sel.isValid ? sel.baseOffset : docLen - 1;
    final index = base.clamp(0, docLen - 1);
    final len = (sel.isValid && !sel.isCollapsed)
        ? (sel.extentOffset - sel.baseOffset).abs()
        : 0;
    _body.replaceText(
      index,
      len,
      text,
      TextSelection.collapsed(offset: index + text.length),
    );
    _bodyFocus.requestFocus();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Inserted ✓'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  // ── Finish: export the current document to PDF in the active style ────────
  Future<void> _exportPdf() async {
    setState(() => _exporting = true);
    try {
      final input = DocPdf.inputFrom(
        style: _style,
        title: _title.text,
        studentName: _fields[DocFieldKind.studentName]!.text,
        institution: _fields[DocFieldKind.institutionName]!.text,
        course: _fields[DocFieldKind.courseName]!.text,
        instructor: _fields[DocFieldKind.instructorName]!.text,
        date: _fields[DocFieldKind.date]!.text,
        abstractText: _abstract.text,
        keywords: _keywords.text,
        bodyText: _bodyText,
        sources: _sources,
      );
      await DocPdf.exportAndShare(
        input: input,
        style: _style,
        docName: _docTitle.text,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('PDF export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ── Document bar: menu · title · Finish ──────────────────────────────────
  Widget _docBar(ThemeData theme, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CockpitSpacing.md,
        CockpitSpacing.sm,
        CockpitSpacing.md,
        0,
      ),
      child: Row(
        children: [
          if (widget.onBack != null)
            _tapIcon(
              Icons.chevron_left_rounded,
              scheme.onSurfaceVariant,
              _leave,
            ),
          Icon(Icons.notes_rounded, size: 18, color: scheme.primary),
          const SizedBox(width: CockpitSpacing.sm),
          Expanded(
            child: TextField(
              controller: _docTitle,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              cursorColor: scheme.primary,
              decoration: const InputDecoration.collapsed(hintText: 'Document'),
            ),
          ),
          if (_saveStatus.isNotEmpty) ...[
            const SizedBox(width: CockpitSpacing.sm),
            Text(
              _saveStatus,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(width: CockpitSpacing.sm),
          const AuthChip(),
          const SizedBox(width: CockpitSpacing.sm),
          DocButton(
            label: _saving ? 'Saving…' : 'Save',
            icon: Icons.bookmark_border_rounded,
            busy: _saving,
            onTap: _save,
          ),
          const SizedBox(width: CockpitSpacing.sm),
          DocButton(
            kind: DocButtonKind.primary,
            label: _exporting ? 'Exporting…' : 'Finish',
            icon: Icons.download_rounded,
            busy: _exporting,
            onTap: _exportPdf,
          ),
        ],
      ),
    );
  }

  /// A compact (32px) tappable icon — no 48px default tap target.
  Widget _tapIcon(
    IconData i,
    Color color,
    VoidCallback onTap, {
    double size = 18,
  }) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(i, size: size),
        color: color,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        splashRadius: 18,
      ),
    );
  }

  // ── Style row: STYLE pills · Format ──────────────────────────────────────
  Widget _styleRow(ThemeData theme, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CockpitSpacing.md,
        CockpitSpacing.xs,
        CockpitSpacing.md,
        CockpitSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text(
                    'STYLE',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: CockpitSpacing.md),
                  for (final s in FormatStyle.values) ...[
                    _StylePill(
                      style: s,
                      selected: _style == s,
                      onTap: () => setState(() => _style = s),
                    ),
                    const SizedBox(width: CockpitSpacing.xs),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          DocButton(
            kind: DocButtonKind.tonal,
            label: 'Format',
            icon: Icons.refresh_rounded,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  // ── Formatting toolbar (quill-wired) + zoom cluster ──────────────────────
  Widget _formatToolbar(ColorScheme scheme, double zoom) {
    Widget zoomBtn(IconData i, VoidCallback onTap) =>
        _tapIcon(i, scheme.onSurfaceVariant, onTap, size: 16);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.xs),
      child: Row(
        children: [
          Expanded(child: EditorToolbar(controller: _body)),
          const SizedBox(width: CockpitSpacing.sm),
          zoomBtn(Icons.remove_rounded, () => _setZoom(zoom - 0.1)),
          GestureDetector(
            onTap: () => setState(() => _zoomOverride = null), // reset to fit
            child: SizedBox(
              width: 44,
              child: Text(
                '${(zoom * 100).round()}%',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ),
          ),
          zoomBtn(Icons.add_rounded, () => _setZoom(zoom + 0.1)),
        ],
      ),
    );
  }

  // ── Status bar ───────────────────────────────────────────────────────────
  Widget _statusBar(ThemeData theme, ColorScheme scheme) {
    final s = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CockpitSpacing.lg,
        vertical: CockpitSpacing.sm,
      ),
      child: Row(
        children: [
          Text('$_words words', style: s),
          const SizedBox(width: CockpitSpacing.md),
          Text('$_chars characters', style: s),
          const SizedBox(width: CockpitSpacing.md),
          Text('Editing', style: s),
          const Spacer(),
          Text('Zoom: 100%', style: s),
        ],
      ),
    );
  }
}

class _StylePill extends StatelessWidget {
  const _StylePill({
    required this.style,
    required this.selected,
    required this.onTap,
  });
  final FormatStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Pressable(
      child: Material(
        color: selected
            ? style.color.withValues(alpha: 0.14)
            : scheme.onSurface.withValues(alpha: 0.03),
        shape: StadiumBorder(
          side: BorderSide(
            color: selected
                ? style.color.withValues(alpha: 0.55)
                : scheme.onSurface.withValues(alpha: 0.08),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StyleMonogram(style, size: 17, active: selected),
                const SizedBox(width: 7),
                Text(
                  style.short,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: selected
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
