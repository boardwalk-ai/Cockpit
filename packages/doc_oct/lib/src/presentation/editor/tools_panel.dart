import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/tools_service.dart';
import '../../domain/citation_templates.dart';
import '../../domain/lookup_result.dart';
import '../../domain/source.dart';
import '../../theme/doc_tokens.dart';
import '../widgets/doc_widgets.dart';

/// The right-panel Tools — Citations · Source · Paraphraser · Dictionary ·
/// Thesaurus, mirroring the web editor. Citations are deterministic (on-device
/// via [CitationTemplates]); the rest read a [ToolsService] whose live results
/// arrive from our backend (mock/sample for now, flagged as such).
class ToolsPanel extends StatefulWidget {
  const ToolsPanel({super.key});

  @override
  State<ToolsPanel> createState() => _ToolsPanelState();
}

enum _Tab { citations, source, paraphraser, dictionary, thesaurus }

class _ToolsPanelState extends State<ToolsPanel> {
  // Seam: swap for a backend-backed service.
  final ToolsService _tools = const MockToolsService();

  _Tab _tab = _Tab.citations;

  // Citations (deterministic, on-device).
  final _citAuthor = TextEditingController();
  final _citTitle = TextEditingController();
  final _citPublisher = TextEditingController();
  final _citYear = TextEditingController();
  FormatStyle _citStyle = FormatStyle.mla;
  String? _citInText, _citBib;

  final _dictInput = TextEditingController();
  final _thesInput = TextEditingController();
  final _sourceInput = TextEditingController();
  final _paraInput = TextEditingController();

  DictResult? _dict;
  ThesResult? _thes;
  List<Source>? _sources;
  String _paraOut = '';
  bool _loading = false;

  @override
  void dispose() {
    for (final c in [
      _citAuthor,
      _citTitle,
      _citPublisher,
      _citYear,
      _dictInput,
      _thesInput,
      _sourceInput,
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

  // ── tab bar ────────────────────────────────────────────────────────────────
  Widget _tabBar(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.sm),
      child: Row(
        children: [
          for (final t in _Tab.values)
            GestureDetector(
              onTap: () => setState(() => _tab = t),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: CockpitSpacing.sm, vertical: CockpitSpacing.sm),
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
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 2,
                      width: 22,
                      decoration: BoxDecoration(
                        color: _tab == t ? scheme.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
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

  // ── Citations (on-device) ───────────────────────────────────────────────────
  Widget _citationsTab(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      children: [
        const Eyebrow('Citation'),
        const SizedBox(height: CockpitSpacing.md),
        _field(_citAuthor, 'Author name', 'e.g. Smith, John'),
        _field(_citPublisher, 'Publisher', 'e.g. Penguin Books'),
        _field(_citTitle, 'Title', 'e.g. A Study of Things'),
        _field(_citYear, 'Published year', 'e.g. 2023'),
        const SizedBox(height: CockpitSpacing.md),
        const Eyebrow('Format'),
        const SizedBox(height: CockpitSpacing.sm),
        Wrap(
          spacing: CockpitSpacing.xs,
          runSpacing: CockpitSpacing.xs,
          children: [
            for (final s in FormatStyle.values)
              _StylePill(
                label: s.short,
                color: s.color,
                selected: _citStyle == s,
                onTap: () => setState(() {
                  _citStyle = s;
                  if (_citBib != null) _generateCitation();
                }),
              ),
          ],
        ),
        const SizedBox(height: CockpitSpacing.lg),
        _RedButton(label: 'Generate Citation', onTap: _generateCitation),
        if (_citBib != null) ...[
          const SizedBox(height: CockpitSpacing.xl),
          _resultBlock(context, 'In-text', _citInText!),
          const SizedBox(height: CockpitSpacing.md),
          _resultBlock(context, 'Bibliography', _citBib!),
        ] else ...[
          const SizedBox(height: CockpitSpacing.lg),
          Text('Fill the form above to generate a citation.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ],
    );
  }

  void _generateCitation() {
    final s = Source(
      url: '',
      title: _citTitle.text,
      author: _citAuthor.text,
      publishedYear: _citYear.text,
      publisher: _citPublisher.text,
    );
    setState(() {
      _citInText = CitationTemplates.inText(_citStyle, s, 1);
      _citBib = CitationTemplates.reference(_citStyle, s, 1);
    });
  }

  // ── Source search ────────────────────────────────────────────────────────────
  Widget _sourceTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(CockpitSpacing.md),
          child: _searchBar(_sourceInput, 'Search academic sources…', () {
            _run(() async {
              final r = await _tools.searchSources(_sourceInput.text);
              if (mounted) setState(() => _sources = r);
            });
          }),
        ),
        if (_tools.isMock) _sampleBanner(context),
        Expanded(
          child: _sources == null
              ? _idle(context, Icons.travel_explore_rounded,
                  'Search a topic to find sources')
              : ListView(
                  padding: const EdgeInsets.fromLTRB(CockpitSpacing.md, 0,
                      CockpitSpacing.md, CockpitSpacing.md),
                  children: [
                    for (final s in _sources!) _sourceCard(context, s),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _sourceCard(BuildContext context, Source s) {
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
      child: DocSurface(
        padding: const EdgeInsets.all(CockpitSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(meta,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
            if (domain.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(domain,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
            const SizedBox(height: CockpitSpacing.sm),
            Row(
              children: [
                _miniAction('Quote', () {}),
                const SizedBox(width: CockpitSpacing.xs),
                _miniAction('Cite', () {}),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Paraphraser ──────────────────────────────────────────────────────────────
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

  // ── Dictionary ───────────────────────────────────────────────────────────────
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
              ? _idle(context, Icons.menu_book_rounded,
                  'Type a word and press search')
              : ListView(
                  padding: const EdgeInsets.fromLTRB(CockpitSpacing.md, 0,
                      CockpitSpacing.md, CockpitSpacing.md),
                  children: [
                    Text(_dict!.word,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    if (_dict!.phonetic != null)
                      Text(_dict!.phonetic!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: CockpitSpacing.md),
                    for (final m in _dict!.meanings) ...[
                      DocChip(m.partOfSpeech, color: scheme.primary),
                      const SizedBox(height: CockpitSpacing.xs),
                      for (final d in m.definitions)
                        Padding(
                          padding: const EdgeInsets.only(
                              bottom: CockpitSpacing.sm),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.definition,
                                  style: theme.textTheme.bodyMedium),
                              if (d.example != null)
                                Text('“${d.example}”',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                        fontStyle: FontStyle.italic)),
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
                        children: [
                          for (final w in _dict!.synonyms) DocChip(w),
                        ],
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  // ── Thesaurus ────────────────────────────────────────────────────────────────
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
              ? _idle(context, Icons.compare_arrows_rounded,
                  'Find synonyms and antonyms')
              : ListView(
                  padding: const EdgeInsets.fromLTRB(CockpitSpacing.md, 0,
                      CockpitSpacing.md, CockpitSpacing.md),
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
                            DocChip(w.word, color: Theme.of(context).colorScheme.primary),
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
  Widget _field(TextEditingController c, String label, String hint) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: CockpitSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
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
      TextEditingController c, String hint, VoidCallback onSearch) {
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
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: CockpitSpacing.md, vertical: CockpitSpacing.sm),
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
                          duration: Duration(seconds: 1)),
                    );
                  }
                },
                child: Icon(Icons.copy_rounded,
                    size: 15, color: scheme.onSurfaceVariant),
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
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: CockpitSpacing.md, vertical: 4),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant)),
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
          Icon(icon,
              size: 30, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(height: CockpitSpacing.sm),
          Text(text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _sampleBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          CockpitSpacing.md, 0, CockpitSpacing.md, CockpitSpacing.sm),
      child: Text(
        'Sample results — live tools arrive with the backend.',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
      ),
    );
  }
}

class _StylePill extends StatelessWidget {
  const _StylePill(
      {required this.label,
      required this.color,
      required this.selected,
      required this.onTap});
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? color.withValues(alpha: 0.18)
          : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: CockpitSpacing.md, vertical: CockpitSpacing.xs),
          child: Text(label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
              )),
        ),
      ),
    );
  }
}

class _RedButton extends StatelessWidget {
  const _RedButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary,
      borderRadius: BorderRadius.circular(CockpitRadii.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.md),
          child: Center(
            child: Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ),
        ),
      ),
    );
  }
}
