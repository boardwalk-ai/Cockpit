import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/backend_config.dart';
import '../../application/tools_service.dart';
import '../../application/wizard_session.dart';
import '../../domain/citation_templates.dart';
import '../../domain/lookup_result.dart';
import '../../domain/source.dart';
import '../../theme/doc_tokens.dart';
import '../widgets/doc_button.dart';
import '../widgets/doc_widgets.dart';
import '../widgets/motion.dart';
import '../widgets/reveal.dart';
import 'source_modal.dart';

/// The right-panel Tools — Citations · Source · Paraphraser · Dictionary ·
/// Thesaurus, mirroring the web editor (each with its own sub-tabs). Citations
/// are deterministic (on-device via [CitationTemplates]); the rest read a
/// [ToolsService] whose live results arrive from our backend (sample for now).
class ToolsPanel extends StatefulWidget {
  const ToolsPanel({
    super.key,
    this.currentStyle = FormatStyle.mla,
    this.sources = const [],
    this.onSourcesFound,
    this.onInsertText,
  });

  /// The essay's active citation style — flags the "current" format pill.
  final FormatStyle currentStyle;

  /// The document's current sources (so the in-text citation index matches the
  /// references order). Search results replace this via [onSourcesFound].
  final List<Source> sources;

  /// Called when a source search returns — the editor adopts the results as the
  /// document's sources (references + in-text index follow them).
  final void Function(List<Source>)? onSourcesFound;

  /// Inserts [text] (a quote and/or an in-text citation) at the body cursor.
  final void Function(String text)? onInsertText;

  @override
  State<ToolsPanel> createState() => _ToolsPanelState();
}

enum _Tab { citations, source, paraphraser, dictionary, thesaurus }

class _ToolsPanelState extends State<ToolsPanel> {
  final ToolsService _tools =
      createToolsService(); // mock, or backend via --dart-define

  _Tab _tab = _Tab.citations;

  // Citations
  int _citMode = 0; // 0 = Manual, 1 = Auto
  final _citAuthor = TextEditingController();
  final _citTitle = TextEditingController();
  final _citPublisher = TextEditingController();
  final _citYear = TextEditingController();
  final _citContent = TextEditingController();
  final _citUrl = TextEditingController();
  FormatStyle _citStyle = FormatStyle.mla;
  String? _citInText, _citBib;

  // Source
  int _sourceSub = 0; // Auto Search / Keyword / Intelligence / Uploads
  /// Panel-wide Auto Humanize — the default for every source modal.
  bool _autoHumanize = false;

  /// Per-source overrides set inside a modal (key = source url/title) and the
  /// humanized text already fetched for a source.
  final Map<String, bool> _humanizeFor = {};
  final Map<String, String> _humanizedText = {};

  String _sourceKey(Source s) => s.url.isNotEmpty ? s.url : s.title;
  final _sourceKeyword = TextEditingController();

  // Lookups
  final _dictInput = TextEditingController();
  final _thesInput = TextEditingController();
  final _paraInput = TextEditingController();

  DictResult? _dict;
  ThesResult? _thes;
  List<Source>? _sources;
  String _paraOut = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _citStyle = widget.currentStyle;
    final stored = WizardSession.searchTopic;
    if (stored.isNotEmpty) _sourceKeyword.text = stored;
  }

  @override
  void dispose() {
    for (final c in [
      _citAuthor,
      _citTitle,
      _citPublisher,
      _citYear,
      _citContent,
      _citUrl,
      _sourceKeyword,
      _dictInput,
      _thesInput,
      _paraInput,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tabBar(context),
        Expanded(child: _body(context)),
      ],
    );
  }

  // ── top tab bar ──────────────────────────────────────────────────────────────
  Widget _tabBar(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.sm),
      child: Row(
        children: [
          for (final t in _Tab.values)
            Pressable(
              pressedScale: 0.9,
              child: GestureDetector(
                onTap: () => setState(() => _tab = t),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CockpitSpacing.sm,
                    vertical: CockpitSpacing.sm,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _label(t),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: _tab == t
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // The active-tab underline grows in / shrinks out.
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutBack,
                        height: 2,
                        width: _tab == t ? 22 : 0,
                        decoration: BoxDecoration(
                          color: _tab == t
                              ? scheme.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _label(_Tab t) => switch (t) {
    _Tab.citations => 'Citations',
    _Tab.source => 'Source',
    _Tab.paraphraser => 'Paraphraser',
    _Tab.dictionary => 'Dictionary',
    _Tab.thesaurus => 'Thesaurus',
  };

  Widget _body(BuildContext context) => switch (_tab) {
    _Tab.citations => _citationsTab(context),
    _Tab.source => _sourceTab(context),
    _Tab.paraphraser => _paraphraserTab(context),
    _Tab.dictionary => _dictionaryTab(context),
    _Tab.thesaurus => _thesaurusTab(context),
  };

  // ══════════════ CITATIONS (Manual / Auto) ══════════════
  Widget _citationsTab(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.all(CockpitSpacing.md),
      children: [
        _segmented(
          const ['Manual', 'Auto'],
          _citMode,
          (i) => setState(() => _citMode = i),
        ),
        const SizedBox(height: CockpitSpacing.lg),
        if (_citMode == 0) ...[
          _field(_citAuthor, 'Author name', 'e.g. John Smith'),
          _field(_citPublisher, 'Publisher name', 'e.g. Penguin Books'),
          _field(_citYear, 'Published year', 'e.g. 2023'),
          _fieldMultiline(
            _citContent,
            'Full content (helps AI)',
            'Paste a summary or excerpt…',
          ),
          const SizedBox(height: CockpitSpacing.md),
          const Eyebrow('Which format?'),
          const SizedBox(height: CockpitSpacing.sm),
          _formatPicker(),
          const SizedBox(height: CockpitSpacing.lg),
          _RedButton(label: 'Generate Citation', onTap: _generateManual),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _citUrl,
                  style: theme.textTheme.bodyMedium,
                  cursorColor: scheme.primary,
                  onSubmitted: (_) => _scrapeUrl(),
                  decoration: _dec('Paste a URL to cite…', scheme),
                ),
              ),
              const SizedBox(width: CockpitSpacing.xs),
              _RedButton(label: 'Scrape', compact: true, onTap: _scrapeUrl),
            ],
          ),
          if (_tools.isMock) ...[
            const SizedBox(height: CockpitSpacing.sm),
            _sampleBanner(context),
          ],
        ],
        const SizedBox(height: CockpitSpacing.xl),
        const Eyebrow('Bibliography'),
        const SizedBox(height: CockpitSpacing.sm),
        if (_citBib != null) ...[
          _resultBlock(context, 'In-text', _citInText!),
          const SizedBox(height: CockpitSpacing.sm),
          _resultBlock(context, 'Reference', _citBib!),
        ] else
          Text(
            _citMode == 1
                ? 'Scrape a URL above to generate citations.'
                : 'Fill in the form above to generate a citation.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  Widget _formatPicker() {
    return Wrap(
      spacing: CockpitSpacing.xs,
      runSpacing: CockpitSpacing.xs,
      children: [
        for (final s in FormatStyle.values)
          _FormatPill(
            style: s,
            selected: _citStyle == s,
            isCurrent: s == widget.currentStyle,
            onTap: () => setState(() {
              _citStyle = s;
              if (_citBib != null) _generateManual();
            }),
          ),
      ],
    );
  }

  Source get _manualSource => Source(
    url: '',
    title: _citTitle.text,
    author: _citAuthor.text,
    publishedYear: _citYear.text,
    publisher: _citPublisher.text,
  );

  void _generateManual() {
    final s = _manualSource;
    setState(() {
      _citInText = CitationTemplates.inText(_citStyle, s, 1);
      _citBib = CitationTemplates.reference(_citStyle, s, 1);
    });
  }

  void _scrapeUrl() {
    final host = Uri.tryParse(
      _citUrl.text.trim(),
    )?.host.replaceFirst('www.', '');
    if (host == null || host.isEmpty) return;
    // Mock scrape → a Source from the URL; backend does the real scrape.
    final s = Source(
      url: _citUrl.text.trim(),
      title: 'Article from $host',
      author: null,
      publishedYear: DateTime.now().year.toString(),
      publisher: host,
    );
    setState(() {
      _citInText = CitationTemplates.inText(_citStyle, s, 1);
      _citBib = CitationTemplates.reference(_citStyle, s, 1);
    });
  }

  // ══════════════ SOURCE (Auto / Keyword / Intelligence / Uploads) ══════════════
  Widget _sourceTab(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(CockpitSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _segmented(
                const ['Auto Search', 'Keyword', 'Intelligence', 'Uploads'],
                _sourceSub,
                (i) => setState(() => _sourceSub = i),
              ),
              const SizedBox(height: CockpitSpacing.sm),
              _humanizeToggle(),
            ],
          ),
        ),
        Expanded(child: _sourceSubBody(context, theme, scheme)),
      ],
    );
  }

  Widget _humanizeToggle() {
    const teal = Color(0xFF0D9488);
    final on = _autoHumanize;
    return Pressable(
      pressedScale: 0.95,
      child: GestureDetector(
        // The panel switch sets every source; per-source modal choices reset.
        onTap: () => setState(() {
          _autoHumanize = !on;
          _humanizeFor.clear();
        }),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: CockpitSpacing.sm,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            color: on ? teal.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(CockpitRadii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: on
                      ? teal
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Auto Humanize',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: on
                      ? teal
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sourceSubBody(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    switch (_sourceSub) {
      case 3: // Uploads
        return _uploadsBody(context, theme, scheme);
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CockpitSpacing.md,
                0,
                CockpitSpacing.md,
                CockpitSpacing.md,
              ),
              child: _sourceInputArea(context, theme, scheme),
            ),
            if (_tools.isMock) _sampleBanner(context),
            Expanded(
              child: _sources == null
                  ? _idle(
                      context,
                      Icons.travel_explore_rounded,
                      _sourceSub == 2
                          ? 'Select text in your essay above'
                          : 'Search a topic to find sources',
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                        CockpitSpacing.md,
                        0,
                        CockpitSpacing.md,
                        CockpitSpacing.md,
                      ),
                      children: [
                        for (var i = 0; i < _sources!.length; i++)
                          Reveal(
                            delay: Duration(milliseconds: 50 * i),
                            child: _sourceCard(context, _sources![i], i),
                          ),
                      ],
                    ),
            ),
          ],
        );
    }
  }

  Widget _sourceInputArea(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    void search() => _run(() async {
      final query = _sourceKeyword.text.trim().isNotEmpty
          ? _sourceKeyword.text.trim()
          : WizardSession.searchTopic;
      if (query.isEmpty) return;
      if (_sourceKeyword.text.trim().isEmpty) {
        _sourceKeyword.text = query;
      }
      final r = await _tools.searchSources(query);
      if (mounted) {
        setState(() => _sources = r);
        widget.onSourcesFound?.call(r);
      }
    });
    switch (_sourceSub) {
      case 0: // Auto Search
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              WizardSession.searchTopic.isEmpty
                  ? 'Uses the essay topic from setup, or type a keyword '
                        'in the Keyword tab.'
                  : 'Searches sources for “${WizardSession.searchTopic}” '
                        '(saved from your essay topic).',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: CockpitSpacing.sm),
            _RedButton(
              label: _loading ? 'Searching…' : 'Auto Search',
              onTap: search,
            ),
          ],
        );
      case 1: // Keyword
        return _searchBar(_sourceKeyword, 'Search for sources…', search);
      case 2: // Intelligence
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Select any text in your essay to find supporting sources.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: CockpitSpacing.sm),
            DocSurface(
              padding: const EdgeInsets.all(CockpitSpacing.md),
              child: Text(
                'Highlight text in your essay…',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: CockpitSpacing.sm),
            _RedButton(
              label: 'Search for sources',
              outline: true,
              onTap: search,
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _uploadsBody(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CockpitSpacing.md,
            0,
            CockpitSpacing.md,
            CockpitSpacing.md,
          ),
          child: Material(
            color: scheme.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(CockpitRadii.pill),
            child: InkWell(
              onTap: () {},
              borderRadius: BorderRadius.circular(CockpitRadii.pill),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: CockpitSpacing.md,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.upload_rounded, size: 15, color: scheme.primary),
                    const SizedBox(width: CockpitSpacing.xs),
                    Text(
                      'Upload File',
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: CockpitSpacing.xs),
                    Text(
                      'PDF · IMG',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: _idle(
            context,
            Icons.description_outlined,
            'Upload a PDF or image to cite it',
          ),
        ),
      ],
    );
  }

  Widget _sourceCard(BuildContext context, Source s, int index) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final meta = [
      if (s.author?.isNotEmpty == true) s.author!.split(',').first.trim(),
      if (s.publishedYear?.isNotEmpty == true) s.publishedYear,
      if (s.publisher?.isNotEmpty == true) s.publisher,
    ].join(' · ');
    final domain = Uri.tryParse(s.url)?.host.replaceFirst('www.', '') ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: CockpitSpacing.sm),
      child: Pressable(
        pressedScale: 0.98,
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        child: DocSurface(
          padding: EdgeInsets.zero,
          child: InkWell(
            onTap: () => _openSourceModal(s, index),
            borderRadius: BorderRadius.circular(CockpitRadii.md),
            child: Padding(
              padding: const EdgeInsets.all(CockpitSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (domain.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      domain,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: CockpitSpacing.sm),
                  Row(
                    children: [
                      _miniAction('Quote', () => _openSourceModal(s, index)),
                      const SizedBox(width: CockpitSpacing.xs),
                      _miniAction('Cite', () => _insertCitation(s, index)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The in-text mark for source [index] (0-based) in the active style, e.g.
  /// MLA `(Smith)`, APA `(Smith, 2020)`, IEEE `[3]`.
  String _inTextFor(Source s, int index) =>
      CitationTemplates.inText(widget.currentStyle, s, index + 1);

  /// "Cite": drop just the in-text citation at the cursor.
  void _insertCitation(Source s, int index) =>
      widget.onInsertText?.call(_inTextFor(s, index));

  /// Opens the source modal — read the content, optionally humanize it, select a
  /// passage, and insert it as a quote + in-text citation at the cursor.
  Future<void> _openSourceModal(Source s, int index) async {
    await showDocDialog<void>(
      context: context,
      builder: (dialogCtx) => SourceModal(
        source: s,
        inText: _inTextFor(s, index),
        humanize: (text) => _tools.paraphrase(text),
        canHumanize: !_tools.isMock,
        initialHumanize: _humanizeFor[_sourceKey(s)] ?? _autoHumanize,
        onHumanizeChanged: (on) => _humanizeFor[_sourceKey(s)] = on,
        cachedHumanized: _humanizedText[_sourceKey(s)],
        onHumanized: (text) => _humanizedText[_sourceKey(s)] = text,
        onInsert: (text) {
          widget.onInsertText?.call(text);
          Navigator.of(dialogCtx).pop();
        },
      ),
    );
  }

  // ══════════════ PARAPHRASER ══════════════
  Widget _paraphraserTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(CockpitSpacing.md),
      children: [
        const Eyebrow('Paraphraser'),
        const SizedBox(height: CockpitSpacing.sm),
        _multiline(_paraInput, 'Paste or type text to humanize…'),
        const SizedBox(height: CockpitSpacing.sm),
        _RedButton(
          label: _loading ? 'Humanizing…' : 'Humanize',
          onTap: () => _run(() async {
            final r = await _tools.paraphrase(_paraInput.text);
            if (mounted) setState(() => _paraOut = r);
          }),
        ),
        if (_tools.isMock) ...[
          const SizedBox(height: CockpitSpacing.sm),
          _sampleBanner(context),
        ],
        if (_paraOut.isNotEmpty) ...[
          const SizedBox(height: CockpitSpacing.md),
          _resultBlock(context, 'Result', _paraOut),
        ],
      ],
    );
  }

  // ══════════════ DICTIONARY ══════════════
  Widget _dictionaryTab(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(CockpitSpacing.md),
          child: _searchBar(_dictInput, 'Search a word…', () {
            _run(() async {
              final r = await _tools.dictionary(_dictInput.text);
              if (mounted) setState(() => _dict = r);
            });
          }),
        ),
        if (_tools.isMock) _sampleBanner(context),
        Expanded(
          child: _dict == null
              ? _idle(
                  context,
                  Icons.menu_book_rounded,
                  'Type a word and press search',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    CockpitSpacing.md,
                    0,
                    CockpitSpacing.md,
                    CockpitSpacing.md,
                  ),
                  children: [
                    Text(
                      _dict!.word,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (_dict!.phonetic != null)
                      Text(
                        _dict!.phonetic!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: CockpitSpacing.md),
                    for (final m in _dict!.meanings) ...[
                      DocChip(m.partOfSpeech, color: scheme.primary),
                      const SizedBox(height: CockpitSpacing.xs),
                      for (final d in m.definitions)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: CockpitSpacing.sm,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.definition,
                                style: theme.textTheme.bodyMedium,
                              ),
                              if (d.example != null)
                                Text(
                                  '“${d.example}”',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      const SizedBox(height: CockpitSpacing.sm),
                    ],
                    if (_dict!.synonyms.isNotEmpty) ...[
                      const Eyebrow('Synonyms'),
                      const SizedBox(height: CockpitSpacing.xs),
                      Wrap(
                        spacing: CockpitSpacing.xs,
                        runSpacing: CockpitSpacing.xs,
                        children: [for (final w in _dict!.synonyms) DocChip(w)],
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  // ══════════════ THESAURUS ══════════════
  Widget _thesaurusTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(CockpitSpacing.md),
          child: _searchBar(_thesInput, 'Search a word…', () {
            _run(() async {
              final r = await _tools.thesaurus(_thesInput.text);
              if (mounted) setState(() => _thes = r);
            });
          }),
        ),
        if (_tools.isMock) _sampleBanner(context),
        Expanded(
          child: _thes == null
              ? _idle(
                  context,
                  Icons.compare_arrows_rounded,
                  'Find synonyms and antonyms',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    CockpitSpacing.md,
                    0,
                    CockpitSpacing.md,
                    CockpitSpacing.md,
                  ),
                  children: [
                    const Eyebrow('Synonyms'),
                    const SizedBox(height: CockpitSpacing.xs),
                    Wrap(
                      spacing: CockpitSpacing.xs,
                      runSpacing: CockpitSpacing.xs,
                      children: [
                        for (final w in _thes!.synonyms) DocChip(w.word),
                      ],
                    ),
                    if (_thes!.antonyms.isNotEmpty) ...[
                      const SizedBox(height: CockpitSpacing.lg),
                      const Eyebrow('Antonyms'),
                      const SizedBox(height: CockpitSpacing.xs),
                      Wrap(
                        spacing: CockpitSpacing.xs,
                        runSpacing: CockpitSpacing.xs,
                        children: [
                          for (final w in _thes!.antonyms)
                            DocChip(
                              w.word,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  // ── shared pieces ────────────────────────────────────────────────────────────
  Widget _segmented(
    List<String> labels,
    int selected,
    ValueChanged<int> onTap,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Pressable(
                pressedScale: 0.94,
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: selected == i
                          ? scheme.surfaceContainerHighest
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(CockpitRadii.pill),
                    ),
                    child: Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: selected == i
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label, String hint) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: CockpitSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          TextField(
            controller: c,
            style: theme.textTheme.bodyMedium,
            cursorColor: scheme.primary,
            decoration: _dec(hint, scheme),
          ),
        ],
      ),
    );
  }

  Widget _fieldMultiline(TextEditingController c, String label, String hint) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: CockpitSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          _multiline(c, hint),
        ],
      ),
    );
  }

  Widget _multiline(TextEditingController c, String hint) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return TextField(
      controller: c,
      style: theme.textTheme.bodyMedium,
      cursorColor: scheme.primary,
      maxLines: 5,
      decoration: _dec(hint, scheme),
    );
  }

  Widget _searchBar(
    TextEditingController c,
    String hint,
    VoidCallback onSearch,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: c,
            style: Theme.of(context).textTheme.bodyMedium,
            cursorColor: scheme.primary,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSearch(),
            decoration: _dec(hint, scheme),
          ),
        ),
        const SizedBox(width: CockpitSpacing.xs),
        Material(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(CockpitRadii.md),
          child: InkWell(
            onTap: onSearch,
            borderRadius: BorderRadius.circular(CockpitRadii.md),
            child: const SizedBox(
              width: 38,
              height: 38,
              child: Icon(Icons.search_rounded, size: 18, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _dec(String hint, ColorScheme scheme) => InputDecoration(
    hintText: hint,
    isDense: true,
    filled: true,
    // A light fill + hairline edge that turns red on focus (as in the wizard).
    fillColor: scheme.onSurface.withValues(alpha: 0.04),
    hintStyle: TextStyle(
      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
      fontSize: 13,
    ),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: CockpitSpacing.md,
      vertical: 11,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(CockpitRadii.md),
      borderSide: BorderSide(color: scheme.onSurface.withValues(alpha: 0.08)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(CockpitRadii.md),
      borderSide: BorderSide(color: scheme.primary.withValues(alpha: 0.6)),
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(CockpitRadii.md),
      borderSide: BorderSide.none,
    ),
  );

  Widget _resultBlock(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DocSurface(
      padding: const EdgeInsets.all(CockpitSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Eyebrow(label)),
              InkWell(
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: value));
                  if (context.mounted) {
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      const SnackBar(
                        content: Text('Copied'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                },
                child: Icon(
                  Icons.copy_rounded,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.xs),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _miniAction(String label, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CockpitRadii.pill),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CockpitSpacing.md,
              vertical: 4,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _idle(BuildContext context, IconData icon, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 30,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _sampleBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CockpitSpacing.md,
        0,
        CockpitSpacing.md,
        CockpitSpacing.sm,
      ),
      child: Text(
        'Sample results — live tools arrive with the backend.',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

class _FormatPill extends StatelessWidget {
  const _FormatPill({
    required this.style,
    required this.selected,
    required this.isCurrent,
    required this.onTap,
  });
  final FormatStyle style;
  final bool selected;

  /// The document's own style — marked with a small dot.
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Pressable(
      child: Tooltip(
        message: isCurrent ? "Your document's style" : '',
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
              padding: const EdgeInsets.fromLTRB(5, 5, 11, 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StyleMonogram(style, size: 17, active: selected),
                  const SizedBox(width: 7),
                  Text(
                    style.short,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                  if (isCurrent) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RedButton extends StatelessWidget {
  const _RedButton({
    required this.label,
    required this.onTap,
    this.compact = false,
    this.outline = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool compact;
  final bool outline;

  /// A panel action on the shared [DocButton]: full width and a touch taller
  /// unless [compact]; [outline] is the quieter tonal variant.
  @override
  Widget build(BuildContext context) => DocButton(
    label: label,
    onTap: onTap,
    kind: outline ? DocButtonKind.tonal : DocButtonKind.primary,
    expand: !compact,
    height: compact ? 36 : 40,
  );
}
