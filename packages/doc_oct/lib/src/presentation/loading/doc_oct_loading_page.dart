import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';

/// Doc Oct's signature loading screen, restyled borderless: the wordmark, an
/// "Academic Formatter Engine" eyebrow, a circular % ring, a thin bar and a
/// status line — on the charcoal page, no glows or grid.
class DocOctLoadingPage extends StatefulWidget {
  const DocOctLoadingPage({super.key, this.progress, this.onDone});

  /// Fixed progress (0..1) for deterministic rendering; when null the page
  /// animates 0 → 1 and calls [onDone].
  final double? progress;
  final VoidCallback? onDone;

  @override
  State<DocOctLoadingPage> createState() => _DocOctLoadingPageState();
}

class _DocOctLoadingPageState extends State<DocOctLoadingPage>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void initState() {
    super.initState();
    if (widget.progress == null) {
      _c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2600),
      )
        ..addListener(() => setState(() {}))
        ..forward().whenComplete(() => widget.onDone?.call());
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  double get _p => widget.progress ?? _c?.value ?? 0;

  String get _status {
    final pct = _p * 100;
    if (pct < 35) return 'Warming up';
    if (pct < 70) return 'Loading formatter engine';
    if (pct < 99) return 'Almost there';
    return 'Ready';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pct = (_p * 100).round();

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Wordmark
            Text.rich(
              TextSpan(
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontStyle: FontStyle.italic,
                  letterSpacing: -1,
                ),
                children: [
                  TextSpan(
                      text: 'Octopilot ',
                      style: TextStyle(color: scheme.primary)),
                  const TextSpan(text: 'Doc Oct'),
                ],
              ),
            ),
            const SizedBox(height: CockpitSpacing.sm),
            Text(
              'ACADEMIC FORMATTER ENGINE',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                letterSpacing: 3,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: CockpitSpacing.xxxl),
            // Circular % ring
            SizedBox(
              width: 104,
              height: 104,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: _p,
                      strokeWidth: 4,
                      strokeCap: StrokeCap.round,
                      backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
                      valueColor: AlwaysStoppedAnimation(scheme.primary),
                    ),
                  ),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: '$pct',
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      TextSpan(
                        text: '%',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: CockpitSpacing.xl),
            // Thin linear bar
            SizedBox(
              width: 280,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(CockpitRadii.pill),
                child: LinearProgressIndicator(
                  value: _p,
                  minHeight: 3,
                  backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation(scheme.primary),
                ),
              ),
            ),
            const SizedBox(height: CockpitSpacing.lg),
            // Status
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration:
                      BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                ),
                const SizedBox(width: CockpitSpacing.sm),
                Text(_status,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
