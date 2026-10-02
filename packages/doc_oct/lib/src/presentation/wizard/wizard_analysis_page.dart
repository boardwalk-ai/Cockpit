import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';

import '../../application/hein_service.dart';
import '../../application/lily_service.dart';
import '../../application/wizard_session.dart';
import '../../domain/hein_analysis.dart';
import '../../domain/outline.dart';
import '../../theme/doc_tokens.dart';
import '../widgets/doc_scaffold.dart';
import '../widgets/doc_top_bar.dart';
import '../widgets/doc_widgets.dart';
import '../widgets/motion.dart';
import '../widgets/reveal.dart';
import 'wizard_primary_button.dart';
import 'wizard_shell.dart';

/// Wizard · Step 3 (analysis). Runs Hein (`/api/hein/analyze`) on the prompt
/// and shows the real breakdown — not the Phase-1 placeholder copy.
class WizardAnalysisPage extends StatefulWidget {
  const WizardAnalysisPage({
    super.key,
    required this.topic,
    required this.style,
    this.onBack,
    this.onContinue,
    this.initialAnalysis,
    this.hein,
    this.lily,
  });

  final String topic;
  final FormatStyle style;
  final VoidCallback? onBack;
  final VoidCallback? onContinue;

  /// When set (tests / restore), skip the network call.
  final HeinAnalysis? initialAnalysis;
  final HeinService? hein;
  final LilyService? lily;

  @override
  State<WizardAnalysisPage> createState() => _WizardAnalysisPageState();
}

class _WizardAnalysisPageState extends State<WizardAnalysisPage> {
  /// `build` / `single` open their extra controls; auto runs immediately.
  String? _mode;
  late final HeinService _hein = widget.hein ?? createHeinService();
  late final LilyService _lily = widget.lily ?? createLilyService();

  HeinAnalysis? _result;
  String? _error;
  bool _loading = false;

  final _buildTitle = TextEditingController();
  String _buildType = 'Introduction';
  List<OutlineData> _outlines = [];
  bool _lilyLoading = false;
  String? _lilyError;

  static const _types = ['Introduction', 'Body Paragraph', 'Conclusion'];

  @override
  void initState() {
    super.initState();
    _result = widget.initialAnalysis;
    _outlines = List.of(WizardSession.outlines);
    if (_result == null) _runHein();
  }

  @override
  void dispose() {
    _buildTitle.dispose();
    super.dispose();
  }

  Future<void> _runHein() async {
    final instructions = widget.topic.trim();
    if (instructions.isEmpty) {
      setState(() => _error = 'Add an essay topic first.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _hein.analyze(instructions: instructions);
      await WizardSession.saveAnalysis(result);
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final result = _result;
    final displayTopic = result?.essayTopic.trim().isNotEmpty == true
        ? result!.essayTopic
        : (widget.topic.isEmpty ? 'your assignment prompt' : widget.topic);

    final fields = <(IconData, String, String)>[
      (Icons.lightbulb_outline_rounded, 'Topic', displayTopic),
      (
        Icons.category_outlined,
        'Essay type',
        result?.essayType.trim().isNotEmpty == true ? result!.essayType : '—',
      ),
      (
        Icons.center_focus_weak_rounded,
        'Scope',
        result?.scope.trim().isNotEmpty == true ? result!.scope : '—',
      ),
      (
        Icons.account_tree_outlined,
        'Structure',
        result?.structure.trim().isNotEmpty == true ? result!.structure : '—',
      ),
    ];

    final intro = MaskReveal(
      delay: kEntranceDelay,
      child: Text(
        _loading
            ? 'Octo is reading your prompt…'
            : 'Octo broke down your prompt. Review it, optionally generate an '
                  'outline, then start writing.',
        style: theme.textTheme.bodyLarge?.copyWith(
          color: scheme.onSurfaceVariant,
          height: 1.55,
        ),
      ),
    );
    final cta = WizardPrimaryButton(
      label: 'Continue to Editor',
      dense: true,
      onPressed: widget.onContinue,
    );
    final analysis = _loading
        ? _skeleton(scheme)
        : (_error != null && result == null)
        ? _errorCard(theme, scheme)
        : _breakdown(theme, scheme, result, fields);

    return DocScaffold(
      child: SafeArea(
        child: Column(
          children: [
            const DocOctTopBar(),
            Expanded(
              child: WizardShell(
                step: 3,
                scroll: true,
                wideContent: true,
                onBack: widget.onBack,
                eyebrow: 'Step three',
                headline: [
                  const TextSpan(text: 'Your assignment,'),
                  TextSpan(
                    text: 'decoded.',
                    style: TextStyle(color: scheme.primary),
                  ),
                ],
                child: LayoutBuilder(
                  builder: (context, box) {
                    // Wide: analysis on the left, outline on the right, the
                    // CTA up top where it's always in view. Narrow: one column.
                    if (box.maxWidth < 760) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          intro,
                          const SizedBox(height: CockpitSpacing.xl),
                          analysis,
                          if (!_loading) ...[
                            const SizedBox(height: CockpitSpacing.lg),
                            Align(alignment: Alignment.centerRight, child: cta),
                            const SizedBox(height: CockpitSpacing.xxl),
                            _outlineSection(theme, scheme),
                          ],
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: intro),
                            const SizedBox(width: CockpitSpacing.xl),
                            if (!_loading)
                              Reveal(
                                delay: const Duration(milliseconds: 700),
                                child: cta,
                              ),
                          ],
                        ),
                        const SizedBox(height: CockpitSpacing.xl),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 11, child: analysis),
                            const SizedBox(width: CockpitSpacing.lg),
                            Expanded(
                              flex: 10,
                              child: _loading
                                  ? _panel(
                                      scheme,
                                      const Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Shimmer(width: 120, height: 13),
                                          SizedBox(height: CockpitSpacing.sm),
                                          Shimmer(height: 9),
                                          SizedBox(height: CockpitSpacing.lg),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Shimmer(
                                                  height: 58,
                                                  radius: 12,
                                                ),
                                              ),
                                              SizedBox(
                                                width: CockpitSpacing.sm,
                                              ),
                                              Expanded(
                                                child: Shimmer(
                                                  height: 58,
                                                  radius: 12,
                                                ),
                                              ),
                                              SizedBox(
                                                width: CockpitSpacing.sm,
                                              ),
                                              Expanded(
                                                child: Shimmer(
                                                  height: 58,
                                                  radius: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    )
                                  : Reveal(
                                      delay: const Duration(milliseconds: 620),
                                      child: _panel(
                                        scheme,
                                        _outlineSection(theme, scheme),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A raised panel with a hairline edge (holds the outline column).
  Widget _panel(ColorScheme scheme, Widget child) => Container(
    padding: const EdgeInsets.all(CockpitSpacing.xl),
    decoration: BoxDecoration(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(CockpitRadii.lg),
      border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
    ),
    child: child,
  );

  /// While Octo reads the prompt: the breakdown's shape, shimmering.
  Widget _skeleton(ColorScheme scheme) {
    Widget tile() => Expanded(
      child: Container(
        padding: const EdgeInsets.all(CockpitSpacing.lg),
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(CockpitRadii.md),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Shimmer(width: 70, height: 9),
            SizedBox(height: CockpitSpacing.md),
            Shimmer(height: 10),
            SizedBox(height: CockpitSpacing.sm),
            Shimmer(width: 120, height: 10),
          ],
        ),
      ),
    );
    return _panel(
      scheme,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Shimmer(width: 110, height: 9),
          const SizedBox(height: CockpitSpacing.lg),
          for (final w in const [1.0, 1.0, 0.92, 0.6]) ...[
            FractionallySizedBox(widthFactor: w, child: const Shimmer()),
            const SizedBox(height: CockpitSpacing.sm),
          ],
          const SizedBox(height: CockpitSpacing.lg),
          Row(
            children: [
              tile(),
              const SizedBox(width: CockpitSpacing.md),
              tile(),
            ],
          ),
          const SizedBox(height: CockpitSpacing.md),
          Row(
            children: [
              tile(),
              const SizedBox(width: CockpitSpacing.md),
              tile(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _errorCard(ThemeData theme, ColorScheme scheme) {
    return DocSurface(
      padding: const EdgeInsets.all(CockpitSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hein couldn’t analyze this prompt.',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: CockpitSpacing.md),
          TextButton(onPressed: _runHein, child: const Text('Try again')),
        ],
      ),
    );
  }

  /// Octo's read of the prompt: the summary up top, then Topic · Essay type ·
  /// Scope · Structure as tiles — each entering in turn.
  Widget _breakdown(
    ThemeData theme,
    ColorScheme scheme,
    HeinAnalysis? result,
    List<(IconData, String, String)> fields,
  ) {
    Widget tile(int i) {
      final (icon, label, value) = fields[i];
      return Expanded(
        child: Reveal(
          delay: Duration(milliseconds: 420 + 90 * i),
          child: Container(
            padding: const EdgeInsets.all(CockpitSpacing.lg),
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(CockpitRadii.md),
              border: Border.all(
                color: scheme.onSurface.withValues(alpha: 0.06),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 15, color: scheme.primary),
                    const SizedBox(width: CockpitSpacing.sm),
                    Eyebrow(label),
                  ],
                ),
                const SizedBox(height: CockpitSpacing.sm),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget pair(int a, int b) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tile(a),
          const SizedBox(width: CockpitSpacing.md),
          tile(b),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Reveal(
          delay: const Duration(milliseconds: 300),
          child: _panel(
            scheme,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: Eyebrow("Octo's read")),
                    StyleMonogram(widget.style, size: 18),
                    const SizedBox(width: CockpitSpacing.xs),
                    Text(
                      widget.style.short,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: CockpitSpacing.md),
                Text(
                  result?.analysis.trim().isNotEmpty == true
                      ? result!.analysis
                      : 'Octo did not return a summary. Your topic is still saved.',
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: CockpitSpacing.md),
        pair(0, 1),
        const SizedBox(height: CockpitSpacing.md),
        pair(2, 3),
      ],
    );
  }

  Future<void> _runLily({
    required LilyMode mode,
    String? requestedType,
    String? customTitle,
  }) async {
    if (_lilyLoading) return;
    setState(() {
      _lilyLoading = true;
      _lilyError = null;
    });
    try {
      final items = await _lily.generate(
        mode: mode,
        analysis: _result,
        essayTopic: _result?.essayTopic.trim().isNotEmpty == true
            ? _result!.essayTopic
            : widget.topic,
        requestedType: requestedType,
        customTitle: customTitle,
      );
      if (!mounted) return;
      setState(() {
        if (mode == LilyMode.auto) {
          _outlines = items;
        } else {
          _outlines = [..._outlines, ...items];
        }
        _mode = null;
        _buildTitle.clear();
        _lilyLoading = false;
      });
      await WizardSession.saveOutlines(_outlines);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lilyError = e.toString();
        _lilyLoading = false;
      });
    }
  }

  Widget _outlineSection(ThemeData theme, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            style: theme.textTheme.titleMedium,
            children: [
              const TextSpan(text: 'Outline '),
              TextSpan(
                text: '(optional)',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: CockpitSpacing.xxs),
        Text(
          'Lily drafts sections from your topic. Pick a mode, or skip and write freely.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: CockpitSpacing.md),
        Row(
          children: [
            _OutlineMode(
              icon: Icons.add_rounded,
              label: 'Build My Way',
              selected: _mode == 'build',
              onTap: _lilyLoading
                  ? null
                  : () => setState(
                      () => _mode = _mode == 'build' ? null : 'build',
                    ),
            ),
            const SizedBox(width: CockpitSpacing.sm),
            _OutlineMode(
              icon: Icons.auto_awesome_rounded,
              label: _lilyLoading && _mode == null
                  ? 'Generating…'
                  : 'Auto Outline',
              selected: false,
              onTap: _lilyLoading ? null : () => _runLily(mode: LilyMode.auto),
            ),
            const SizedBox(width: CockpitSpacing.sm),
            _OutlineMode(
              icon: Icons.notes_rounded,
              label: 'One Paragraph',
              selected: _mode == 'single',
              onTap: _lilyLoading
                  ? null
                  : () => setState(
                      () => _mode = _mode == 'single' ? null : 'single',
                    ),
            ),
          ],
        ),
        if (_mode == 'single') ...[
          const SizedBox(height: CockpitSpacing.md),
          Text(
            'WHICH PARAGRAPH?',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Wrap(
            spacing: CockpitSpacing.sm,
            runSpacing: CockpitSpacing.sm,
            children: [
              for (final t in _types)
                _TypeChip(
                  label: t,
                  selected: false,
                  onTap: _lilyLoading
                      ? null
                      : () => _runLily(mode: LilyMode.single, requestedType: t),
                ),
            ],
          ),
        ],
        if (_mode == 'build') ...[
          const SizedBox(height: CockpitSpacing.md),
          Wrap(
            spacing: CockpitSpacing.sm,
            runSpacing: CockpitSpacing.sm,
            children: [
              for (final t in _types)
                _TypeChip(
                  label: t,
                  selected: _buildType == t,
                  onTap: () => setState(() => _buildType = t),
                ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.sm),
          TextField(
            controller: _buildTitle,
            enabled: !_lilyLoading,
            decoration: InputDecoration(
              hintText: 'What should this paragraph focus on?',
              filled: true,
              fillColor: scheme.onSurface.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CockpitRadii.md),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (v) {
              final title = v.trim();
              if (title.isEmpty) return;
              _runLily(
                mode: LilyMode.build,
                requestedType: _buildType,
                customTitle: title,
              );
            },
          ),
          const SizedBox(height: CockpitSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: WizardPrimaryButton(
              label: _lilyLoading ? 'Building…' : 'Build paragraph',
              dense: true,
              onPressed: _lilyLoading
                  ? null
                  : () {
                      final title = _buildTitle.text.trim();
                      if (title.isEmpty) return;
                      _runLily(
                        mode: LilyMode.build,
                        requestedType: _buildType,
                        customTitle: title,
                      );
                    },
            ),
          ),
        ],
        if (_lilyLoading && _mode == null) ...[
          const SizedBox(height: CockpitSpacing.md),
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: CockpitSpacing.sm),
              Text(
                'Lily is writing your outline…',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
        if (_lilyError != null) ...[
          const SizedBox(height: CockpitSpacing.sm),
          Text(
            _lilyError!,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
        ],
        if (_outlines.isNotEmpty) ...[
          const SizedBox(height: CockpitSpacing.lg),
          for (var i = 0; i < _outlines.length; i++)
            Reveal(
              key: ObjectKey(_outlines[i]),
              delay: Duration(milliseconds: 70 * i),
              child: _WizardOutlineCard(
                outline: _outlines[i],
                onRemove: () async {
                  setState(() => _outlines.removeAt(i));
                  await WizardSession.saveOutlines(_outlines);
                },
              ),
            ),
        ],
      ],
    );
  }
}

class _OutlineMode extends StatelessWidget {
  const _OutlineMode({
    required this.icon,
    required this.label,
    required this.selected,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Expanded(
      child: Pressable(
        enabled: onTap != null,
        pressedScale: 0.95,
        child: Material(
          color: selected
              ? scheme.primary.withValues(alpha: 0.12)
              : scheme.onSurface.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CockpitRadii.md),
            side: BorderSide(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.5)
                  : scheme.onSurface.withValues(alpha: 0.07),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: CockpitSpacing.md,
                horizontal: CockpitSpacing.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: accent),
                  const SizedBox(height: CockpitSpacing.xs),
                  Text(
                    label,
                    textAlign: TextAlign.center,
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
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.label, required this.selected, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Pressable(
      enabled: onTap != null,
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.14)
            : scheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CockpitSpacing.md,
              vertical: CockpitSpacing.sm,
            ),
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WizardOutlineCard extends StatelessWidget {
  const _WizardOutlineCard({required this.outline, required this.onRemove});

  final OutlineData outline;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hue = outline.tagColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: CockpitSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(CockpitSpacing.md),
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(CockpitRadii.md),
          border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
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
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (outline.title.isNotEmpty) ...[
              const SizedBox(height: CockpitSpacing.xs),
              Text(
                outline.title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (outline.description.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                outline.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            for (final b in outline.bullets)
              Padding(
                padding: const EdgeInsets.only(top: 4),
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
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
