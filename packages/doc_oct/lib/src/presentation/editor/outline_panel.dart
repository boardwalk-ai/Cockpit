import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';

import '../../application/assist_service.dart';
import '../../application/backend_config.dart';
import '../../domain/outline.dart';

/// The left-panel Outline — generate a structured plan (Introduction / Body /
/// Conclusion cards with bullets) and drop any section into the essay. Mirrors
/// the web editor's outline cards (tag hue by section type).
class OutlinePanel extends StatefulWidget {
  const OutlinePanel({
    super.key,
    this.topic = '',
    this.onInsertText,
  });

  /// The essay topic (document title) seeding generation.
  final String topic;

  /// Inserts an outline section (title + bullets) at the body cursor.
  final void Function(String text)? onInsertText;

  @override
  State<OutlinePanel> createState() => _OutlinePanelState();
}

class _OutlinePanelState extends State<OutlinePanel> {
  final AssistService _assist = createAssistService();
  List<OutlineData>? _outlines;
  bool _loading = false;
  String? _error;

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _assist.outline(topic: widget.topic);
      if (mounted) setState(() => _outlines = r);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _insert(OutlineData o) {
    final text = '${o.title}\n${o.bullets.map((b) => '• $b').join('\n')}\n';
    widget.onInsertText?.call(text);
  }

  void _remove(int i) => setState(() => _outlines!.removeAt(i));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (_outlines == null) {
      return _empty(theme, scheme);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(CockpitSpacing.md, CockpitSpacing.sm,
              CockpitSpacing.md, CockpitSpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: Text('${_outlines!.length} sections',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ),
              TextButton.icon(
                onPressed: _loading ? null : _generate,
                icon: const Icon(Icons.refresh_rounded, size: 15),
                label: Text(_loading ? 'Working…' : 'Regenerate'),
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: theme.textTheme.labelSmall),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                CockpitSpacing.md, 0, CockpitSpacing.md, CockpitSpacing.md),
            children: [
              for (var i = 0; i < _outlines!.length; i++)
                _OutlineCard(
                  outline: _outlines![i],
                  onInsert: () => _insert(_outlines![i]),
                  onRemove: () => _remove(i),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _empty(ThemeData theme, ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(CockpitSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.segment_rounded,
                size: 26, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: CockpitSpacing.md),
            Text('Nothing here yet',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: CockpitSpacing.xs),
            Text(
              'Generate a structured outline — Introduction, body points, and a '
              'conclusion — then drop any section into your essay.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: CockpitSpacing.md),
            FilledButton.icon(
              onPressed: _loading ? null : _generate,
              icon: _loading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome_rounded, size: 16),
              label: Text(_loading ? 'Generating…' : 'Generate outline'),
            ),
            if (_error != null) ...[
              const SizedBox(height: CockpitSpacing.sm),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.error)),
            ],
          ],
        ),
      ),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: hue.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(CockpitRadii.pill),
                ),
                child: Text(outline.type.toUpperCase(),
                    style: TextStyle(
                        color: hue,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6)),
              ),
              const Spacer(),
              InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.close_rounded,
                      size: 15, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.xs),
          Text(outline.title,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          if (outline.description.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(outline.description,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
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
                      decoration:
                          BoxDecoration(color: hue, shape: BoxShape.circle),
                    ),
                  ),
                  Expanded(
                    child: Text(b,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(height: 1.35)),
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
                  textStyle: theme.textTheme.labelSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
