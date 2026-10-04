import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../motion.dart';
import '../shell_models.dart';
import '../shell_theme.dart';

/// Create, Learn and Organize, coming in one after another. Stacked on
/// phones, side by side when wide.
class ModeCards extends StatelessWidget {
  const ModeCards({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final cards = [
          for (final (i, mode) in ShellMode.values.indexed)
            Reveal(
              delay: Duration(milliseconds: 220 + i * 110),
              child: ModeCard(mode),
            ),
        ];
        if (box.maxWidth >= 600) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, card) in cards.indexed) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: card),
                ],
              ],
            ),
          );
        }
        return Column(
          children: [
            for (final (i, card) in cards.indexed) ...[
              if (i > 0) const SizedBox(height: 12),
              card,
            ],
          ],
        );
      },
    );
  }
}

/// The mode's icon; flies to the Library's header when it opens.
class ModeIcon extends StatelessWidget {
  const ModeIcon(this.mode, {super.key, this.size = 46});

  final ShellMode mode;
  final double size;

  @override
  Widget build(BuildContext context) => Hero(
    tag: 'mode-${mode.name}',
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            mode.color.withValues(alpha: 0.34),
            mode.color.withValues(alpha: 0.12),
          ],
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: mode.color.withValues(alpha: 0.35)),
      ),
      child: Icon(mode.icon, color: mode.color, size: size * 0.5),
    ),
  );
}

class ModeCard extends StatefulWidget {
  const ModeCard(this.mode, {super.key});

  final ShellMode mode;

  @override
  State<ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<ModeCard> {
  var _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    final mode = widget.mode;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        label: mode.title,
        child: Pressable(
          onTap: () {
            Haptics.select();
            context.push(mode.path);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: kShellEase,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color.alphaBlend(
                    mode.color.withValues(alpha: _hover ? 0.16 : 0.09),
                    c.surface,
                  ),
                  c.surface.withValues(alpha: 0.85),
                ],
              ),
              border: Border.all(
                color: _hover
                    ? mode.color.withValues(alpha: 0.6)
                    : c.border.withValues(alpha: 0.9),
              ),
              boxShadow: [
                BoxShadow(
                  color: mode.color.withValues(alpha: _hover ? 0.22 : 0.08),
                  blurRadius: _hover ? 30 : 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                ModeIcon(mode),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mode.title,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        mode.tagline,
                        style: TextStyle(color: c.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                AnimatedSlide(
                  duration: const Duration(milliseconds: 300),
                  curve: kShellEase,
                  offset: Offset(_hover ? 0.25 : 0, 0),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: _hover ? mode.color : c.hint,
                    size: 20,
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
