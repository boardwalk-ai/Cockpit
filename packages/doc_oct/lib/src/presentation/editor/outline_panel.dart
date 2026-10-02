import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';

import '../../application/hein_service.dart';
import '../../application/lily_service.dart';
import '../../application/wizard_session.dart';
import '../../domain/hein_analysis.dart';
import '../../domain/outline.dart';
import '../widgets/doc_widgets.dart';
import '../widgets/motion.dart';
import '../widgets/reveal.dart';

/// The left-panel Outline — generate a structured plan (Introduction / Body /
/// Conclusion cards with bullets) and drop any section into the essay. Mirrors
/// the web editor's outline cards (tag hue by section type).
class OutlinePanel extends StatefulWidget {
  const OutlinePanel({
    super.key,
    this.topic = '',
    this.onInsertText,
    this.onTopicSet,
    this.lily,
    this.hein,
  });

  /// The paper title typed in the editor — only pre-fills the topic prompt;
  /// generation always runs from a confirmed topic + Hein analysis.
  final String topic;

  /// Inserts an outline section (title + bullets) at the body cursor.
  final void Function(String text)? onInsertText;

  /// Called with Hein's topic once the user has given one in the editor.
  final void Function(String topic)? onTopicSet;

  /// Outline generator; defaults to the HTTP Lily service (injectable in tests).
  final LilyService? lily;

  /// Assignment analyzer; defaults to the HTTP Hein service.
  final HeinService? hein;

  @override
  State<OutlinePanel> createState() => _OutlinePanelState();
}

/// Modes that expand extra options (Auto Outline generates immediately).
enum _Mode { build, single }

class _OutlinePanelState extends State<OutlinePanel> {
  static const _types = ['Introduction', 'Body Paragraph', 'Conclusion'];

  late final LilyService _lily = widget.lily ?? createLilyService();
  late final HeinService _hein = widget.hein ?? createHeinService();
  final _buildTitle = TextEditingController();
  List<OutlineData>? _outlines;
  bool _loading = false;
  String? _error;

  /// What the spinner says while working (analysis vs. outline).
  String _status = 'Lily is writing your outline…';

  /// Expanded mode (Build My Way / One Paragraph show extra options).
  _Mode? _mode;
  String _buildType = _types.first;

  @override
  void initState() {
    super.initState();
    if (WizardSession.outlines.isNotEmpty) {
      _outlines = List.of(WizardSession.outlines);
    }
  }

  @override
  void dispose() {
    _buildTitle.dispose();
    super.dispose();
  }

  static const _writing = 'Lily is writing your outline…';

  /// Entering the editor via "Start writing" skips the wizard, so there is no
  /// topic yet. Ask for it (pre-filled with the paper title, if any); null =
  /// cancelled.
  Future<String?> _askTopic() async {
    final typed = widget.topic.trim();
    final topic = await showDocDialog<String>(
      context: context,
      builder: (_) =>
          _TopicDialog(initial: typed == 'Untitled document' ? '' : typed),
    );
    final t = topic?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  /// Outlines always come from a real topic: with no Hein analysis yet, ask for
  /// the topic, analyze it, then generate. Auto replaces the outline; Build My
  /// Way / One Paragraph append a section.
  Future<void> _generate(
    LilyMode mode, {
    String? requestedType,
    String? customTitle,
  }) async {
    if (_loading) return;
    String? newTopic;
    if (WizardSession.analysis == null) {
      newTopic = await _askTopic();
      if (newTopic == null || !mounted) return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _status = newTopic != null ? 'Octo is analyzing your topic…' : _writing;
    });
    try {
      var analysis = WizardSession.analysis;
      if (newTopic != null) {
        await WizardSession.savePrompt(newTopic); // also drops old outlines
        _outlines = null;
        analysis = await _hein.analyze(instructions: newTopic);
        await WizardSession.saveAnalysis(analysis);
        widget.onTopicSet?.call(WizardSession.searchTopic);
        if (!mounted) return;
        setState(() => _status = _writing);
      }
      final r = await _lily.generate(
        mode: mode,
        analysis: analysis,
        essayTopic: WizardSession.searchTopic,
        requestedType: requestedType,
        customTitle: customTitle,
      );
      final next = mode == LilyMode.auto ? r : [...?_outlines, ...r];
      await WizardSession.saveOutlines(next);
      if (mounted) {
        setState(() {
          _outlines = next;
          _mode = null;
          _buildTitle.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _build() {
    final title = _buildTitle.text.trim();
    if (title.isEmpty) return;
    _generate(LilyMode.build, requestedType: _buildType, customTitle: title);
  }

  void _toggle(_Mode m) => setState(() => _mode = _mode == m ? null : m);

  void _insert(OutlineData o) {
    final text = '${o.title}\n${o.bullets.map((b) => '• $b').join('\n')}\n';
    widget.onInsertText?.call(text);
  }

  Future<void> _remove(int i) async {
    setState(() => _outlines!.removeAt(i));
    await WizardSession.saveOutlines(_outlines ?? const []);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final analysis = WizardSession.analysis;
    final outlines = _outlines ?? const <OutlineData>[];
    final hasOutlines = outlines.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        CockpitSpacing.md,
        CockpitSpacing.sm,
        CockpitSpacing.md,
        CockpitSpacing.md,
      ),
      children: [
        if (analysis != null) _AnalysisCard(analysis: analysis),
        if (analysis != null) const SizedBox(height: CockpitSpacing.lg),
        Text(
          hasOutlines
              ? 'Your outline · ${outlines.length} '
                    'section${outlines.length == 1 ? '' : 's'}'
              : 'Build an outline',
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (!hasOutlines) ...[
          const SizedBox(height: CockpitSpacing.xs),
          Text(
            analysis == null
                ? 'Pick a mode — Octo will ask for your topic first, analyze '
                      'it, then Lily drafts the sections.'
                : 'Lily drafts sections from your topic. Pick a mode, or skip '
                      'and write freely.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: CockpitSpacing.sm),
        ..._modes(theme, scheme),
        if (_error != null) ...[
          const SizedBox(height: CockpitSpacing.sm),
          Text(
            _error!,
            style: theme.textTheme.labelSmall?.copyWith(color: scheme.error),
          ),
        ],
        const SizedBox(height: CockpitSpacing.sm),
        for (var i = 0; i < outlines.length; i++)
          Reveal(
            delay: Duration(milliseconds: 60 * i),
            child: _OutlineCard(
              outline: outlines[i],
              onInsert: () => _insert(outlines[i]),
              onRemove: () => _remove(i),
            ),
          ),
      ],
    );
  }

  /// Mode pills (Build My Way · Auto Outline · One Paragraph) plus the options
  /// of the expanded mode — mirrors the wizard's analysis step.
  List<Widget> _modes(ThemeData theme, ColorScheme scheme) {
    final idle = !_loading;
    return [
      Wrap(
        spacing: CockpitSpacing.xs,
        runSpacing: CockpitSpacing.xs,
        children: [
          _Pill(
            icon: Icons.add_rounded,
            label: 'Build My Way',
            selected: _mode == _Mode.build,
            onTap: idle ? () => _toggle(_Mode.build) : null,
          ),
          _Pill(
            icon: Icons.auto_awesome_rounded,
            label: _loading && _mode == null ? 'Generating…' : 'Auto Outline',
            selected: false,
            onTap: idle ? () => _generate(LilyMode.auto) : null,
          ),
          _Pill(
            icon: Icons.notes_rounded,
            label: 'One Paragraph',
            selected: _mode == _Mode.single,
            onTap: idle ? () => _toggle(_Mode.single) : null,
          ),
        ],
      ),
      if (_mode == _Mode.single) ...[
        const SizedBox(height: CockpitSpacing.md),
        _optionLabel(theme, scheme, 'Which paragraph?'),
        const SizedBox(height: CockpitSpacing.xs),
        Wrap(
          spacing: CockpitSpacing.xs,
          runSpacing: CockpitSpacing.xs,
          children: [
            for (final t in _types)
              _Pill(
                label: t,
                selected: false,
                onTap: idle
                    ? () => _generate(LilyMode.single, requestedType: t)
                    : null,
              ),
          ],
        ),
      ],
      if (_mode == _Mode.build) ...[
        const SizedBox(height: CockpitSpacing.md),
        _optionLabel(theme, scheme, 'Section type'),
        const SizedBox(height: CockpitSpacing.xs),
        Wrap(
          spacing: CockpitSpacing.xs,
          runSpacing: CockpitSpacing.xs,
          children: [
            for (final t in _types)
              _Pill(
                label: t,
                selected: _buildType == t,
                onTap: idle ? () => setState(() => _buildType = t) : null,
              ),
          ],
        ),
        const SizedBox(height: CockpitSpacing.sm),
        TextField(
          controller: _buildTitle,
          enabled: idle,
          style: theme.textTheme.bodySmall,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'What should this paragraph focus on?',
            filled: true,
            fillColor: scheme.surfaceContainerLow,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CockpitRadii.md),
              borderSide: BorderSide.none,
            ),
          ),
          onSubmitted: (_) => _build(),
        ),
        const SizedBox(height: CockpitSpacing.sm),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: idle ? _build : null,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            child: Text(_loading ? 'Building…' : 'Build paragraph'),
          ),
        ),
      ],
      if (_loading) ...[
        const SizedBox(height: CockpitSpacing.sm),
        Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: CockpitSpacing.sm),
            Expanded(
              child: Text(
                _status,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    ];
  }

  Widget _optionLabel(ThemeData theme, ColorScheme scheme, String text) => Text(
    text.toUpperCase(),
    style: theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      letterSpacing: 1.1,
      fontWeight: FontWeight.w700,
    ),
  );
}

/// Asks for the essay topic / assignment prompt before the first outline.
class _TopicDialog extends StatefulWidget {
  const _TopicDialog({required this.initial});

  final String initial;

  @override
  State<_TopicDialog> createState() => _TopicDialogState();
}

class _TopicDialogState extends State<_TopicDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    if (_c.text.trim().isEmpty) return;
    Navigator.of(context).pop(_c.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AlertDialog(
      title: const Text('What is your essay about?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your topic or paste the assignment prompt. Octo analyzes '
              'it first, then Lily builds the outline from that analysis.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: CockpitSpacing.md),
            TextField(
              controller: _c,
              autofocus: true,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'e.g. The importance of AI safety',
                filled: true,
                fillColor: scheme.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CockpitRadii.md),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ListenableBuilder(
          listenable: _c,
          builder: (context, _) => FilledButton.icon(
            onPressed: _c.text.trim().isEmpty ? null : _submit,
            icon: const Icon(Icons.auto_awesome_rounded, size: 16),
            label: const Text('Analyze & Generate'),
          ),
        ),
      ],
    );
  }
}

/// A compact rounded pill — used for the outline modes and their options.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    this.icon,
    this.onTap,
  });

  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Pressable(
      enabled: onTap != null,
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.14)
            : scheme.surfaceContainerLow,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected
                ? scheme.primary.withValues(alpha: 0.5)
                : scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 13, color: fg),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
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

class _AnalysisCard extends StatelessWidget {
  const _AnalysisCard({required this.analysis});

  final HeinAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fields = <(String, String)>[
      ('Topic', analysis.essayTopic),
      ('Essay type', analysis.essayType),
      ('Scope', analysis.scope),
      ('Structure', analysis.structure),
    ].where((e) => e.$2.trim().isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Analysis'),
        const SizedBox(height: CockpitSpacing.sm),
        DocSurface(
          padding: const EdgeInsets.all(CockpitSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (analysis.analysis.trim().isNotEmpty)
                Text(
                  analysis.analysis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              if (fields.isNotEmpty) ...[
                const SizedBox(height: CockpitSpacing.md),
                for (var i = 0; i < fields.length; i++) ...[
                  if (i > 0) const SizedBox(height: CockpitSpacing.sm),
                  Text(
                    fields[i].$1.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    fields[i].$2,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _OutlineCard extends StatelessWidget {
  const _OutlineCard({
    required this.outline,
    required this.onInsert,
    required this.onRemove,
  });

  final OutlineData outline;
  final VoidCallback onInsert;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hue = outline.tagColor;
    return Container(
      margin: const EdgeInsets.only(bottom: CockpitSpacing.sm),
      padding: const EdgeInsets.all(CockpitSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: hue.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(CockpitRadii.pill),
                ),
                child: Text(
                  outline.type.toUpperCase(),
                  style: TextStyle(
                    color: hue,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.close_rounded,
                    size: 15,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.xs),
          Text(
            outline.title,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (outline.description.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              outline.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: CockpitSpacing.sm),
          for (final b in outline.bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: hue,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      b,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: CockpitSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onInsert,
              icon: const Icon(Icons.add_rounded, size: 15),
              label: const Text('Insert into essay'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: scheme.primary,
                textStyle: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
