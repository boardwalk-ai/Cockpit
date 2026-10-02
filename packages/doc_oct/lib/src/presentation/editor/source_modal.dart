import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';

import '../../domain/source.dart';

/// The source modal — read a researched source, optionally humanize its content,
/// select a passage, and insert it into the essay as a quote + in-text citation.
/// Auto Humanize starts from the Tools panel's setting; flipping it here only
/// affects this source (the caller remembers the choice per source).
class SourceModal extends StatefulWidget {
  const SourceModal({
    super.key,
    required this.source,
    required this.inText,
    required this.humanize,
    required this.canHumanize,
    required this.onInsert,
    this.initialHumanize = false,
    this.onHumanizeChanged,
    this.cachedHumanized,
    this.onHumanized,
  });

  final Source source;

  /// The pre-built in-text citation for this source in the active style.
  final String inText;

  /// Humanizes raw source content (via the backend). Only called when
  /// [canHumanize] and the toggle is on.
  final Future<String> Function(String text) humanize;
  final bool canHumanize;

  /// Inserts the final text at the cursor (the caller closes the modal).
  final void Function(String text) onInsert;

  /// Whether Auto Humanize starts on — this source's own choice, else the
  /// panel's Auto Humanize setting.
  final bool initialHumanize;

  /// The user flipped Auto Humanize in this modal (for this source only).
  final ValueChanged<bool>? onHumanizeChanged;

  /// This source's humanized content from an earlier open (skips the call).
  final String? cachedHumanized;

  /// Reports freshly humanized content so reopening this source reuses it.
  final ValueChanged<String>? onHumanized;

  @override
  State<SourceModal> createState() => _SourceModalState();
}

class _SourceModalState extends State<SourceModal> {
  late bool _autoHumanize = widget.canHumanize && widget.initialHumanize;
  String _selected = '';
  late String? _humanized = widget.cachedHumanized; // humanized content
  bool _humanizing = false;

  String get _raw => widget.source.fullContent.trim();

  /// The content currently shown — humanized when the toggle is on and ready.
  String get _shown =>
      (_autoHumanize && _humanized != null) ? _humanized! : _raw;

  @override
  void initState() {
    super.initState();
    if (_autoHumanize && _raw.isNotEmpty) _runHumanize();
  }

  Future<void> _runHumanize() async {
    if (_humanized != null || _raw.isEmpty) return;
    setState(() => _humanizing = true);
    try {
      final h = await widget.humanize(_raw);
      final out = h.trim().isEmpty ? _raw : h.trim();
      if (h.trim().isNotEmpty) widget.onHumanized?.call(out);
      if (mounted) setState(() => _humanized = out);
    } catch (_) {
      if (mounted) setState(() => _humanized = _raw); // fall back to raw
    } finally {
      if (mounted) setState(() => _humanizing = false);
    }
  }

  void _toggleHumanize(bool on) {
    setState(() {
      _selected = '';
      _autoHumanize = on;
    });
    widget.onHumanizeChanged?.call(on);
    if (on) _runHumanize();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = widget.source;
    final domain = Uri.tryParse(s.url)?.host.replaceFirst('www.', '') ?? '';
    final hasContent = _raw.isNotEmpty;
    final quote = '"$_selected" ${widget.inText}';

    return Dialog(
      backgroundColor: scheme.surface,
      insetPadding: const EdgeInsets.all(CockpitSpacing.lg),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(CockpitSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(theme, scheme, s.title, domain),
              const SizedBox(height: CockpitSpacing.sm),
              _citationAndToggle(theme, scheme, hasContent),
              const SizedBox(height: CockpitSpacing.xs),
              Expanded(child: _content(theme, scheme, hasContent)),
              const SizedBox(height: CockpitSpacing.xs),
              if (hasContent)
                Text(
                  _selected.isEmpty
                      ? 'Select a passage above to insert it as a quote.'
                      : '${_selected.length} characters selected',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: CockpitSpacing.sm),
              _actions(quote),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(
    ThemeData theme,
    ColorScheme scheme,
    String title,
    String domain,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (domain.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    domain,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded, size: 20),
          splashRadius: 18,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }

  Widget _citationAndToggle(
    ThemeData theme,
    ColorScheme scheme,
    bool hasContent,
  ) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Citation: ${widget.inText}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (widget.canHumanize) ...[
          Text(
            'Auto Humanize',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 4),
          Switch(
            value: _autoHumanize,
            onChanged: hasContent ? _toggleHumanize : null,
            thumbColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? const Color(0xFF14B8A6)
                  : null,
            ),
          ),
        ],
      ],
    );
  }

  Widget _content(ThemeData theme, ColorScheme scheme, bool hasContent) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CockpitSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(CockpitRadii.md),
      ),
      child: _humanizing
          ? const Center(child: CircularProgressIndicator())
          : hasContent
          ? SingleChildScrollView(
              child: SelectableText(
                _shown,
                style: theme.textTheme.bodyMedium,
                onSelectionChanged: (sel, _) =>
                    setState(() => _selected = sel.textInside(_shown).trim()),
              ),
            )
          : Center(
              child: Text(
                'No readable content for this source yet — you can still '
                'insert its citation.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
    );
  }

  Widget _actions(String quote) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => widget.onInsert(widget.inText),
            child: const Text('Insert citation only'),
          ),
        ),
        const SizedBox(width: CockpitSpacing.sm),
        Expanded(
          child: FilledButton(
            onPressed: _selected.isEmpty ? null : () => widget.onInsert(quote),
            child: const Text('Insert quote + citation'),
          ),
        ),
      ],
    );
  }
}
