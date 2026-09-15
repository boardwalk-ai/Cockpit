import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../application/sources.dart';
import '../../domain/source.dart';
import '../../theme/doc_tokens.dart';
import '../widgets/doc_scaffold.dart';
import 'doc_model.dart';
import 'editor_panels.dart';
import 'editor_toolbar.dart';
import 'format_spec.dart';
import 'paged_document.dart';
import 'tools_panel.dart';

/// The central editor — Doc Oct's web editor, restyled borderless. The paper is
/// the one light element (a real page); the chrome is flat charcoal. The style
/// pills re-project the *same* semantic fields, so switching APA↔MLA reflows
/// without touching content.
class EditorPage extends StatefulWidget {
  const EditorPage({super.key, this.initialStyle = FormatStyle.apa, this.onBack});

  final FormatStyle initialStyle;
  final VoidCallback? onBack;

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

  final _docTitle = TextEditingController(text: 'Untitled document');
  final _title = TextEditingController();
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

  // Researched sources feeding the references page. Seam: replaced by our
  // backend (frontend never calls the scraper/AI directly). Mock for now.
  final List<Source> _sources = mockSources;

  // The body prose — flutter_quill (EditableText underneath → works on web).
  final QuillController _body = QuillController.basic();
  final FocusNode _bodyFocus = FocusNode();
  final ScrollController _bodyScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    for (final c in _all) {
      c.addListener(_onChanged);
    }
    _body.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
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

  int get _words => [
        ..._all.map((c) => c.text),
        _bodyText,
      ]
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
    final panelMax = (MediaQuery.sizeOf(context).width / 2 - 40).clamp(240, 720);

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
                            vertical: CockpitSpacing.md),
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
        child: Row(
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
              child: const OutlinePanel(),
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
              child: const ToolsPanel(),
            ),
          ],
        ),
      ),
    );
  }

  void _setZoom(double v) =>
      setState(() => _zoomOverride = v.clamp(0.4, 2.0));

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

  // ── Document bar: menu · title · Finish ──────────────────────────────────
  Widget _docBar(ThemeData theme, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          CockpitSpacing.md, CockpitSpacing.sm, CockpitSpacing.md, 0),
      child: Row(
        children: [
          if (widget.onBack != null)
            _tapIcon(Icons.chevron_left_rounded, scheme.onSurfaceVariant,
                widget.onBack!),
          Icon(Icons.notes_rounded, size: 18, color: scheme.primary),
          const SizedBox(width: CockpitSpacing.sm),
          SizedBox(
            width: 240,
            child: TextField(
              controller: _docTitle,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
              cursorColor: scheme.primary,
              decoration: const InputDecoration.collapsed(hintText: 'Document'),
            ),
          ),
          const Spacer(),
          _RedPill(
            icon: Icons.download_rounded,
            label: 'Finish',
            onTap: () {},
          ),
        ],
      ),
    );
  }

  /// A compact (32px) tappable icon — no 48px default tap target.
  Widget _tapIcon(IconData i, Color color, VoidCallback onTap, {double size = 18}) {
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
      padding: const EdgeInsets.fromLTRB(CockpitSpacing.md, CockpitSpacing.xs,
          CockpitSpacing.md, CockpitSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text('STYLE',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w700,
                      )),
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
          _RedPill(icon: Icons.refresh_rounded, label: 'Format', onTap: () {}),
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
              child: Text('${(zoom * 100).round()}%',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
            ),
          ),
          zoomBtn(Icons.add_rounded, () => _setZoom(zoom + 0.1)),
        ],
      ),
    );
  }

  // ── Status bar ───────────────────────────────────────────────────────────
  Widget _statusBar(ThemeData theme, ColorScheme scheme) {
    final s = theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.lg, vertical: CockpitSpacing.sm),
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
  const _StylePill(
      {required this.style, required this.selected, required this.onTap});
  final FormatStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: selected
          ? style.color.withValues(alpha: 0.18)
          : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: CockpitSpacing.md, vertical: CockpitSpacing.xs),
          child: Text(
            style.short,
            style: theme.textTheme.labelMedium?.copyWith(
              color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _RedPill extends StatelessWidget {
  const _RedPill(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary,
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: CockpitSpacing.md, vertical: CockpitSpacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: Colors.white),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
