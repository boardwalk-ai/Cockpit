import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'mobile_composer.dart';
import 'mobile_motion.dart';
import 'mobile_theme.dart';

/// Phone landing screen: animated greeting in the middle, suggestions and the
/// prompt composer docked at the bottom where the thumb is.
class GhostWriterMobileLanding extends StatefulWidget {
  const GhostWriterMobileLanding({
    super.key,
    required this.controller,
    required this.canStart,
    required this.onChanged,
    required this.onStart,
    this.userName,
    this.onAttach,
    this.attachments,
  });

  final TextEditingController controller;
  final bool canStart;
  final ValueChanged<String> onChanged;
  final VoidCallback onStart;

  /// The "+" button, and the attached files shown in the composer.
  final VoidCallback? onAttach;
  final Widget? attachments;

  /// Shown in the greeting; omitted for guests.
  final String? userName;

  @override
  State<GhostWriterMobileLanding> createState() =>
      _GhostWriterMobileLandingState();
}

class _GhostWriterMobileLandingState extends State<GhostWriterMobileLanding>
    with TickerProviderStateMixin {
  /// Plays once: staggers every element onto the screen.
  late final AnimationController _entry = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );

  /// Loops forever: background drift, ghost float, greeting shine.
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  static const _suggestions = [
    (Icons.edit_note_rounded, 'Draft an essay', 'Write an essay about '),
    (
      Icons.auto_fix_high_rounded,
      'Rewrite a section',
      'Rewrite this section: ',
    ),
    (Icons.menu_book_rounded, 'Polish my sources', 'Polish these sources: '),
    (Icons.short_text_rounded, 'Tighten my intro', 'Tighten this intro: '),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _entry.value = 1;
      _ambient.stop();
    } else {
      if (_entry.status == AnimationStatus.dismissed) _entry.forward();
      if (!_ambient.isAnimating) _ambient.repeat();
    }
  }

  @override
  void dispose() {
    _entry.dispose();
    _ambient.dispose();
    super.dispose();
  }

  void _useSuggestion(String prompt) {
    widget.controller.value = TextEditingValue(
      text: prompt,
      selection: TextSelection.collapsed(offset: prompt.length),
    );
    widget.onChanged(prompt);
  }

  @override
  Widget build(BuildContext context) {
    // On a very short screen (landscape, split view) the suggestions give
    // their room to the greeting and the composer.
    final hideSuggestions =
        widget.canStart || MediaQuery.sizeOf(context).height < 420;

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 16,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: _Hero(
                      entry: _entry,
                      ambient: _ambient,
                      userName: widget.userName,
                    ),
                  ),
                ),
              ),
            ),
            // Suggestions also step aside once the user starts typing.
            AnimatedSize(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: hideSuggestions ? 0 : 1,
                child: hideSuggestions
                    ? const SizedBox(width: double.infinity)
                    : _SuggestionRow(
                        entry: _entry,
                        suggestions: _suggestions,
                        onPick: _useSuggestion,
                      ),
              ),
            ),
            GwReveal(
              animation: _entry,
              from: 0.3,
              to: 0.8,
              offset: const Offset(0, 48),
              child: GwComposer(
                controller: widget.controller,
                canSend: widget.canStart,
                onChanged: widget.onChanged,
                onSend: widget.onStart,
                onAttach: widget.onAttach,
                header: widget.attachments,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.entry, required this.ambient, this.userName});

  final Animation<double> entry;
  final Animation<double> ambient;
  final String? userName;

  @override
  Widget build(BuildContext context) {
    final name = userName;
    final words = ['Hey', name == null ? 'there' : 'there,', ?name];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GwReveal(
          animation: entry,
          from: 0,
          to: 0.4,
          scaleFrom: 0.4,
          child: GwFloatingGhost(ambient: ambient),
        ),
        const SizedBox(height: 14),
        AnimatedBuilder(
          animation: ambient,
          builder: (context, child) {
            // A highlight sweeps across the greeting once per loop.
            final t = (ambient.value * 4).clamp(0.0, 1.0);
            final x = -2.5 + 5 * t;

            return ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment(x - 0.7, 0),
                end: Alignment(x + 0.7, 0),
                colors: const [
                  GwColors.accentSoft,
                  Color(0xFFFFD9DA),
                  GwColors.accentSoft,
                ],
              ).createShader(bounds),
              child: child,
            );
          },
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              for (final (index, word) in words.indexed)
                GwReveal(
                  animation: entry,
                  from: 0.14 + index * 0.09,
                  to: 0.5 + index * 0.09,
                  offset: const Offset(0, 26),
                  child: Text(
                    word,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      height: 1.15,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -1,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        GwReveal(
          animation: entry,
          from: 0.4,
          to: 0.8,
          child: const Text(
            'Draft fast. Revise cleanly.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: GwColors.muted,
              fontFamily: GwFonts.secondary,
              fontFamilyFallback: GwFonts.secondaryFallback,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

/// The ghost artwork, bobbing gently over its shadow.
class GwFloatingGhost extends StatelessWidget {
  const GwFloatingGhost({super.key, required this.ambient});

  final Animation<double> ambient;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ambient,
      child: Image.asset(
        GwAssets.ghost,
        width: 148,
        height: 148,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'GhostWriter',
      ),
      builder: (context, child) {
        // Three bobs per ambient loop.
        final wave = math.sin(ambient.value * 6 * math.pi);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.translate(
              offset: Offset(0, wave * 5),
              child: Transform.rotate(angle: wave * 0.05, child: child),
            ),
            const SizedBox(height: 10),
            // Ground shadow tightens as the ghost rises.
            Container(
              width: 56 + wave * 10,
              height: 1,
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45 + wave * 0.12),
                    blurRadius: 10,
                    spreadRadius: 3,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.entry,
    required this.suggestions,
    required this.onPick,
  });

  final Animation<double> entry;
  final List<(IconData, String, String)> suggestions;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        itemCount: suggestions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (icon, label, prompt) = suggestions[index];

          return GwReveal(
            animation: entry,
            from: 0.5 + index * 0.07,
            to: 0.82 + index * 0.06,
            offset: const Offset(36, 0),
            child: GwPressable(
              haptic: GwHaptic.selection,
              pressedScale: 0.94,
              onTap: () => onPick(prompt),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: GwColors.panel,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: GwColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 17, color: GwColors.accentSoft),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFFD7D7D9),
                        fontFamily: GwFonts.secondary,
                        fontFamilyFallback: GwFonts.secondaryFallback,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
